/**
 * Минимальный клиент MCP (Streamable HTTP, JSON-RPC 2.0) для сервера Rive
 * Editor — http://127.0.0.1:9791/mcp, или туннель до него.
 *
 * Зачем свой, если Claude Code умеет MCP сам: конфигурация серверов
 * читается при старте сессии, а адрес туннеля меняется. Этот клиент
 * позволяет дотянуться до редактора из уже идущей сессии и из скриптов
 * (например, выгрузить иерархию открытого файла и сверить со спекой).
 *
 * Сервер может отвечать обычным JSON или потоком SSE — поддержано оба.
 */

const PROTOCOL_VERSION = '2025-06-18';

export class RiveMcpClient {
  constructor({ url = process.env.RIVE_MCP_URL || 'http://127.0.0.1:9791/mcp', fetchImpl = fetch, timeoutMs = 30000 } = {}) {
    this.url = url;
    this.fetch = fetchImpl;
    this.timeoutMs = timeoutMs;
    this.sessionId = null;
    this.nextId = 1;
    this.serverInfo = null;
  }

  async initialize() {
    const result = await this.request('initialize', {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: { name: 'teddytales-rig-tools', version: '0.1.0' },
    });
    this.serverInfo = result;
    await this.notify('notifications/initialized');
    return result;
  }

  async listTools() {
    const tools = [];
    let cursor;
    do {
      const page = await this.request('tools/list', cursor ? { cursor } : {});
      tools.push(...(page.tools ?? []));
      cursor = page.nextCursor;
    } while (cursor);
    return tools;
  }

  async callTool(name, args = {}) {
    const result = await this.request('tools/call', { name, arguments: args });
    if (result.isError) {
      const text = (result.content ?? []).map((c) => c.text ?? '').join('\n');
      throw new Error(`инструмент ${name} вернул ошибку: ${text || JSON.stringify(result)}`);
    }
    return result;
  }

  async request(method, params) {
    const id = this.nextId++;
    const body = await this.post({ jsonrpc: '2.0', id, method, params });
    const message = body.find((m) => m.id === id) ?? body[0];
    if (!message) throw new Error(`пустой ответ на ${method}`);
    if (message.error) throw new Error(`${method}: ${message.error.message} (${message.error.code})`);
    return message.result;
  }

  async notify(method, params = {}) {
    await this.post({ jsonrpc: '2.0', method, params }, { expectBody: false });
  }

  async post(payload, { expectBody = true } = {}) {
    const headers = {
      'content-type': 'application/json',
      accept: 'application/json, text/event-stream',
      'mcp-protocol-version': PROTOCOL_VERSION,
    };
    if (this.sessionId) headers['mcp-session-id'] = this.sessionId;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    let response;
    try {
      response = await this.fetch(this.url, { method: 'POST', headers, body: JSON.stringify(payload), signal: controller.signal });
    } catch (error) {
      throw new Error(`нет связи с ${this.url}: ${error.cause?.code ?? error.message}. Открыт ли Rive Editor (Early Access)? Если сервер на другой машине — нужен туннель, см. docs/rive-mcp-setup.md`);
    } finally {
      clearTimeout(timer);
    }

    const session = response.headers.get('mcp-session-id');
    if (session) this.sessionId = session;

    if (!expectBody || response.status === 202 || response.status === 204) return [];
    if (!response.ok) {
      const text = await response.text().catch(() => '');
      throw new Error(`HTTP ${response.status} от ${this.url}: ${text.slice(0, 300)}`);
    }

    const type = response.headers.get('content-type') ?? '';
    const text = await response.text();
    return type.includes('text/event-stream') ? parseSse(text) : asArray(JSON.parse(text));
  }
}

/** Достаёт JSON-RPC сообщения из SSE-потока: каждое событие — строки `data:`. */
export function parseSse(text) {
  const messages = [];
  for (const block of text.split(/\r?\n\r?\n/)) {
    const data = block
      .split(/\r?\n/)
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice(5).trim())
      .join('\n');
    if (!data) continue;
    try {
      messages.push(...asArray(JSON.parse(data)));
    } catch {
      // не-JSON событие (ping, комментарий) — пропускаем
    }
  }
  return messages;
}

const asArray = (value) => (Array.isArray(value) ? value : [value]);

/** Текстовое содержимое ответа инструмента одной строкой. */
export function toolText(result) {
  return (result?.content ?? [])
    .map((c) => (c.type === 'text' ? c.text : `[${c.type}]`))
    .join('\n');
}

/**
 * Вызов инструмента с разбором JSON-ответа и повторами при кратких сбоях
 * редактора: DNS туннеля, пустой ответ, текст ошибки вместо JSON (редактор
 * иногда на секунду «не видит» таймлайн или объект). Повторяются только
 * идемпотентные операции — чтение, запись свойств, перенос, порядок, ключи;
 * загрузка ассета, создание и удаление объектов не повторяются (дубли).
 */
const IDEMPOTENT = /^(session_info|get_|query_|set_property_values|reparent_objects|reorder_objects|rename_objects|animation_editor|mesh_rigging_tool)$/;
export function jsonCaller(client, { tries = 6, delayMs = 3000, log = () => {} } = {}) {
  return async (tool, args) => {
    const retryable = IDEMPOTENT.test(tool) && !(tool === 'mesh_rigging_tool' && args?.command === 'generateMesh')
      || (tool === 'assets_tool' && args?.command === 'listAssets');
    for (let i = 0; ; i++) {
      try {
        const text = toolText(await client.callTool(tool, args));
        let r; try { r = JSON.parse(text); } catch { throw new Error(`${tool}: не JSON: ${text.slice(0, 200)}`); }
        if (r.success === false) throw new Error(`${tool}: ${JSON.stringify(r).slice(0, 300)}`);
        return r;
      } catch (e) {
        const transient = /ENOTFOUND|DNS|fetch failed|пустой ответ|не JSON|not found/i.test(e.message);
        if (!retryable || !transient || i >= tries - 1) throw e;
        log(`  повтор ${tool} (${e.message.slice(0, 80)})`);
        await new Promise((r) => setTimeout(r, delayMs * (1 + (i >> 1))));
      }
    }
  };
}

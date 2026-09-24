import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

import { RiveMcpClient, parseSse, toolText, jsonCaller } from '../lib/rive_mcp.mjs';

/** Mock сервера Rive: JSON на initialize, SSE на tools/*, требует session id. */
function startMock({ sse = true } = {}) {
  const seen = [];
  const server = createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const msg = JSON.parse(body);
      seen.push({ method: msg.method, session: req.headers['mcp-session-id'] ?? null });
      if (msg.method === 'initialize') {
        res.writeHead(200, { 'content-type': 'application/json', 'mcp-session-id': 'sess-42' });
        res.end(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result: { protocolVersion: '2025-06-18', serverInfo: { name: 'rive-mock', version: '0.8' }, capabilities: { tools: {} } } }));
        return;
      }
      if (msg.method === 'notifications/initialized') {
        res.writeHead(202).end();
        return;
      }
      if (req.headers['mcp-session-id'] !== 'sess-42') {
        res.writeHead(400).end('missing session');
        return;
      }
      let result;
      if (msg.method === 'tools/list') result = { tools: [{ name: 'get_hierarchy', description: 'Scene tree\nmore' }, { name: 'create_shape', description: 'x' }] };
      if (msg.method === 'tools/call') result = msg.params.name === 'boom' ? { isError: true, content: [{ type: 'text', text: 'nope' }] } : { content: [{ type: 'text', text: `called ${msg.params.name} with ${JSON.stringify(msg.params.arguments)}` }] };
      const payload = JSON.stringify({ jsonrpc: '2.0', id: msg.id, result });
      if (sse) {
        res.writeHead(200, { 'content-type': 'text/event-stream' });
        res.end(`: ping\n\nevent: message\ndata: ${payload}\n\n`);
      } else {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(payload);
      }
    });
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, seen, url: `http://127.0.0.1:${server.address().port}/mcp` })));
}

test('initialize запоминает session id и шлёт notifications/initialized', async () => {
  const { server, seen, url } = await startMock();
  try {
    const client = new RiveMcpClient({ url });
    const info = await client.initialize();
    assert.equal(info.serverInfo.name, 'rive-mock');
    assert.equal(client.sessionId, 'sess-42');
    assert.deepEqual(seen.map((s) => s.method), ['initialize', 'notifications/initialized']);
    assert.equal(seen[1].session, 'sess-42');
  } finally {
    server.close();
  }
});

test('tools/list и tools/call через SSE-ответы', async () => {
  const { server, url } = await startMock({ sse: true });
  try {
    const client = new RiveMcpClient({ url });
    await client.initialize();
    const tools = await client.listTools();
    assert.deepEqual(tools.map((t) => t.name), ['get_hierarchy', 'create_shape']);
    const result = await client.callTool('get_hierarchy', { artboard: 'Bear_Boy' });
    assert.equal(toolText(result), 'called get_hierarchy with {"artboard":"Bear_Boy"}');
  } finally {
    server.close();
  }
});

test('tools/call через обычный JSON тоже работает', async () => {
  const { server, url } = await startMock({ sse: false });
  try {
    const client = new RiveMcpClient({ url });
    await client.initialize();
    const result = await client.callTool('create_shape', {});
    assert.match(toolText(result), /called create_shape/);
  } finally {
    server.close();
  }
});

test('isError от инструмента превращается в исключение с текстом', async () => {
  const { server, url } = await startMock();
  try {
    const client = new RiveMcpClient({ url });
    await client.initialize();
    await assert.rejects(() => client.callTool('boom'), /nope/);
  } finally {
    server.close();
  }
});

test('недоступный сервер даёт подсказку про редактор и туннель', async () => {
  const client = new RiveMcpClient({ url: 'http://127.0.0.1:1/mcp', timeoutMs: 2000 });
  await assert.rejects(() => client.initialize(), /Rive Editor|туннель/);
});

test('parseSse собирает многострочные data и пропускает мусор', () => {
  const text = ': keepalive\n\nevent: message\ndata: {"jsonrpc":"2.0",\ndata: "id":1,"result":{}}\n\ndata: not json\n\n';
  assert.deepEqual(parseSse(text), [{ jsonrpc: '2.0', id: 1, result: {} }]);
});

/** Заглушка клиента: отдаёт тексты ответов по очереди. */
const stubClient = (texts) => {
  const calls = [];
  return { calls, callTool: async (name, args) => { calls.push(name); return { content: [{ type: 'text', text: texts.shift() }] }; } };
};

test('jsonCaller повторяет идемпотентный вызов после текста ошибки вместо JSON', async () => {
  const client = stubClient(['Error: Linear Animation with id 0-6 not found', '{"success":true,"v":1}']);
  const call = jsonCaller(client, { delayMs: 1 });
  assert.deepEqual(await call('animation_editor', { command: 'queryKeyFrames' }), { success: true, v: 1 });
  assert.equal(client.calls.length, 2);
});

test('jsonCaller не повторяет загрузку ассета (иначе дубли)', async () => {
  const client = stubClient(['Error: upload failed', '{"success":true}']);
  const call = jsonCaller(client, { delayMs: 1 });
  await assert.rejects(call('upload_asset', { file: 'data:' }), /не JSON/);
  assert.equal(client.calls.length, 1);
});

test('jsonCaller: success:false — ошибка без повтора', async () => {
  const client = stubClient(['{"success":false,"error":"bad"}', '{"success":true}']);
  const call = jsonCaller(client, { delayMs: 1 });
  await assert.rejects(call('query_objects', {}), /bad/);
  assert.equal(client.calls.length, 1);
});

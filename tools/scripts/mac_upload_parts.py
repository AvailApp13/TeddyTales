#!/usr/bin/env python3
"""
Запускается НА МАКЕ, рядом с открытым Rive Editor. Загружает все PNG из папки
в открытый файл Rive как ассеты через локальный MCP (127.0.0.1:9791), без
туннеля и без передачи байтов через облако. Печатает JSON {имя: assetId},
его нужно прислать Claude — дальше слои расставляет place_parts.mjs --assets.

    python3 mac_upload_parts.py ~/Desktop/bear_parts

Зависимостей нет: только стандартная библиотека Python 3 (есть в macOS).
"""
import base64, json, os, sys, urllib.parse, urllib.request

URL = 'http://127.0.0.1:9791/mcp'
HEADERS = {'content-type': 'application/json',
           'accept': 'application/json, text/event-stream',
           'mcp-protocol-version': '2025-06-18'}
session = {}
seq = [0]

def post(payload, expect=True):
    h = dict(HEADERS)
    if session.get('id'): h['mcp-session-id'] = session['id']
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(), headers=h, method='POST')
    with urllib.request.urlopen(req, timeout=300) as r:
        sid = r.headers.get('mcp-session-id')
        if sid: session['id'] = sid
        text = r.read().decode()
        ctype = r.headers.get('content-type', '')
    if not expect or not text.strip(): return []
    if 'text/event-stream' in ctype:
        msgs = []
        for block in text.replace('\r\n', '\n').split('\n\n'):
            data = '\n'.join(l[5:].strip() for l in block.split('\n') if l.startswith('data:'))
            if data: msgs.append(json.loads(data))
        return msgs
    body = json.loads(text)
    return body if isinstance(body, list) else [body]

def request(method, params):
    seq[0] += 1
    msgs = post({'jsonrpc': '2.0', 'id': seq[0], 'method': method, 'params': params})
    msg = next((m for m in msgs if m.get('id') == seq[0]), msgs[0] if msgs else None)
    if msg is None: raise SystemExit(f'пустой ответ на {method}')
    if 'error' in msg: raise SystemExit(f"{method}: {msg['error']}")
    return msg['result']

folder = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/Desktop/bear_parts')
files = sorted(f for f in os.listdir(folder) if f.lower().endswith('.png'))
if not files: raise SystemExit(f'в {folder} нет PNG')

request('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                       'clientInfo': {'name': 'teddytales-mac-upload', 'version': '0.1.0'}})
post({'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}}, expect=False)

out = {}
for f in files:
    name = os.path.splitext(f)[0]
    with open(os.path.join(folder, f), 'rb') as fh:
        b64 = base64.b64encode(fh.read()).decode()
    uri = f'data:image/png;name={urllib.parse.quote(f)};base64,{b64}'
    res = request('tools/call', {'name': 'upload_asset', 'arguments': {'file': uri, 'name': name}})
    text = ''.join(c.get('text', '') for c in res.get('content', []) if c.get('type') == 'text')
    try:
        info = json.loads(text)
        a = info['asset']; out[name] = {'asset': a['id'], 'width': a['width'], 'height': a['height']}
        print(f"{name:16s} -> {a['id']}  {a['width']}x{a['height']}", file=sys.stderr)
    except Exception:
        print(f'{name}: {text[:300]}', file=sys.stderr)
print(json.dumps(out, indent=1))

#!/usr/bin/env python3
"""
Запускается НА МАКЕ, рядом с открытым Rive Editor. Загружает все PNG из папки
в открытый файл Rive как ассеты через локальный MCP (127.0.0.1:9791), без
туннеля и без передачи байтов через облако. Печатает JSON {имя: assetId},
его нужно прислать Claude — дальше слои расставляет place_parts.mjs --assets.

    python3 mac_upload_parts.py ~/Desktop/bear_parts

Если в папке нет PNG (или папки нет), скрипт сам скачивает слои из галереи
Higgsfield (ссылки ниже, это результаты в аккаунте Руслана) и кладёт их
туда с правильными именами. full_no_tag.png скачивается для сравнения, в
редактор не грузится.

Зависимостей нет: только стандартная библиотека Python 3 (есть в macOS).
"""
import base64, json, os, sys, urllib.parse, urllib.request

URL = 'http://127.0.0.1:9791/mcp'
PARTS = {'head': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141738_d83b3c2b-33dd-40c1-872b-2c04b8990afc.png',
 'ears': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141748_27cf515b-41fb-4f2b-afba-a17cf9c161f2.png',
 'outfit_head': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141755_a72000b6-fac6-44fc-9fed-91de3010f6ba.png',
 'outfit_body': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_142303_ada9a416-6e6d-4048-a25c-275d4bcfebe4.png',
 'body': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141808_0393cfb4-3d55-4d34-b819-61fa1fe113b6.png',
 'arm_left': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141814_443fc8cc-fcb8-43ef-a55c-99f9a8102f44.png',
 'arm_right': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141823_6785090a-5ba8-4faf-a302-1789ee5ade44.png',
 'leg_left': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141832_c8b9dea6-a207-4a42-ba3e-68f2b196d638.png',
 'leg_right': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141837_468741a2-d7f7-419b-9f85-f58d48dca4a7.png',
 'outfit_feet': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141843_19aba9b4-4b7d-4668-861e-5b753829d0cc.png',
 'face_features': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141849_d062dc9b-3678-431d-a491-c3b7b60e54e8.png',
 'full_no_tag': 'https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7/hf_20260923_141502_54f40bd0-45bc-43f4-8fe2-17fac08fae57.png'}
SKIP_UPLOAD = {'full_no_tag'}
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
    if msg is None: raise RuntimeError(f'пустой ответ на {method}')
    if 'error' in msg: raise RuntimeError(f"{method}: {msg['error']}")
    return msg['result']

def call_tool(name, arguments):
    res = request('tools/call', {'name': name, 'arguments': arguments})
    text = ''.join(c.get('text', '') for c in res.get('content', []) if c.get('type') == 'text')
    return json.loads(text) if text.strip().startswith('{') else {'raw': text}

def existing_assets():
    info = call_tool('assets_tool', {'command': 'listAssets'})
    return {a['name']: a for a in info.get('assets', []) if a.get('type') == 'image'}

folder = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/Desktop/bear_parts')
os.makedirs(folder, exist_ok=True)
for name, url in PARTS.items():
    dst = os.path.join(folder, name + '.png')
    if os.path.exists(dst) and os.path.getsize(dst) > 10000: continue
    print(f'скачиваю {name}.png ...', file=sys.stderr)
    urllib.request.urlretrieve(url, dst)
files = sorted(f for f in os.listdir(folder) if f.lower().endswith('.png') and os.path.splitext(f)[0] not in SKIP_UPLOAD)
if not files: raise SystemExit(f'в {folder} нет PNG')

request('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                       'clientInfo': {'name': 'teddytales-mac-upload', 'version': '0.1.0'}})
post({'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}}, expect=False)

import time
out = {}
have = existing_assets()
for f in files:
    name = os.path.splitext(f)[0]
    if name in have:
        a = have[name]; out[name] = {'asset': a['id'], 'width': a['width'], 'height': a['height']}
        print(f"{name:16s} уже в файле -> {a['id']}", file=sys.stderr); continue
    with open(os.path.join(folder, f), 'rb') as fh:
        b64 = base64.b64encode(fh.read()).decode()
    uri = f'data:image/png;name={urllib.parse.quote(f)};base64,{b64}'
    a = None
    for attempt in range(1, 4):
        try:
            info = call_tool('upload_asset', {'file': uri, 'name': name})
            a = info.get('asset')
            if a: break
            print(f'{name}: {str(info)[:200]}', file=sys.stderr)
        except Exception as e:
            print(f'{name}: попытка {attempt}: {e}', file=sys.stderr)
        time.sleep(5)
        have = existing_assets()
        if name in have: a = have[name]; break
    if not a:
        print(f'{name}: не загрузился', file=sys.stderr); continue
    out[name] = {'asset': a['id'], 'width': a['width'], 'height': a['height']}
    print(f"{name:16s} -> {a['id']}  {a['width']}x{a['height']}", file=sys.stderr)
    time.sleep(2)
print(json.dumps(out, indent=1))

#!/usr/bin/env python3
"""Упаковывает собранное Flutter Web приложение в один самодостаточный HTML.

Зачем: показать живое приложение там, где нет сервера — в предпросмотре,
в письме, на флешке. Обычная сборка Flutter это набор файлов, которые браузер
докачивает по HTTP; здесь всё лежит внутри страницы.

Как это работает
----------------
Наивный путь — перехватывать загрузку CanvasKit — не работает: движок берёт его
через динамический ``import()``, а его не поймать ни патчем ``fetch``, ни
service worker'ом. Поэтому CanvasKit не перехватывается, а **вытесняется**:
готовый объект кладётся в ``window.flutterCanvasKit`` до старта приложения, и
движок берёт его вместо того, чтобы грузить (проверка стоит первой в его цепочке
приоритетов).

Между двумя обычными inline-скриптами нельзя поставить ``await``, поэтому старт
движка откладывается легальной точкой: приложение ищет ``_flutter.loader`` и,
найдя, отдаёт ему инициализатор и останавливается. Мы подставляем свой
минимальный loader и запускаем движок сами, когда обе половины готовы.

Что остаётся снаружи
--------------------
``rive_native`` подтягивается тегом ``<script>`` с CDN, а не через ``fetch`` —
шим его не ловит. В упакованном файле анимация персонажа не поднимется, и
приложение штатно покажет заглушку вместо мишки. Для демонстрации интерфейса
это приемлемо, для боевой сборки wasm Rive надо хостить у себя.

Запуск:
    flutter build web --release
    python3 tool/pack_single_file.py [build/web] [-o teddytales-app.html]
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

# Ассеты, которые приложение запрашивает через fetch. NOTICES (1.3 МБ) не нужен:
# он читается только экраном лицензий, а вес заметный.
ASSET_FILES = [
    'assets/FontManifest.json',
    'assets/AssetManifest.bin',
    'assets/AssetManifest.bin.json',
    'assets/fonts/MaterialIcons-Regular.otf',
    'assets/assets/fonts/Roboto-Light.ttf',
    'assets/assets/fonts/Roboto-Regular.ttf',
    'assets/assets/fonts/Roboto-Medium.ttf',
    'assets/assets/fonts/Roboto-Bold.ttf',
    # Шейдеры при старте не грузятся, но дёргаются на первом ripple и стоят копейки.
    'assets/shaders/ink_sparkle.frag',
    'assets/shaders/stretch_effect.frag',
]

MIME = {
    '.json': 'application/json',
    '.bin': 'application/octet-stream',
    '.otf': 'font/otf',
    '.ttf': 'font/ttf',
    '.frag': 'text/plain',
    '.riv': 'application/octet-stream',
    '.png': 'image/png',
}

# Адрес, по которому движок жёстко просит Roboto, если не нашёл семейство в
# манифесте. Мы семейство объявили, но подстраховка дешёвая.
ROBOTO_MARKER = 'KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2'


def patch_canvaskit(src: str) -> str:
    """Превращает ESM-модуль CanvasKit в обычный скрипт.

    ``import.meta`` — синтаксическая ошибка вне модуля, поэтому оба вхождения
    надо убрать, даже то, что лежит в мёртвой ветке: код обязан хотя бы
    распарситься.
    """
    replacements = [
        ('var _scriptName = import.meta.url;', 'var _scriptName = "";'),
        ('(new URL("canvaskit.wasm",import.meta.url)).href', '"canvaskit.wasm"'),
        ('export default CanvasKitInit;', 'globalThis.CanvasKitInit=CanvasKitInit;'),
    ]
    for old, new in replacements:
        if old not in src:
            raise SystemExit(
                'Не найден фрагмент CanvasKit для замены:\n  ' + old + '\n'
                'Похоже, поменялась версия Flutter — сверьте упаковщик с '
                'canvaskit.js из свежей сборки.'
            )
        src = src.replace(old, new, 1)

    if 'import.meta' in src:
        raise SystemExit('В canvaskit.js остался import.meta — вне модуля это не запустится.')
    return src


def read_b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode('ascii')


def guard(name: str, text: str) -> str:
    """Проверяет, что инлайн-скрипт не разорвёт HTML."""
    for bad in ('</script', '<!--'):
        if bad in text:
            raise SystemExit(
                f'В {name} встретилось {bad!r} — инлайнить без экранирования нельзя.'
            )
    return text


def build(build_dir: Path, out: Path, title: str, fragment: bool = False) -> None:
    canvaskit_js = build_dir / 'canvaskit' / 'canvaskit.js'
    canvaskit_wasm = build_dir / 'canvaskit' / 'canvaskit.wasm'
    main_js = build_dir / 'main.dart.js'

    for f in (canvaskit_js, canvaskit_wasm, main_js):
        if not f.exists():
            raise SystemExit(f'Нет файла {f}. Сначала: flutter build web --release')

    print('Патчу CanvasKit…')
    ck_src = guard('canvaskit.js', patch_canvaskit(canvaskit_js.read_text(encoding='utf-8')))

    print('Читаю main.dart.js…')
    main_src = guard('main.dart.js', main_js.read_text(encoding='utf-8'))

    print('Кодирую canvaskit.wasm…')
    wasm_b64 = read_b64(canvaskit_wasm)

    print('Собираю ассеты…')
    assets: dict[str, dict[str, str]] = {}
    for rel in ASSET_FILES:
        f = build_dir / rel
        if not f.exists():
            print(f'  пропускаю {rel} — нет в сборке')
            continue
        assets[rel] = {
            'b64': read_b64(f),
            'mime': MIME.get(f.suffix, 'application/octet-stream'),
        }
        print(f'  {rel} — {f.stat().st_size} Б')

    roboto = assets.get('assets/assets/fonts/Roboto-Regular.ttf')

    template = FRAGMENT_TEMPLATE if fragment else PAGE_TEMPLATE
    page = template.format(
        title=title,
        assets_json=json.dumps(assets, separators=(',', ':')),
        roboto_marker=ROBOTO_MARKER,
        roboto_key='assets/assets/fonts/Roboto-Regular.ttf' if roboto else '',
        wasm_b64=wasm_b64,
        canvaskit_js=ck_src,
        main_js=main_src,
    )

    out.write_text(page, encoding='utf-8')
    size = out.stat().st_size
    print(f'\nГотово: {out}  —  {size / 1024 / 1024:.1f} МБ')
    if size > 16 * 1024 * 1024:
        print('ВНИМАНИЕ: больше 16 МБ — в предпросмотр такой файл не примут.')


PAGE_TEMPLATE = '''<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{title}</title>
<style>
  html, body {{ margin: 0; padding: 0; height: 100%; background: #F6F1EB; }}
  #boot {{
    position: fixed; inset: 0; display: grid; place-items: center;
    font: 15px/1.5 system-ui, sans-serif; color: #8C7A66; text-align: center;
  }}
  #boot p {{ max-width: 320px; }}
</style>
</head>
<body>
<div id="boot"><p>Загружаю приложение…</p></div>

<!-- S1. Шим сети и отложенный старт движка. -->
<script>
(() => {{
  'use strict';

  const ASSETS = {assets_json};
  const ROBOTO_MARKER = {roboto_marker!r};
  const ROBOTO_KEY = {roboto_key!r};

  const decode = (b64) => {{
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }};

  const cache = new Map();
  const get = (key) => {{
    if (!cache.has(key)) cache.set(key, decode(ASSETS[key].b64));
    return cache.get(key);
  }};

  // Приложение не знает, что сервера нет: все его запросы обслуживаются отсюда.
  // Наружу не выпускаем ничего — иначе на странице со строгой политикой
  // безопасности запрос либо упадёт с ошибкой, либо повиснет.
  window.fetch = (input, init) => {{
    const url = typeof input === 'string' ? input : (input && input.url) || '';

    if (ROBOTO_KEY && url.includes(ROBOTO_MARKER)) {{
      const bytes = get(ROBOTO_KEY);
      return Promise.resolve(new Response(bytes, {{
        status: 200, headers: {{ 'Content-Type': 'font/ttf' }},
      }}));
    }}

    for (const key of Object.keys(ASSETS)) {{
      if (url.endsWith(key)) {{
        const bytes = get(key);
        return Promise.resolve(new Response(bytes, {{
          status: 200, headers: {{ 'Content-Type': ASSETS[key].mime }},
        }}));
      }}
    }}

    // Например, .riv персонажа: в демо-сборке его нет, и приложение штатно
    // показывает заглушку вместо мишки.
    return Promise.resolve(new Response(null, {{ status: 404 }}));
  }};

  // Приложение ищет _flutter.loader, отдаёт ему инициализатор и останавливается.
  // Мы стартуем движок сами — когда CanvasKit будет готов.
  let initializer = null;
  let canvasKitReady = false;

  const maybeStart = async () => {{
    if (!initializer || !canvasKitReady) return;
    const boot = document.getElementById('boot');
    try {{
      const app = await initializer.initializeEngine();
      await app.runApp();
      if (boot) boot.remove();
    }} catch (e) {{
      if (boot) boot.innerHTML = '<p>Не удалось запустить: ' + e + '</p>';
      throw e;
    }}
  }};

  window._flutter = {{
    loader: {{
      didCreateEngineInitializer: (init) => {{ initializer = init; maybeStart(); }},
    }},
  }};

  window.__teddyCanvasKitReady = (ck) => {{
    window.flutterCanvasKit = ck;
    window.flutterCanvasKitLoaded = Promise.resolve(ck);
    canvasKitReady = true;
    maybeStart();
  }};

  window.__teddyWasm = decode({wasm_b64!r});
}})();
</script>

<!-- S2. CanvasKit, переведённый из модуля в обычный скрипт. -->
<script>
{canvaskit_js}
</script>

<!-- S3. Инициализация CanvasKit из памяти, без единого запроса. -->
<script>
CanvasKitInit({{
  instantiateWasm: (imports, callback) => {{
    // Именно так, а не через compileStreaming: у нас нет ответа с
    // Content-Type: application/wasm, и потоковая компиляция бы его потребовала.
    WebAssembly.instantiate(window.__teddyWasm, imports)
      .then((r) => callback(r.instance, r.module));
    return {{}};
  }},
}}).then((ck) => window.__teddyCanvasKitReady(ck));
</script>

<!-- S4. Само приложение. -->
<script>
{main_js}
</script>
</body>
</html>
'''


FRAGMENT_TEMPLATE = (
    PAGE_TEMPLATE
    .replace('<!DOCTYPE html>\n<html lang="ru">\n<head>\n', '')
    .replace('<meta charset="UTF-8">\n', '')
    .replace(
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n',
        '',
    )
    .replace('</head>\n<body>\n', '')
    .replace('</body>\n</html>\n', '')
)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('build_dir', nargs='?', default='build/web', type=Path)
    ap.add_argument('-o', '--out', default='teddytales-app.html', type=Path)
    ap.add_argument('--title', default='TeddyTales')
    ap.add_argument(
        '--fragment',
        action='store_true',
        help='без <!DOCTYPE>/<html>/<head>/<body> — для площадок, которые '
             'оборачивают содержимое в свой скелет документа',
    )
    args = ap.parse_args()

    build(args.build_dir, args.out, args.title, args.fragment)
    return 0


if __name__ == '__main__':
    sys.exit(main())

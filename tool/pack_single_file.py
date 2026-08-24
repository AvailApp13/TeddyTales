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

Рантайм Rive
------------
``rive_native`` тоже внутри — и js, и wasm. Его загрузчик вставляет
``<script src=...>``, поймать который шимом ``fetch`` нельзя, поэтому сам
скрипт вшит в страницу обычным тегом, а загрузчику подставляется пустышка.
Подробности — у константы ``RIVE_JS`` ниже.

Запуск:
    flutter build web --release \\
        --dart-define=RIVE_NATIVE_WASM_HOST=data:text/javascript,//#
    python3 tool/pack_single_file.py [build/web] [-o teddytales-app.html]

Для обычной сборки под сервер define другой — пустой:
    --dart-define=RIVE_NATIVE_WASM_HOST=
"""

from __future__ import annotations

import argparse
import base64
import gzip
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
    # Без него эмодзи-заглушки предметов превращаются в квадраты: движок за
    # недостающими глифами ходит в сеть, а её здесь нет.
    'assets/assets/fonts/NotoColorEmoji-Subset.ttf',
    # Шейдеры при старте не грузятся, но дёргаются на первом ripple и стоят копейки.
    'assets/shaders/ink_sparkle.frag',
    'assets/shaders/stretch_effect.frag',
]

# Рантайм анимации Rive. Подключается отдельно от остального: его загрузчик
# вставляет <script src=...>, а такой тег ни перехватить, ни выполнить из
# памяти нельзя. Обходим так: сам скрипт вшиваем в страницу обычным тегом, а
# загрузчику подсовываем пустую data:-заглушку, которая мгновенно «загрузится».
# К этому моменту window.RiveNative уже определён, и загрузчик его подхватит.
# Чтобы это сработало, приложение должно быть собрано с
#     --dart-define=RIVE_NATIVE_WASM_HOST=data:text/javascript,//#
RIVE_JS = 'wasm/rive_native.js'
RIVE_WASM = 'wasm/rive_native.wasm'

MIME = {
    '.json': 'application/json',
    '.bin': 'application/octet-stream',
    '.otf': 'font/otf',
    '.ttf': 'font/ttf',
    '.frag': 'text/plain',
    '.riv': 'application/octet-stream',
    '.jpg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
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
    """Сжимает файл и кодирует в base64.

    Base64 раздувает данные на треть, поэтому без сжатия страница не влезает
    в лимит. Распаковкой занимается сам браузер — DecompressionStream есть
    во всех актуальных.
    """
    return gz_b64(path.read_bytes())


def gz_b64(data: bytes) -> str:
    packed = gzip.compress(data, 9)
    return base64.b64encode(packed).decode('ascii')


def guard(name: str, text: str) -> str:
    """Проверяет, что инлайн-скрипт не разорвёт HTML."""
    for bad in ('</script', '<!--'):
        if bad in text:
            raise SystemExit(
                f'В {name} встретилось {bad!r} — инлайнить без экранирования нельзя.'
            )
    return text


def _trim_font_manifest(assets: dict[str, dict[str, str]]) -> None:
    """Выбрасывает из манифеста начертания, которых нет в упаковке.

    Иначе движок пойдёт за ними по сети, получит от шима 404 и будет ругаться
    в консоль на каждом запуске.
    """
    key = 'assets/FontManifest.json'
    entry = assets.get(key)
    if entry is None:
        return

    manifest = json.loads(
        gzip.decompress(base64.b64decode(entry['b64'])).decode('utf-8')
    )
    for family in manifest:
        family['fonts'] = [
            f for f in family['fonts']
            if 'assets/' + f['asset'] in assets or f['asset'] in assets
        ]

    trimmed = json.dumps(manifest, ensure_ascii=False).encode('utf-8')
    assets[key] = {'b64': gz_b64(trimmed), 'mime': 'application/json'}


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

    # Риг персонажа: если он уже лежит в сборке, кладём внутрь — тогда в
    # упакованном файле персонаж будет живой, а не заглушкой.
    for rig in sorted((build_dir / 'assets' / 'assets' / 'rive').glob('*.riv')):
        rel = str(rig.relative_to(build_dir))
        assets[rel] = {'b64': read_b64(rig), 'mime': MIME['.riv']}
        print(f'  {rel} — {rig.stat().st_size} Б')

    # Картинки приложения (фото героя для пазла и всё, что появится рядом).
    images_dir = build_dir / 'assets' / 'assets' / 'images'
    if images_dir.exists():
        for image in sorted(images_dir.iterdir()):
            mime = MIME.get(image.suffix.lower())
            if mime is None:
                continue
            rel = str(image.relative_to(build_dir))
            assets[rel] = {'b64': read_b64(image), 'mime': mime}
            print(f'  {rel} — {image.stat().st_size} Б')

    rive_js_file = build_dir / RIVE_JS
    rive_wasm_file = build_dir / RIVE_WASM
    rive_js = ''
    if rive_js_file.exists() and rive_wasm_file.exists():
        rive_js = guard('rive_native.js', rive_js_file.read_text(encoding='utf-8'))
        assets[RIVE_WASM] = {
            'b64': read_b64(rive_wasm_file),
            'mime': 'application/wasm',
        }
        print(f'  {RIVE_WASM} — {rive_wasm_file.stat().st_size} Б')
    else:
        print('  рантайм Rive не найден — персонаж будет заглушкой')

    _trim_font_manifest(assets)

    roboto = assets.get('assets/assets/fonts/Roboto-Regular.ttf')

    template = FRAGMENT_TEMPLATE if fragment else PAGE_TEMPLATE
    page = template.format(
        title=title,
        assets_json=json.dumps(assets, separators=(',', ':')),
        roboto_marker=ROBOTO_MARKER,
        roboto_key='assets/assets/fonts/Roboto-Regular.ttf' if roboto else '',
        wasm_b64=wasm_b64,
        canvaskit_js=ck_src,
        rive_js=rive_js,
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

  // Всё вложенное лежит сжатым: без этого страница не влезает в лимит размера.
  // Распаковывает сам браузер, штатным DecompressionStream.
  const inflate = async (b64) => {{
    const packed = decode(b64);
    const stream = new Blob([packed]).stream()
      .pipeThrough(new DecompressionStream('gzip'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }};
  window.__teddyInflate = inflate;

  const cache = new Map();
  const get = async (key) => {{
    if (!cache.has(key)) cache.set(key, await inflate(ASSETS[key].b64));
    return cache.get(key);
  }};

  // Приложение не знает, что сервера нет: все его запросы обслуживаются отсюда.
  // Наружу не выпускаем ничего — иначе на странице со строгой политикой
  // безопасности запрос либо упадёт с ошибкой, либо повиснет.
  window.fetch = async (input, init) => {{
    const url = typeof input === 'string' ? input : (input && input.url) || '';

    const serve = async (key, mime) => new Response(await get(key), {{
      status: 200,
      headers: {{ 'Content-Type': mime || ASSETS[key].mime }},
    }});

    if (ROBOTO_KEY && url.includes(ROBOTO_MARKER)) {{
      return serve(ROBOTO_KEY, 'font/ttf');
    }}

    for (const key of Object.keys(ASSETS)) {{
      if (url.endsWith(key)) return serve(key);
    }}

    // Вшитый скрипт не знает своего каталога, поэтому просит соседний файл без
    // пути — например rive_native.wasm вместо wasm/rive_native.wasm.
    // Досопоставляем по имени файла.
    const base = url.split('?')[0].split('#')[0].split('/').pop();
    if (base) {{
      for (const key of Object.keys(ASSETS)) {{
        if (key.split('/').pop() === base) return serve(key);
      }}
    }}

    // Неизвестный адрес: наружу не выпускаем, отвечаем сами.
    return new Response(null, {{ status: 404 }});
  }};

  // Загрузчик Rive вставляет в документ <script src=...> и ждёт от него события
  // load. Настоящий скрипт уже вшит в страницу ниже, поэтому вставляемый тег
  // нужен только ради события — но на площадке со строгой политикой
  // безопасности он не выполнится, события не будет, и загрузчик зависнет
  // навсегда. Поэтому такой тег в документ не попадает вовсе: мы сразу шлём
  // ему load.
  const STUB_PREFIX = 'data:text/javascript';

  const isStub = (node) =>
    node && node.tagName === 'SCRIPT' &&
    typeof node.src === 'string' && node.src.startsWith(STUB_PREFIX);

  const fireLoad = (node) =>
    queueMicrotask(() => node.dispatchEvent(new Event('load')));

  const origAppend = Element.prototype.append;
  Element.prototype.append = function (...nodes) {{
    const rest = nodes.filter((n) => (isStub(n) ? (fireLoad(n), false) : true));
    if (rest.length) origAppend.apply(this, rest);
  }};

  const origAppendChild = Node.prototype.appendChild;
  Node.prototype.appendChild = function (node) {{
    if (isStub(node)) {{
      fireLoad(node);
      return node;
    }}
    return origAppendChild.call(this, node);
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

  window.__teddyWasm = inflate({wasm_b64!r});
}})();
</script>

<!-- S2. CanvasKit, переведённый из модуля в обычный скрипт. -->
<script>
{canvaskit_js}
</script>

<!-- S3. Инициализация CanvasKit из памяти, без единого запроса. -->
<script>
(async () => {{
  const wasm = await window.__teddyWasm;
  const ck = await CanvasKitInit({{
    instantiateWasm: (imports, callback) => {{
      // Именно так, а не через compileStreaming: у нас нет ответа с
      // Content-Type: application/wasm, и потоковая компиляция бы его
      // потребовала.
      WebAssembly.instantiate(wasm, imports)
        .then((r) => callback(r.instance, r.module));
      return {{}};
    }},
  }});
  window.__teddyCanvasKitReady(ck);
}})();
</script>

<!-- S3b. Рантайм анимации Rive: определяет window.RiveNative заранее. -->
<script>
{rive_js}
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

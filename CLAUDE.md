# Работа над TeddyTales

## Показывать результат, а не описывать его

Заказчик смотрит работу в панели справа (артефакт), а не в терминале и не по
ссылке в браузере. Скриншоты не подходят — ему нужно приложение, которое
можно потрогать.

**После каждого изменения, которое видно на экране, обновлять живое
приложение:**

```
flutter build web --release --base-href /TeddyTales/ --dart-define=RIVE_NATIVE_WASM_HOST=
```

затем скопировать `build/web` во временную папку, выбросить лишнее
(`canvaskit/skwasm*`, `canvaskit/experimental_webparagraph`, `canvaskit/wimp*`,
`canvaskit/*.symbols`, `flutter_service_worker.js`), заменить в `index.html`
`<base href="/TeddyTales/">` на `<base href="./">` — и опубликовать тем же
`file_path`, что и в прошлый раз: адрес артефакта тогда сохранится.

Живое приложение: https://claude.ai/artifact/KBHgmyHzzPGZrYGr5u3SQd

Тонкости публикации: артефакт не отдаёт `application/octet-stream`, поэтому
`assets/AssetManifest.bin` и `.riv` публикуются с `contentType:
"application/wasm"`, `.frag`, `NOTICES` и `.symbols` — с `text/plain`.

Веб-версия по адресу https://availapp13.github.io/TeddyTales/ (ветка
`gh-pages`) остаётся как запасной вариант, но заказчик ей не пользуется.

## Правки только по команде

Ничего не менять в коде по своей инициативе. Заметил проблему — сказать о
ней и дождаться решения.

## Чужие проекты

Avail (VVL) и всё, что к нему относится, в этой работе не трогать ни при
каких обстоятельствах. TeddyTales — отдельная организация и отдельный проект
Supabase (`bwvwzzquiepghebskaib`).

## Ветка

Разработка и пуш — только в `claude/greeting-5sa20d`.

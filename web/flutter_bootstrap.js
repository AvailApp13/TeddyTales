// Свой загрузчик Flutter Web вместо стандартного.
//
// Единственное отличие от того, что генерирует Flutter: CanvasKit берётся из
// сборки (`canvaskit/`), а не с www.gstatic.com. Иначе приложение не
// запускается там, где нет выхода в CDN, — в закрытом контуре, в CI и в
// офлайн-режиме, который требует КП 1.1.
//
// Файлы CanvasKit и так лежат в `build/web/canvaskit/` после каждой сборки,
// так что это не увеличивает бандл — только убирает внешний запрос.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});

# assets/rive

Сюда кладутся экспортированные из Rive Editor файлы (пункт 10 ТЗ аниматора).

| Файл | Что это | Константа в коде |
| --- | --- | --- |
| `bear_main.riv` | основной персонаж: артборд и State Machine `bear_main`, 108 клипов | `BearRigSpec.assetPath` |
| `birth_scene.riv` | сцена рождения, отдельный артборд, вне основной State Machine | `BearRigSpec.birthSceneAssetPath` |

Пока файлов нет, `BearView` рендерит плейсхолдер вместо падения — приложение
собирается и запускается без рига.

## Требования к экспорту

- Тариф Rive **Cadet** ($9/мес) — безлимитный экспорт `.riv` для продакшена.
- Naming convention в файле: `Workspace → Admin → Options → Naming convention → snake_case`.
- Размер: не более 3 МБ для `bear_main.riv`, не более 4 МБ для `birth_scene.riv`
  (раздел 9 ТЗ аниматора).
- Имена артборда, State Machine и всех входов должны совпадать с
  `lib/bear/bear_rig_spec.dart`. Если в редакторе имена другие — правится один
  файл спецификации, код трогать не нужно.

## Чеклисты

- Именование частей и порядок слоёв — `docs/rig-naming.md`
- Входы State Machine — раздел 8.1 в `docs/tz-animator.md`

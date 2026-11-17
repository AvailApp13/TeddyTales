/// Задания обучения из панели управления (КП 9.4, 15.5, таблица
/// `edu_tasks`). До 17.11 все 300 заданий были зашиты в сборку.
///
/// Уровень берётся с сервера, только если в панели он полный — десять
/// заданий с вопросом на трёх языках, четырьмя вариантами и верным ответом
/// среди них. Иначе — уровень из сборки ([eduContent]): ребёнок не должен
/// увидеть полупустой уровень из-за недописанной строки. Без сети — тоже
/// из сборки (КП 1.1).
library;

import 'learning_content.dart';

abstract final class EduTasks {
  static Map<String, Map<int, List<EduTask>>> _server = const {};

  /// Уровни категории: с сервера, где он полный, иначе из сборки.
  static List<List<EduTask>> levels(String category) {
    final built = eduContent[category] ?? const <List<EduTask>>[];
    final server = _server[category];
    if (server == null) return built;
    return [
      for (var i = 0; i < built.length; i++) server[i + 1] ?? built[i],
    ];
  }

  /// Взять строки панели `{category, level, idx, ru, en, zh, options,
  /// correct}`.
  static void applyServer(Object? rows) {
    if (rows is! List) return;
    final byLevel = <String, Map<int, Map<int, EduTask>>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final task = _task(row);
      final category = row['category'];
      final level = row['level'], idx = row['idx'];
      if (task == null || category is! String) continue;
      if (level is! int || idx is! int) continue;
      if (idx < 1 || idx > eduTasksPerLevel) continue;
      ((byLevel[category] ??= {})[level] ??= {})[idx] = task;
    }
    _server = {
      for (final MapEntry(key: category, value: levels) in byLevel.entries)
        category: {
          for (final MapEntry(key: level, value: tasks) in levels.entries)
            if (tasks.length == eduTasksPerLevel)
              level: [for (var i = 1; i <= eduTasksPerLevel; i++) tasks[i]!],
        },
    };
  }

  static EduTask? _task(Map<dynamic, dynamic> row) {
    final ru = row['ru'], en = row['en'], zh = row['zh'];
    final options = row['options'], correct = row['correct'];
    if (ru is! String || en is! String || zh is! String) return null;
    if ([ru, en, zh].any((t) => t.trim().isEmpty)) return null;
    if (options is! List || options.length != 4) return null;
    if (options.any((o) => o is! String || o.trim().isEmpty)) return null;
    // Повтор среди вариантов — два одинаковых ответа, один «неверный».
    if (options.toSet().length != 4) return null;
    if (correct is! int || correct < 0 || correct > 3) return null;
    return EduTask(ru, en, zh, List<String>.unmodifiable(options), correct);
  }

  /// Забыть задания панели — для тестов.
  static void reset() => _server = const {};
}

import 'package:flutter/foundation.dart';

import 'local_cache.dart';
import 'memory_store.dart';
import 'pet_snapshot.dart';
import 'progress_store.dart';
import 'supabase_store.dart';

/// Чем закончился запуск: с чем работать и удалось ли достучаться до сервера.
class BootResult {
  const BootResult({
    required this.store,
    required this.snapshot,
    required this.isOnline,
    this.cache,
    this.error,
  });

  final ProgressStore store;
  final PetSnapshot snapshot;

  /// Кеш на устройстве. `null` — хранилище не поднялось.
  final LocalCache? cache;

  /// Работаем ли с сервером. `false` — запустились офлайн (КП 1.1).
  final bool isOnline;

  /// Почему не вышло. Показывать пользователю не нужно, но в отладке это
  /// единственный способ отличить «нет сети» от «сломали схему».
  final String? error;
}

/// Поднимает хранилище прогресса при старте приложения.
///
/// Порядок один и тот же: подключиться, войти без регистрации (КП 1.2),
/// забрать состояние (КП 1.4). Любой сбой на любом шаге — не ошибка запуска,
/// а переход в офлайн: КП 1.1 требует, чтобы приложение работало без сети на
/// последних данных, а не показывало экран с крестиком.
///
/// Таймаут стоит намеренно и намеренно короткий. Без него приложение с
/// неотвечающей сетью висит на пустом экране до срабатывания системного
/// таймаута, а это десятки секунд — пользователь успевает решить, что оно
/// сломано, и закрыть его.
abstract final class Bootstrap {
  static const Duration timeout = Duration(seconds: 8);

  static Future<BootResult> start() async {
    final cache = await LocalCache.open();

    if (!BackendConfig.isConfigured) {
      return _offline('бэкенд не настроен', cache);
    }

    try {
      final store = await SupabaseStore.connect().timeout(timeout);
      await store.signIn().timeout(timeout);
      final snapshot = await store.load().timeout(timeout);
      // Свежий ответ сразу уходит в кеш: следующий запуск без сети покажет
      // его, а не пустого новорождённого.
      await cache?.save(snapshot);
      return BootResult(
        store: store,
        snapshot: snapshot,
        isOnline: true,
        cache: cache,
      );
    } on Object catch (error) {
      // Сюда попадает и отсутствие сети, и отказ сервера, и расхождение
      // схемы. Для пользователя разницы нет — игра в любом случае должна
      // открыться.
      debugPrint('[TeddyTales] офлайн: $error');
      return _offline(error.toString(), cache);
    }
  }

  static BootResult _offline(String reason, LocalCache? cache) {
    // Последнее, что видел игрок, лучше пустого места: он вернётся к своему
    // подросшему мишке, а не к чужому новорождённому (КП 1.1).
    final saved = cache?.load();
    final store = MemoryStore(initial: saved);
    return BootResult(
      store: store,
      snapshot: saved ?? MemoryStore.emptySnapshot(),
      isOnline: false,
      cache: cache,
      error: reason,
    );
  }
}

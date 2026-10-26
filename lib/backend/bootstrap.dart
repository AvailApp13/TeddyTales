import 'package:flutter/foundation.dart';

import 'email_auth.dart';
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
    this.auth,
    this.hasSession = false,
  });

  final ProgressStore store;
  final PetSnapshot snapshot;

  /// Кеш на устройстве. `null` — хранилище не поднялось.
  final LocalCache? cache;

  /// Работаем ли с сервером. `false` — запустились офлайн (КП 1.1).
  final bool isOnline;

  /// Учётная запись: вход и регистрация по почте, выход. `null` — сервер не
  /// настроен или не поднялся.
  final AccountAuth? auth;

  /// Входил ли человек на этом устройстве. Нет — сначала стартовая
  /// страница со способами входа.
  final bool hasSession;

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

  /// [guest] — человек нажал «Пропустить» (или способ входа, который ещё
  /// не подключён): пускаем без регистрации, анонимно (КП 1.2). Иначе без
  /// сохранённой сессии ничего не заводим — сначала стартовая страница.
  static Future<BootResult> start({bool guest = false}) async {
    final cache = await LocalCache.open();

    if (!BackendConfig.isConfigured) {
      return _offline('бэкенд не настроен', cache);
    }

    final SupabaseStore store;
    try {
      store = await SupabaseStore.connect().timeout(timeout);
    } on Object catch (error) {
      debugPrint('[TeddyTales] офлайн: $error');
      return _offline(error.toString(), cache);
    }

    if (!store.isSignedIn && !guest) {
      // Никто не входил: стартовая страница. Прогресса ещё нет, а кеш мог
      // остаться от прежнего человека — его не показываем.
      return BootResult(
        store: MemoryStore(),
        snapshot: MemoryStore.emptySnapshot(),
        isOnline: false,
        cache: cache,
        auth: store,
      );
    }

    try {
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
        auth: store,
        hasSession: true,
      );
    } on Object catch (error) {
      // Сюда попадает и отсутствие сети, и отказ сервера, и расхождение
      // схемы. Для пользователя разницы нет — игра в любом случае должна
      // открыться.
      debugPrint('[TeddyTales] офлайн: $error');
      final offline = _offline(error.toString(), cache);
      return BootResult(
        store: offline.store,
        snapshot: offline.snapshot,
        isOnline: false,
        cache: cache,
        error: offline.error,
        auth: store,
        hasSession: store.isSignedIn,
      );
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

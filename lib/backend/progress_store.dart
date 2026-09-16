import '../bear/bear_action.dart';
import 'pet_snapshot.dart';

/// Откуда приложение берёт прогресс и куда его отдаёт.
///
/// Интерфейс, а не прямые вызовы Supabase, нужен ради КП 1.1: при отсутствии
/// сети приложение работает на последних данных. Экраны не должны знать,
/// отвечает им сервер или память, — иначе офлайн пришлось бы разбирать в
/// каждом экране отдельно.
///
/// Все действия возвращают новый снимок целиком, а не «ок». Так решает
/// сервер: покормить — это и показатели, и монеты, и событие для расчёта
/// характера; посчитать результат на клиенте значит рано или поздно
/// разойтись с сервером в цифрах.
abstract interface class ProgressStore {
  /// Вошли ли мы. Без входа остальные методы бросают исключение.
  bool get isSignedIn;

  /// Вход без регистрации (КП 1.2): аккаунт создаётся сам при первом
  /// запуске, у пользователя ничего не спрашивают.
  Future<void> signIn();

  /// Состояние игрока целиком (КП 1.4).
  Future<PetSnapshot> load();

  /// Действие ухода (КП 6.4). Насколько поднимется показатель и сколько
  /// дадут монет, решает сервер по настройкам (КП 15.4).
  Future<PetSnapshot> recordCare(BearAction action);

  /// Покупка предмета за монеты (КП 11.1). Цену знает сервер.
  Future<PetSnapshot> buyItem(String itemId);

  /// Пройденный уровень обучения (КП 9.5).
  Future<PetSnapshot> completeLevel(String categoryId, int level);

  /// Поставить предмет в комнату или убрать (КП 10.7).
  Future<void> setPlaced(String itemId, {required bool placed});

  /// Настройки игры: скорости, тайминги, награды, цены (КП 5.6, 15.4).
  Future<Map<String, dynamic>> config();
}

/// Ошибка обращения к хранилищу.
///
/// Отдельный тип, чтобы приложение отличало «сервер недоступен» от ошибки
/// в собственном коде: первое — штатная ситуация, за которой следует работа
/// офлайн, второе чинится, а не обходится.
class ProgressStoreException implements Exception {
  const ProgressStoreException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'ProgressStoreException: $message${cause == null ? '' : ' ($cause)'}';
}

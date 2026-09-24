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

  /// Вход в личный кабинет при запуске: состояние игрока целиком (КП 1.4).
  ///
  /// Кабинет у каждого свой — он создаётся на сервере вместе с учётной
  /// записью и привязан к её id: кошелёк, мишка, покупки, прогресс.
  Future<PetSnapshot> load();

  /// Действие ухода (КП 6.4). Насколько поднимется показатель и сколько
  /// дадут монет, решает сервер по настройкам (КП 15.4).
  Future<PetSnapshot> recordCare(BearAction action);

  /// Покупка предмета за монеты (КП 11.1). Цену знает сервер.
  Future<PetSnapshot> buyItem(String itemId);

  /// Готовое блюдо за монеты (КП 8.2). Цену и сытость берёт сервер из
  /// своих настроек, списывает с кошелька кабинета. Не хватило монет —
  /// [ProgressStoreException] с кодом [ProgressStoreException.notEnoughCoins].
  Future<PetSnapshot> feedDish(String dishId);

  /// Приготовленный рецепт (КП 8.4): награда в кошелёк и сытость.
  Future<PetSnapshot> completeRecipe(String recipeId);

  /// Пройденный уровень обучения (КП 9.5).
  Future<PetSnapshot> completeLevel(String categoryId, int level);

  /// Переименовать питомца (КП 2.3).
  ///
  /// Форму имени — длину и знаки — приложение проверяет само, но сервер
  /// проверяет её заново: клиент бывает старым, чужим или поддельным.
  /// Запрещённые слова ловит только сервер: список правит модератор из
  /// панели (КП 15.6), и приложение со старым списком пропустило бы то,
  /// что уже запретили.
  ///
  /// Бросает [ProgressStoreException], если имя отклонено.
  Future<PetSnapshot> renamePet(String name, {String locale = 'ru'});

  /// Поставить предмет в комнату или убрать (КП 10.7).
  Future<void> setPlaced(String itemId, {required bool placed});

  /// Настройки игры: скорости, тайминги, награды, цены (КП 5.6, 15.4).
  Future<Map<String, dynamic>> config();

  /// Удалить аккаунт целиком: кабинет, мишку, покупки, историю. Требование
  /// App Store 5.1.1(v) — раз аккаунт создаётся в приложении, удаляться он
  /// должен там же.
  Future<void> deleteAccount();
}

/// Ошибка обращения к хранилищу.
///
/// Отдельный тип, чтобы приложение отличало «сервер недоступен» от ошибки
/// в собственном коде: первое — штатная ситуация, за которой следует работа
/// офлайн, второе чинится, а не обходится.
class ProgressStoreException implements Exception {
  const ProgressStoreException(this.message, {this.cause, this.code});

  final String message;
  final Object? cause;

  /// Код ошибки сервера. `null` — до сервера не дошли (нет сети).
  final String? code;

  /// Коды функций базы (`supabase/migrations/0010_personal_account.sql`).
  static const String notSignedIn = 'TT401';
  static const String notEnoughCoins = 'TT402';
  static const String notYourPet = 'TT403';
  static const String notFound = 'TT404';
  static const String alreadyOwned = 'TT409';

  /// Сервер ответил и отказал. Такое действие повторять бессмысленно: оно
  /// не пройдёт и со второго раза, в отличие от обрыва связи.
  bool get isRejected => code != null;

  @override
  String toString() =>
      'ProgressStoreException: $message${cause == null ? '' : ' ($cause)'}';
}

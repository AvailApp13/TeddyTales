import 'bear_rig_spec.dart';

/// Двенадцать знаков зодиака (КП 7.2).
///
/// Знак присваивается при рождении по **игровому календарю** (КП 2.5), а не по
/// реальной дате — поэтому здесь нет вычисления знака из `DateTime`: значение
/// приходит с сервера вместе с карточкой рождения.
enum BearZodiac {
  aries('Овен'),
  taurus('Телец'),
  gemini('Близнецы'),
  cancer('Рак'),
  leo('Лев'),
  virgo('Дева'),
  libra('Весы'),
  scorpio('Скорпион'),
  sagittarius('Стрелец'),
  capricorn('Козерог'),
  aquarius('Водолей'),
  pisces('Рыбы');

  const BearZodiac(this.title);

  final String title;
}

/// Стартовые склонности характера по знаку зодиака (КП 7.2).
///
/// **Таблица — за Заказчиком.** КП говорит прямо: «Двенадцать знаков зодиака —
/// по таблице Заказчика, задают стартовые склонности». Придумывать её за
/// Заказчика мы не будем, поэтому по умолчанию используется [neutral] —
/// механика работает, влияния нет.
///
/// Когда таблица придёт, она подставляется одним объектом:
///
/// ```dart
/// const table = BearZodiacInfluence({
///   BearZodiac.leo: {BearTrait.active: 0.3, BearTrait.affectionate: 0.1},
///   // …
/// });
/// ```
///
/// Значения — добавка к нормализованному счёту черты (счёт в диапазоне 0–1),
/// поэтому осмысленный порядок величин — 0,1–0,3: склонность должна смещать
/// итог, но не перебивать реальные действия пользователя, из которых характер
/// и формируется (КП 7.3).
class BearZodiacInfluence {
  const BearZodiacInfluence(this.byZodiac);

  /// Пустая таблица: знак не влияет ни на что.
  static const BearZodiacInfluence neutral = BearZodiacInfluence({});

  final Map<BearZodiac, Map<BearTrait, double>> byZodiac;

  bool get isEmpty => byZodiac.isEmpty;

  /// Добавка к счёту [trait] для знака [zodiac]. Ноль, если таблицы нет.
  double bonus(BearZodiac? zodiac, BearTrait trait) {
    if (zodiac == null) return 0;
    return byZodiac[zodiac]?[trait] ?? 0;
  }
}

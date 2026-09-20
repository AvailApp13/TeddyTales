/// Каталог игры (КП 10).
///
/// Было 52 предмета: мебель 10, декор 16, игрушки 10, одежда 16. 20.09
/// заказчик прислал для магазина настоящие картинки, и каталог вырос под
/// них — к прежним позициям добавились кресла, полки, ковры, растения и
/// игрушки, на которые картинки есть. Одежда осталась со значками: её в
/// присланном наборе не было.

library;

import '../bear/bear_rig_spec.dart';
import '../bear/bear_state.dart';

/// Куда предмет попадает в магазине и в комнате.
enum ItemKind {
  furniture('Мебель'),
  wallpaper('Обои'),
  floor('Пол'),
  decor('Декор'),
  toy('Игрушки'),
  outfit('Наряды'),
  top('Верх'),
  bottom('Низ'),
  headwear('Головные уборы'),
  shoes('Обувь'),
  accessory('Аксессуары');

  const ItemKind(this.title);

  final String title;

  /// Надевается ли предмет на мишку (в отличие от обстановки комнаты).
  bool get isWearable => switch (this) {
    ItemKind.outfit ||
    ItemKind.top ||
    ItemKind.bottom ||
    ItemKind.headwear ||
    ItemKind.shoes ||
    ItemKind.accessory => true,
    _ => false,
  };
}

/// Предмет игры.
class ShopItem {
  const ShopItem({
    required this.id,
    required this.emoji,
    required this.title,
    required this.price,
    required this.kind,
    this.photo = false,
    this.slotValue,
    this.suitsFrom = BearStage.newborn,
  });

  final String id;

  /// Запасной значок: показывается, пока у товара нет своей картинки.
  ///
  /// До 20.09 эмодзи были единственным изображением в магазине, и витрина
  /// рядом с фотографическими комнатами выглядела чужой — заказчик: «это же
  /// абсурд». Теперь заказчик присылает настоящие картинки; у позиций,
  /// которых в присланном наборе не оказалось (вся одежда и часть декора),
  /// значок пока остаётся.
  final String emoji;

  /// Есть ли у товара своя картинка в `assets/shop/items`.
  final bool photo;

  final String title;

  /// Цена в монетах.
  ///
  /// ЗАГЛУШКА: по КП 10.9 цены рассчитываются и утверждаются отдельно до
  /// запуска магазина, а по 15.4 меняются из панели управления.
  final int price;

  final ItemKind kind;

  /// Значение соответствующего входа рига для надеваемых вещей.
  ///
  /// Сопоставление «товар → id в риге» живёт здесь, потому что это свойство
  /// каталога, а не персонажа: `BearOutfit` знает только числа.
  final int? slotValue;

  /// С какой стадии предмет уместен малышу.
  ///
  /// **Это не замок.** Купить можно всё и в любой момент: закрытая витрина
  /// злит, а «пока рано» — продаёт. Значение управляет только порядком:
  /// подходящее возрасту стоит первым, остальное ниже, под отдельной
  /// подписью. Кроватка и ночник нужны в первый день, шкаф и пазл — нет.
  final BearStage suitsFrom;

  bool suitsAt(BearStage stage) => stage.riveValue >= suitsFrom.riveValue;

  /// Путь к картинке товара или `null`, если её ещё не прислали.
  ///
  /// Имя файла выводится из [id], а не хранится отдельно: два источника
  /// правды разъехались бы при первом же переименовании.
  String? get image => photo ? 'assets/shop/items/$id.webp' : null;

  /// Применяет предмет к образу мишки.
  BearOutfit applyTo(BearOutfit outfit) {
    final v = slotValue;
    if (v == null) return outfit;

    return switch (kind) {
      ItemKind.outfit => outfit.copyWith(outfitId: v),
      ItemKind.top => outfit.copyWith(topId: v),
      ItemKind.bottom => outfit.copyWith(bottomId: v),
      ItemKind.headwear => outfit.copyWith(headwearId: v),
      ItemKind.shoes => outfit.copyWith(shoesId: v),
      ItemKind.accessory => outfit.copyWith(accessoryId: v),
      _ => outfit,
    };
  }

  /// Надет ли предмет сейчас.
  bool isWornIn(BearOutfit outfit) {
    final v = slotValue;
    if (v == null) return false;

    return switch (kind) {
      ItemKind.outfit => outfit.outfitId == v,
      ItemKind.top => outfit.topId == v,
      ItemKind.bottom => outfit.bottomId == v,
      ItemKind.headwear => outfit.headwearId == v,
      ItemKind.shoes => outfit.shoesId == v,
      ItemKind.accessory => outfit.accessoryId == v,
      _ => false,
    };
  }
}

/// Каталог игровых предметов.
abstract final class ItemCatalog {
  /// Мебель — 10 (КП 10.2).
  static const List<ShopItem> furniture = <ShopItem>[
    ShopItem(
      id: 'bed',
      emoji: '🛏',
      title: 'Кроватка',
      price: 120,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'wardrobe',
      emoji: '🚪',
      title: 'Шкаф',
      price: 140,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'table',
      emoji: '🪑',
      title: 'Стол',
      price: 90,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'chair',
      emoji: '💺',
      title: 'Стул',
      price: 70,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'shelf',
      emoji: '📚',
      title: 'Книжная полка',
      price: 110,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'dresser',
      emoji: '🗄',
      title: 'Комод',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair',
      emoji: '🛋',
      title: 'Кресло',
      price: 130,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'rug',
      emoji: '🟫',
      title: 'Ковёр',
      price: 80,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'lamp',
      emoji: '💡',
      title: 'Светильник',
      price: 60,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'basket',
      emoji: '🧺',
      title: 'Корзина',
      price: 50,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'shelf_house',
      emoji: '🏠',
      title: 'Полка-домик',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'shelf_moon',
      emoji: '🌙',
      title: 'Полка-месяц',
      price: 130,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'armchair_sage',
      emoji: '🪑',
      title: 'Кресло мятное',
      price: 170,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair_bean',
      emoji: '🛋',
      title: 'Кресло-пуф',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'armchair_flower',
      emoji: '🌸',
      title: 'Кресло-цветок',
      price: 180,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair_wing',
      emoji: '👑',
      title: 'Кресло с ушками',
      price: 190,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'swing',
      emoji: '🪺',
      title: 'Подвесное кресло',
      price: 200,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'basket_star',
      emoji: '⭐️',
      title: 'Корзина со звездой',
      price: 70,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'rug_cloud',
      emoji: '☁️',
      title: 'Ковёр-облако',
      price: 110,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'rug_heart',
      emoji: '💗',
      title: 'Ковёр с сердцем',
      price: 110,
      photo: true,
      kind: ItemKind.furniture,
    ),
  ];

  /// Декор — 16 (КП 10.3): обои 3, полы 3, картины 3, подушки 2, растения 2,
  /// гирлянда, часы, постер.
  static const List<ShopItem> decor = <ShopItem>[
    ShopItem(
      id: 'wall_rose',
      emoji: '🌸',
      title: 'Обои розовые',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'wall_sage',
      emoji: '🌿',
      title: 'Обои зелёные',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'wall_sky',
      emoji: '☁️',
      title: 'Обои небо',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'floor_wood',
      emoji: '🟤',
      title: 'Пол дерево',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'floor_light',
      emoji: '⬜️',
      title: 'Пол светлый',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'floor_carpet',
      emoji: '🟩',
      title: 'Пол ковролин',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'pic_bear',
      emoji: '🖼',
      title: 'Картина мишка',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'pic_forest',
      emoji: '🏞',
      title: 'Картина лес',
      price: 55,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'pic_moon',
      emoji: '🌙',
      title: 'Картина луна',
      price: 55,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'pillow_heart',
      emoji: '💗',
      title: 'Подушка сердце',
      price: 30,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'pillow_star',
      emoji: '⭐️',
      title: 'Подушка звезда',
      price: 30,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'plant',
      emoji: '🪴',
      title: 'Растение',
      price: 45,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'cactus',
      emoji: '🌵',
      title: 'Кактус',
      price: 45,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'garland',
      emoji: '✨',
      title: 'Гирлянда',
      price: 65,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'clock',
      emoji: '🕰',
      title: 'Часы',
      price: 70,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'poster',
      emoji: '📜',
      title: 'Постер',
      price: 50,
      kind: ItemKind.decor,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'pic_heart',
      emoji: '🖼',
      title: 'Картина с сердцем',
      price: 60,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'plant_ivy',
      emoji: '🌿',
      title: 'Плющ на подставке',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'plant_bear',
      emoji: '🐻',
      title: 'Цветок в кашпо-мишке',
      price: 65,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_daisy',
      emoji: '🌼',
      title: 'Ромашки в банке',
      price: 50,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_orchid',
      emoji: '🌺',
      title: 'Орхидея',
      price: 70,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_euc',
      emoji: '🍃',
      title: 'Эвкалипт в вазе',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
    ),
  ];

  /// Игрушки — 10 (КП 10.4). Состав утверждается Заказчиком по таблице до
  /// отрисовки, здесь рабочий набор.
  static const List<ShopItem> toys = <ShopItem>[
    ShopItem(
      id: 'ball',
      emoji: '⚽️',
      title: 'Мячик',
      price: 40,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'teddy',
      emoji: '🧸',
      title: 'Мишка',
      price: 90,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'cubes',
      emoji: '🧊',
      title: 'Кубики',
      price: 60,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'car',
      emoji: '🚗',
      title: 'Машинка',
      price: 70,
      kind: ItemKind.toy,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'duck',
      emoji: '🦆',
      title: 'Уточка',
      price: 35,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'drum',
      emoji: '🥁',
      title: 'Барабан',
      price: 80,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'puzzle',
      emoji: '🧩',
      title: 'Пазл',
      price: 65,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'train',
      emoji: '🚂',
      title: 'Паровозик',
      price: 95,
      kind: ItemKind.toy,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'kite',
      emoji: '🪁',
      title: 'Воздушный змей',
      price: 55,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'rocket',
      emoji: '🚀',
      title: 'Ракета',
      price: 85,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'teddy_cream',
      emoji: '🧸',
      title: 'Мишка кремовый',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'bunny',
      emoji: '🐰',
      title: 'Зайчик',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'bunny_pink',
      emoji: '🎀',
      title: 'Зайчик розовый',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'pyramid',
      emoji: '🗼',
      title: 'Пирамидка',
      price: 80,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'dollhouse',
      emoji: '🏡',
      title: 'Кукольный домик',
      price: 220,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'house_felt',
      emoji: '🏠',
      title: 'Домик из фетра',
      price: 160,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
  ];

  /// Одежда и аксессуары — 16 (КП 10.5).
  ///
  /// Разбивка отличается от КП: там 8 комплектов, 3 головных убора, 2 обуви,
  /// 3 аксессуара. Здесь часть комплектов заменена раздельными верхом и низом —
  /// по решению от 10.08.2026, см. `docs/rig-change-request.md`. Итоговый
  /// пересчёт каталога за Заказчиком.
  static const List<ShopItem> clothes = <ShopItem>[
    ShopItem(
      id: 'out_yellow',
      emoji: '🧥',
      title: 'Комплект жёлтый',
      price: 160,
      kind: ItemKind.outfit,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_sailor',
      emoji: '👔',
      title: 'Комплект матрос',
      price: 180,
      kind: ItemKind.outfit,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_bear',
      emoji: '🐻',
      title: 'Костюм мишки',
      price: 200,
      kind: ItemKind.outfit,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_berry',
      emoji: '🍓',
      title: 'Костюм клубника',
      price: 220,
      kind: ItemKind.outfit,
      slotValue: 4,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_bee',
      emoji: '🐝',
      title: 'Костюм пчёлка',
      price: 240,
      kind: ItemKind.outfit,
      slotValue: 5,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_glasses',
      emoji: '👓',
      title: 'Комплект очкарик',
      price: 100,
      kind: ItemKind.outfit,
      slotValue: 6,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_winter',
      emoji: '🧣',
      title: 'Комплект зимний',
      price: 190,
      kind: ItemKind.outfit,
      slotValue: 7,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_sport',
      emoji: '🎽',
      title: 'Комплект спорт',
      price: 150,
      kind: ItemKind.outfit,
      slotValue: 8,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_rose',
      emoji: '👕',
      title: 'Свитер розовый',
      price: 120,
      kind: ItemKind.top,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_sage',
      emoji: '🥼',
      title: 'Кофта зелёная',
      price: 130,
      kind: ItemKind.top,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_blue',
      emoji: '🧥',
      title: 'Толстовка голубая',
      price: 140,
      kind: ItemKind.top,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_yellow',
      emoji: '🩳',
      title: 'Шорты жёлтые',
      price: 110,
      kind: ItemKind.bottom,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_blue',
      emoji: '👖',
      title: 'Штаны синие',
      price: 120,
      kind: ItemKind.bottom,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_skirt',
      emoji: '🩱',
      title: 'Юбка розовая',
      price: 125,
      kind: ItemKind.bottom,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'hat_cap',
      emoji: '🎩',
      title: 'Шапка',
      price: 90,
      kind: ItemKind.headwear,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'acc_bow',
      emoji: '🎀',
      title: 'Бантик',
      price: 60,
      kind: ItemKind.accessory,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
  ];

  /// Все 52 предмета.
  static List<ShopItem> get all => [
    ...furniture,
    ...decor,
    ...toys,
    ...clothes,
  ];

  static ShopItem byId(String id) => all.firstWhere((i) => i.id == id);

  static List<ShopItem> ofKind(ItemKind kind) =>
      all.where((i) => i.kind == kind).toList();
}

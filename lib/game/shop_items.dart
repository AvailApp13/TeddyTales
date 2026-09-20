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
    required this.title,
    required this.price,
    required this.kind,
    this.photo = false,
    this.slotValue,
    this.suitsFrom = BearStage.newborn,
  });

  final String id;

  /// Есть ли у товара своя картинка в `assets/shop/items`.
  ///
  /// Позиции без картинки в витрину не попадают: до 20.09 они рисовались
  /// эмодзи, и заказчик попросил убрать их совсем — «все эмодзи, которые
  /// остались, удали их». Сами позиции живы: купленные вещи стоят в
  /// комнате, а каталог ждёт картинок.
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
      title: 'Кроватка',
      price: 120,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'wardrobe',
      title: 'Шкаф',
      price: 140,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'table',
      title: 'Стол',
      price: 90,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'chair',
      title: 'Стул',
      price: 70,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'shelf',
      title: 'Книжная полка',
      price: 110,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'dresser',
      title: 'Комод',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair',
      title: 'Кресло',
      price: 130,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'rug',
      title: 'Ковёр',
      price: 80,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'lamp',
      title: 'Светильник',
      price: 60,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'basket',
      title: 'Корзина',
      price: 50,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'shelf_house',
      title: 'Полка-домик',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'shelf_moon',
      title: 'Полка-месяц',
      price: 130,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'armchair_sage',
      title: 'Кресло мятное',
      price: 170,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair_bean',
      title: 'Кресло-пуф',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'armchair_flower',
      title: 'Кресло-цветок',
      price: 180,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair_wing',
      title: 'Кресло с ушками',
      price: 190,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'swing',
      title: 'Подвесное кресло',
      price: 200,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'basket_star',
      title: 'Корзина со звездой',
      price: 70,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'rug_cloud',
      title: 'Ковёр-облако',
      price: 110,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'rug_heart',
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
      title: 'Обои розовые',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'wall_sage',
      title: 'Обои зелёные',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'wall_sky',
      title: 'Обои небо',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'floor_wood',
      title: 'Пол дерево',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'floor_light',
      title: 'Пол светлый',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'floor_carpet',
      title: 'Пол ковролин',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'pic_bear',
      title: 'Картина мишка',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'pic_forest',
      title: 'Картина лес',
      price: 55,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'pic_moon',
      title: 'Картина луна',
      price: 55,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'pillow_heart',
      title: 'Подушка сердце',
      price: 30,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'pillow_star',
      title: 'Подушка звезда',
      price: 30,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'plant',
      title: 'Растение',
      price: 45,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'cactus',
      title: 'Кактус',
      price: 45,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'garland',
      title: 'Гирлянда',
      price: 65,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'clock',
      title: 'Часы',
      price: 70,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'poster',
      title: 'Постер',
      price: 50,
      kind: ItemKind.decor,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'pic_heart',
      title: 'Картина с сердцем',
      price: 60,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'plant_ivy',
      title: 'Плющ на подставке',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'plant_bear',
      title: 'Цветок в кашпо-мишке',
      price: 65,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_daisy',
      title: 'Ромашки в банке',
      price: 50,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_orchid',
      title: 'Орхидея',
      price: 70,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_euc',
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
      title: 'Мячик',
      price: 40,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'teddy',
      title: 'Мишка',
      price: 90,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'cubes',
      title: 'Кубики',
      price: 60,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'car',
      title: 'Машинка',
      price: 70,
      kind: ItemKind.toy,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'duck',
      title: 'Уточка',
      price: 35,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'drum',
      title: 'Барабан',
      price: 80,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'puzzle',
      title: 'Пазл',
      price: 65,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'train',
      title: 'Паровозик',
      price: 95,
      kind: ItemKind.toy,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'kite',
      title: 'Воздушный змей',
      price: 55,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'rocket',
      title: 'Ракета',
      price: 85,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'teddy_cream',
      title: 'Мишка кремовый',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'bunny',
      title: 'Зайчик',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'bunny_pink',
      title: 'Зайчик розовый',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'pyramid',
      title: 'Пирамидка',
      price: 80,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'dollhouse',
      title: 'Кукольный домик',
      price: 220,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'house_felt',
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
      title: 'Комплект жёлтый',
      price: 160,
      kind: ItemKind.outfit,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_sailor',
      title: 'Комплект матрос',
      price: 180,
      kind: ItemKind.outfit,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_bear',
      title: 'Костюм мишки',
      price: 200,
      kind: ItemKind.outfit,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_berry',
      title: 'Костюм клубника',
      price: 220,
      kind: ItemKind.outfit,
      slotValue: 4,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_bee',
      title: 'Костюм пчёлка',
      price: 240,
      kind: ItemKind.outfit,
      slotValue: 5,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_glasses',
      title: 'Комплект очкарик',
      price: 100,
      kind: ItemKind.outfit,
      slotValue: 6,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_winter',
      title: 'Комплект зимний',
      price: 190,
      kind: ItemKind.outfit,
      slotValue: 7,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_sport',
      title: 'Комплект спорт',
      price: 150,
      kind: ItemKind.outfit,
      slotValue: 8,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_rose',
      title: 'Свитер розовый',
      price: 120,
      kind: ItemKind.top,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_sage',
      title: 'Кофта зелёная',
      price: 130,
      kind: ItemKind.top,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_blue',
      title: 'Толстовка голубая',
      price: 140,
      kind: ItemKind.top,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_yellow',
      title: 'Шорты жёлтые',
      price: 110,
      kind: ItemKind.bottom,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_blue',
      title: 'Штаны синие',
      price: 120,
      kind: ItemKind.bottom,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_skirt',
      title: 'Юбка розовая',
      price: 125,
      kind: ItemKind.bottom,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'hat_cap',
      title: 'Шапка',
      price: 90,
      kind: ItemKind.headwear,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'acc_bow',
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

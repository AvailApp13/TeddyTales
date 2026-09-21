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
import 'item_groups.dart';

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
    required this.group,
    required this.title,
    required this.price,
    required this.kind,
    this.photo = false,
    this.slotValue,
    this.suitsFrom = BearStage.newborn,
  });

  final String id;

  /// Род вещи: ковёр, картина, кресло. Отсюда берутся и подкатегория в
  /// магазине, и размер вещи в комнате — см. [ItemGroup].
  ///
  /// Заказчик 21.09: «я тебе его отправляю, ты понимаешь, что это ковёр, и
  /// делаешь его не огромным размером, а тем, который сейчас задан». Новая
  /// картинка — это одна строка здесь с нужной подкатегорией; подгонять
  /// размер руками больше не нужно.
  final ItemGroup group;

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
      group: ItemGroup.beds,
      title: 'Кроватка',
      price: 120,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'wardrobe',
      group: ItemGroup.wardrobes,
      title: 'Шкаф',
      price: 140,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'table',
      group: ItemGroup.tables,
      title: 'Стол',
      price: 90,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'chair',
      group: ItemGroup.seats,
      title: 'Стул',
      price: 70,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'shelf',
      group: ItemGroup.shelves,
      title: 'Книжная полка',
      price: 110,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'dresser',
      group: ItemGroup.dressers,
      title: 'Комод',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair',
      group: ItemGroup.chairs,
      title: 'Кресло',
      price: 130,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'lamp',
      group: ItemGroup.lamps,
      title: 'Светильник',
      price: 60,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'basket',
      group: ItemGroup.baskets,
      title: 'Корзина',
      price: 50,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'shelf_house',
      group: ItemGroup.shelves,
      title: 'Полка-домик',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'shelf_moon',
      group: ItemGroup.shelves,
      title: 'Полка-месяц',
      price: 130,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'armchair_sage',
      group: ItemGroup.chairs,
      title: 'Кресло мятное',
      price: 170,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair_bean',
      group: ItemGroup.chairs,
      title: 'Кресло-пуф',
      price: 150,
      photo: true,
      kind: ItemKind.furniture,
    ),
    ShopItem(
      id: 'armchair_flower',
      group: ItemGroup.chairs,
      title: 'Кресло-цветок',
      price: 180,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'armchair_wing',
      group: ItemGroup.chairs,
      title: 'Кресло с ушками',
      price: 190,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'swing',
      group: ItemGroup.chairs,
      title: 'Подвесное кресло',
      price: 200,
      photo: true,
      kind: ItemKind.furniture,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'basket_star',
      group: ItemGroup.baskets,
      title: 'Корзина со звездой',
      price: 70,
      photo: true,
      kind: ItemKind.furniture,
    ),
  ];

  /// Декор — 16 (КП 10.3): обои 3, полы 3, картины 3, подушки 2, растения 2,
  /// гирлянда, часы, постер. С 21.09 здесь же ковры: «он вообще, в принципе,
  /// относится к декору» — заказчик.
  static const List<ShopItem> decor = <ShopItem>[
    // Ковры.
    ShopItem(
      id: 'rug',
      group: ItemGroup.rugs,
      title: 'Ковёр',
      price: 80,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'rug_cloud',
      group: ItemGroup.rugs,
      title: 'Ковёр-облако',
      price: 110,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'rug_heart',
      group: ItemGroup.rugs,
      title: 'Ковёр с сердцем',
      price: 110,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'wall_rose',
      group: ItemGroup.walls,
      title: 'Обои розовые',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'wall_sage',
      group: ItemGroup.walls,
      title: 'Обои зелёные',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'wall_sky',
      group: ItemGroup.walls,
      title: 'Обои небо',
      price: 40,
      kind: ItemKind.wallpaper,
    ),
    ShopItem(
      id: 'floor_wood',
      group: ItemGroup.floors,
      title: 'Пол дерево',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'floor_light',
      group: ItemGroup.floors,
      title: 'Пол светлый',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'floor_carpet',
      group: ItemGroup.floors,
      title: 'Пол ковролин',
      price: 35,
      kind: ItemKind.floor,
    ),
    ShopItem(
      id: 'pic_bear',
      group: ItemGroup.pictures,
      title: 'Картина мишка',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'pic_forest',
      group: ItemGroup.pictures,
      title: 'Картина лес',
      price: 55,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'pic_moon',
      group: ItemGroup.pictures,
      title: 'Картина луна',
      price: 55,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'pillow_heart',
      group: ItemGroup.pillows,
      title: 'Подушка сердце',
      price: 30,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'pillow_star',
      group: ItemGroup.pillows,
      title: 'Подушка звезда',
      price: 30,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'plant',
      group: ItemGroup.plants,
      title: 'Растение',
      price: 45,
      photo: true,
      kind: ItemKind.decor,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'cactus',
      group: ItemGroup.plants,
      title: 'Кактус',
      price: 45,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'garland',
      group: ItemGroup.garlands,
      title: 'Гирлянда',
      price: 65,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'clock',
      group: ItemGroup.clocks,
      title: 'Часы',
      price: 70,
      kind: ItemKind.decor,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'poster',
      group: ItemGroup.pictures,
      title: 'Постер',
      price: 50,
      kind: ItemKind.decor,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'pic_heart',
      group: ItemGroup.pictures,
      title: 'Картина с сердцем',
      price: 60,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'plant_ivy',
      group: ItemGroup.plants,
      title: 'Плющ на подставке',
      price: 55,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'plant_bear',
      group: ItemGroup.plants,
      title: 'Цветок в кашпо-мишке',
      price: 65,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_daisy',
      group: ItemGroup.flowers,
      title: 'Ромашки в банке',
      price: 50,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_orchid',
      group: ItemGroup.flowers,
      title: 'Орхидея',
      price: 70,
      photo: true,
      kind: ItemKind.decor,
    ),
    ShopItem(
      id: 'flowers_euc',
      group: ItemGroup.flowers,
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
      group: ItemGroup.toys,
      title: 'Мячик',
      price: 40,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'teddy',
      group: ItemGroup.plush,
      title: 'Мишка',
      price: 90,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'cubes',
      group: ItemGroup.toys,
      title: 'Кубики',
      price: 60,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'car',
      group: ItemGroup.toys,
      title: 'Машинка',
      price: 70,
      kind: ItemKind.toy,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'duck',
      group: ItemGroup.toys,
      title: 'Уточка',
      price: 35,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'drum',
      group: ItemGroup.toys,
      title: 'Барабан',
      price: 80,
      kind: ItemKind.toy,
      suitsFrom: BearStage.crawling,
    ),
    ShopItem(
      id: 'puzzle',
      group: ItemGroup.toys,
      title: 'Пазл',
      price: 65,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'train',
      group: ItemGroup.toys,
      title: 'Паровозик',
      price: 95,
      kind: ItemKind.toy,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'kite',
      group: ItemGroup.toys,
      title: 'Воздушный змей',
      price: 55,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'rocket',
      group: ItemGroup.toys,
      title: 'Ракета',
      price: 85,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'teddy_cream',
      group: ItemGroup.plush,
      title: 'Мишка кремовый',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'bunny',
      group: ItemGroup.plush,
      title: 'Зайчик',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'bunny_pink',
      group: ItemGroup.plush,
      title: 'Зайчик розовый',
      price: 110,
      photo: true,
      kind: ItemKind.toy,
    ),
    ShopItem(
      id: 'pyramid',
      group: ItemGroup.toys,
      title: 'Пирамидка',
      price: 80,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'dollhouse',
      group: ItemGroup.houses,
      title: 'Кукольный домик',
      price: 220,
      photo: true,
      kind: ItemKind.toy,
      suitsFrom: BearStage.growing,
    ),
    ShopItem(
      id: 'house_felt',
      group: ItemGroup.houses,
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
      group: ItemGroup.outfits,
      title: 'Комплект жёлтый',
      price: 160,
      kind: ItemKind.outfit,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_sailor',
      group: ItemGroup.outfits,
      title: 'Комплект матрос',
      price: 180,
      kind: ItemKind.outfit,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_bear',
      group: ItemGroup.outfits,
      title: 'Костюм мишки',
      price: 200,
      kind: ItemKind.outfit,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_berry',
      group: ItemGroup.outfits,
      title: 'Костюм клубника',
      price: 220,
      kind: ItemKind.outfit,
      slotValue: 4,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_bee',
      group: ItemGroup.outfits,
      title: 'Костюм пчёлка',
      price: 240,
      kind: ItemKind.outfit,
      slotValue: 5,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_glasses',
      group: ItemGroup.outfits,
      title: 'Комплект очкарик',
      price: 100,
      kind: ItemKind.outfit,
      slotValue: 6,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_winter',
      group: ItemGroup.outfits,
      title: 'Комплект зимний',
      price: 190,
      kind: ItemKind.outfit,
      slotValue: 7,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'out_sport',
      group: ItemGroup.outfits,
      title: 'Комплект спорт',
      price: 150,
      kind: ItemKind.outfit,
      slotValue: 8,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_rose',
      group: ItemGroup.tops,
      title: 'Свитер розовый',
      price: 120,
      kind: ItemKind.top,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_sage',
      group: ItemGroup.tops,
      title: 'Кофта зелёная',
      price: 130,
      kind: ItemKind.top,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'top_blue',
      group: ItemGroup.tops,
      title: 'Толстовка голубая',
      price: 140,
      kind: ItemKind.top,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_yellow',
      group: ItemGroup.bottoms,
      title: 'Шорты жёлтые',
      price: 110,
      kind: ItemKind.bottom,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_blue',
      group: ItemGroup.bottoms,
      title: 'Штаны синие',
      price: 120,
      kind: ItemKind.bottom,
      slotValue: 2,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'bot_skirt',
      group: ItemGroup.bottoms,
      title: 'Юбка розовая',
      price: 125,
      kind: ItemKind.bottom,
      slotValue: 3,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'hat_cap',
      group: ItemGroup.hats,
      title: 'Шапка',
      price: 90,
      kind: ItemKind.headwear,
      slotValue: 1,
      suitsFrom: BearStage.firstSteps,
    ),
    ShopItem(
      id: 'acc_bow',
      group: ItemGroup.extras,
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

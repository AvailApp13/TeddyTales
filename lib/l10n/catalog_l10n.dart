/// Локализация каталога предметов (см. `lib/game/shop_items.dart`).
///
/// Русские `title` в каталоге — эталонные данные и остаются на месте;
/// экраны берут отображаемые названия только через эти функции.
library;

import '../game/shop_items.dart';
import 'gen/app_localizations.dart';

/// Локализованное название предмета каталога по его [id].
///
/// Для неизвестного id возвращает исходное русское название из каталога
/// (а если предмета нет и там — сам id), чтобы интерфейс не падал на
/// рассинхроне каталога и переводов.
String shopItemName(AppLocalizations l10n, String id) => switch (id) {
  // Мебель.
  'bed' => l10n.itemBed,
  'wardrobe' => l10n.itemWardrobe,
  'table' => l10n.itemTable,
  'chair' => l10n.itemChair,
  'shelf' => l10n.itemShelf,
  'dresser' => l10n.itemDresser,
  'armchair' => l10n.itemArmchair,
  'rug' => l10n.itemRug,
  'lamp' => l10n.itemLamp,
  'basket' => l10n.itemBasket,
  // Декор: обои, полы, картины, подушки, растения и мелочи.
  'wall_rose' => l10n.itemWallRose,
  'wall_sage' => l10n.itemWallSage,
  'wall_sky' => l10n.itemWallSky,
  'floor_wood' => l10n.itemFloorWood,
  'floor_light' => l10n.itemFloorLight,
  'floor_carpet' => l10n.itemFloorCarpet,
  'pic_bear' => l10n.itemPicBear,
  'pic_forest' => l10n.itemPicForest,
  'pic_moon' => l10n.itemPicMoon,
  'pillow_heart' => l10n.itemPillowHeart,
  'pillow_star' => l10n.itemPillowStar,
  'plant' => l10n.itemPlant,
  'cactus' => l10n.itemCactus,
  'garland' => l10n.itemGarland,
  'clock' => l10n.itemClock,
  'poster' => l10n.itemPoster,
  // Игрушки.
  'ball' => l10n.itemBall,
  'teddy' => l10n.itemTeddy,
  'cubes' => l10n.itemCubes,
  'car' => l10n.itemCar,
  'duck' => l10n.itemDuck,
  'drum' => l10n.itemDrum,
  'puzzle' => l10n.itemPuzzle,
  'train' => l10n.itemTrain,
  'kite' => l10n.itemKite,
  'rocket' => l10n.itemRocket,
  // Одежда и аксессуары.
  'out_yellow' => l10n.itemOutYellow,
  'out_sailor' => l10n.itemOutSailor,
  'out_bear' => l10n.itemOutBear,
  'out_berry' => l10n.itemOutBerry,
  'out_bee' => l10n.itemOutBee,
  'out_glasses' => l10n.itemOutGlasses,
  'out_winter' => l10n.itemOutWinter,
  'out_sport' => l10n.itemOutSport,
  'top_rose' => l10n.itemTopRose,
  'top_sage' => l10n.itemTopSage,
  'top_blue' => l10n.itemTopBlue,
  'bot_yellow' => l10n.itemBotYellow,
  'bot_blue' => l10n.itemBotBlue,
  'bot_skirt' => l10n.itemBotSkirt,
  'hat_cap' => l10n.itemHatCap,
  'acc_bow' => l10n.itemAccBow,
  _ => _catalogFallback(id),
};

/// Локализованное название раздела каталога [ItemKind].
String shopCategoryTitle(AppLocalizations l10n, ItemKind kind) =>
    switch (kind) {
      ItemKind.furniture => l10n.categoryFurniture,
      ItemKind.wallpaper => l10n.categoryWallpaper,
      ItemKind.floor => l10n.categoryFloor,
      ItemKind.decor => l10n.categoryDecor,
      ItemKind.toy => l10n.categoryToy,
      ItemKind.outfit => l10n.categoryOutfit,
      ItemKind.top => l10n.categoryTop,
      ItemKind.bottom => l10n.categoryBottom,
      ItemKind.headwear => l10n.categoryHeadwear,
      ItemKind.shoes => l10n.categoryShoes,
      ItemKind.accessory => l10n.categoryAccessory,
    };

/// Русское название из каталога — фолбэк для id, которого нет в переводах.
String _catalogFallback(String id) {
  for (final item in ItemCatalog.all) {
    if (item.id == id) return item.title;
  }
  return id;
}

/// Локализация каталога предметов (см. `lib/game/shop_items.dart`).
///
/// Русские `title` в каталоге — эталонные данные и остаются на месте;
/// экраны берут отображаемые названия только через эти функции.
library;

import '../game/item_groups.dart';
import '../game/shop_items.dart';
import 'gen/app_localizations.dart';

/// Локализованное название предмета каталога по его [id].
///
/// Для неизвестного id возвращает исходное русское название из каталога
/// (а если предмета нет и там — сам id), чтобы интерфейс не падал на
/// рассинхроне каталога и переводов.
String shopItemName(AppLocalizations l10n, String id) => switch (id) {
  // Мебель.
  // Позиции, добавленные 20.09 под присланные картинки.
  'shelf_house' => l10n.itemShelfHouse,
  'shelf_moon' => l10n.itemShelfMoon,
  'armchair_sage' => l10n.itemArmchairSage,
  'armchair_bean' => l10n.itemArmchairBean,
  'armchair_flower' => l10n.itemArmchairFlower,
  'armchair_wing' => l10n.itemArmchairWing,
  'swing' => l10n.itemSwing,
  'basket_star' => l10n.itemBasketStar,
  'rug_cloud' => l10n.itemRugCloud,
  'rug_heart' => l10n.itemRugHeart,
  'pic_heart' => l10n.itemPicHeart,
  'plant_ivy' => l10n.itemPlantIvy,
  'plant_bear' => l10n.itemPlantBear,
  'flowers_daisy' => l10n.itemFlowersDaisy,
  'flowers_orchid' => l10n.itemFlowersOrchid,
  'flowers_euc' => l10n.itemFlowersEuc,
  'teddy_cream' => l10n.itemTeddyCream,
  'bunny' => l10n.itemBunny,
  'bunny_pink' => l10n.itemBunnyPink,
  'pyramid' => l10n.itemPyramid,
  'dollhouse' => l10n.itemDollhouse,
  'house_felt' => l10n.itemHouseFelt,
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

/// Локализованное название подкатегории [ItemGroup] — подписи на чипах
/// внутри вкладки магазина.
String shopGroupName(AppLocalizations l10n, ItemGroup group) =>
    switch (group) {
      ItemGroup.beds => l10n.shopGroupBeds,
      ItemGroup.chairs => l10n.shopGroupChairs,
      ItemGroup.seats => l10n.shopGroupSeats,
      ItemGroup.dressers => l10n.shopGroupDressers,
      ItemGroup.wardrobes => l10n.shopGroupWardrobes,
      ItemGroup.tables => l10n.shopGroupTables,
      ItemGroup.baskets => l10n.shopGroupBaskets,
      ItemGroup.shelves => l10n.shopGroupShelves,
      ItemGroup.lamps => l10n.shopGroupLamps,
      ItemGroup.rugs => l10n.shopGroupRugs,
      ItemGroup.pictures => l10n.shopGroupPictures,
      ItemGroup.clocks => l10n.shopGroupClocks,
      ItemGroup.garlands => l10n.shopGroupGarlands,
      ItemGroup.plants => l10n.shopGroupPlants,
      ItemGroup.flowers => l10n.shopGroupFlowers,
      ItemGroup.pillows => l10n.shopGroupPillows,
      ItemGroup.walls => l10n.shopGroupWalls,
      ItemGroup.floors => l10n.shopGroupFloors,
      ItemGroup.plush => l10n.shopGroupPlush,
      ItemGroup.houses => l10n.shopGroupHouses,
      ItemGroup.toys => l10n.shopGroupToys,
      ItemGroup.outfits => l10n.shopGroupOutfits,
      ItemGroup.tops => l10n.shopGroupTops,
      ItemGroup.bottoms => l10n.shopGroupBottoms,
      ItemGroup.hats => l10n.shopGroupHats,
      ItemGroup.shoes => l10n.shopGroupShoes,
      ItemGroup.extras => l10n.shopGroupExtras,
    };

/// Русское название из каталога — фолбэк для id, которого нет в переводах.
String _catalogFallback(String id) {
  for (final item in ItemCatalog.all) {
    if (item.id == id) return item.title;
  }
  return id;
}

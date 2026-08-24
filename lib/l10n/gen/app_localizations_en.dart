// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String ageDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String ageMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '$count month',
    );
    return '$_temp0';
  }

  @override
  String ageMonthsDays(int months, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months',
      one: '$months month',
    );
    String _temp1 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '$days day',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years',
      one: '$count year',
    );
    return '$_temp0';
  }

  @override
  String get appTitle => 'TeddyTales';

  @override
  String bearRigMissingHint(String path) {
    return 'Add $path to the app';
  }

  @override
  String get bearRigMissingTitle => 'The rig isn’t hooked up yet';

  @override
  String get birthCueAwakening =>
      'The little one opens their eyes and looks around.';

  @override
  String get birthCueCradle =>
      'A warm little bed. Someone is breathing softly under the blanket…';

  @override
  String get birthCueFinale => 'Calm at last. Hello, little one.';

  @override
  String get birthCueFirstBreath => 'The first breath…';

  @override
  String get birthCueFirstCry => 'The first cry — calling out for you.';

  @override
  String get birthCueStars => 'Little stars drift in the soft light.';

  @override
  String get birthSceneNotReady => 'The birth scene isn\'t assembled yet';

  @override
  String get birthSkip => 'Skip';

  @override
  String get careFeedSubtitle => 'Something tasty for your little one';

  @override
  String get careFeedTitle => 'Feed';

  @override
  String get careFootnote =>
      'Petting isn\'t on the list: per spec section 8.1 it\'s a screen touch — just tap your bear on the home screen.';

  @override
  String careLockedUntilStage(int stage) {
    return 'Unlocks at stage $stage';
  }

  @override
  String get carePlaySubtitle => 'Fun and games together';

  @override
  String get carePlayTitle => 'Play';

  @override
  String get careSleepSubtitle => 'Good night, little bear';

  @override
  String get careSleepTitle => 'Tuck in';

  @override
  String get careTitle => 'What shall we do?';

  @override
  String get careWashSubtitle => 'Bath time!';

  @override
  String get careWashTitle => 'Bathe';

  @override
  String get catalogCheckoutTitle => 'Checkout';

  @override
  String get catalogCountryChina => 'China';

  @override
  String get catalogCountryGermany => 'Germany';

  @override
  String get catalogCountryKazakhstan => 'Kazakhstan';

  @override
  String get catalogCountryRussia => 'Russia';

  @override
  String get catalogCountryUsa => 'USA';

  @override
  String get catalogDeliveryNote =>
      'Delivery per the store: USA 7–9 business days, Canada 8–10, Europe 9–11, Asia 5–7. Orders go to the Client\'s live sales system (Brief 12.5) — this form doesn\'t submit anything yet.';

  @override
  String get catalogFieldAddress => 'Address';

  @override
  String get catalogFieldAddressHint => 'Street, building, apartment';

  @override
  String get catalogFieldCountry => 'Country';

  @override
  String get catalogFieldName => 'Full name';

  @override
  String get catalogFieldNameHint => 'As in your ID';

  @override
  String get catalogFieldPhone => 'Phone';

  @override
  String get catalogFieldPostcode => 'Postcode';

  @override
  String catalogFootnote(String shoes, String price) {
    return 'Items, prices and sizes come from the official TeddyTales® store, as required by Brief 12.1. The photos are identical placeholders: real shots will come from the Client\'s catalog. Shoes are sold there separately — $shoes, $price.';
  }

  @override
  String get catalogGrownSubtitle => 'and ready to come home to you';

  @override
  String get catalogGrownTitle => 'Your little one is all grown up';

  @override
  String get catalogItemFortune => 'Fortune Pocket Bear';

  @override
  String get catalogItemHug => 'Peachy Cuddle Bear';

  @override
  String get catalogItemShortFur => 'Short-Fur Teddy';

  @override
  String get catalogItemSpaceSet => 'Astronaut & Bride Set';

  @override
  String get catalogOrderButton => 'Order now';

  @override
  String get catalogPayPalNote => ' — or by card, no account needed';

  @override
  String get catalogPaySection => 'Payment · Brief 12.4';

  @override
  String get catalogPayStub => 'Payments will be connected during integration';

  @override
  String catalogSizeCm(int size) {
    return '$size cm';
  }

  @override
  String get catalogSummaryItem => 'Item';

  @override
  String get catalogSummaryPrice => 'Price';

  @override
  String get catalogSummarySize => 'Size';

  @override
  String get catalogTitle => 'Order a bear';

  @override
  String get categoryAccessory => 'Accessories';

  @override
  String get categoryBottom => 'Bottoms';

  @override
  String get categoryDecor => 'Decor';

  @override
  String get categoryFloor => 'Floor';

  @override
  String get categoryFurniture => 'Furniture';

  @override
  String get categoryHeadwear => 'Headwear';

  @override
  String get categoryOutfit => 'Outfits';

  @override
  String get categoryShoes => 'Shoes';

  @override
  String get categoryTop => 'Tops';

  @override
  String get categoryToy => 'Toys';

  @override
  String get categoryWallpaper => 'Wallpaper';

  @override
  String get commonBack => 'Back';

  @override
  String commonCoins(int count) {
    return '$count coins';
  }

  @override
  String get diaryEventFavoriteToy => 'A favorite toy';

  @override
  String get diaryEventFirstBath => 'First bath';

  @override
  String get diaryEventFirstCrawl => 'Learned to crawl';

  @override
  String get diaryEventFirstTooth => 'First tooth';

  @override
  String get diaryFootnote =>
      'The diary isn\'t in the КП — it comes from the mockup. Slated for version two and built as a draft. The photo album and sharing will need the camera and photo permissions. Event thumbnails are stubs: real photos arrive with the album.';

  @override
  String get diaryTitle => 'Diary';

  @override
  String get dishCookie => 'Cookies';

  @override
  String get dishFruit => 'Fruit';

  @override
  String get dishOmelette => 'Omelette';

  @override
  String get dishPasta => 'Pasta';

  @override
  String get dishPie => 'Pie';

  @override
  String get dishPorridge => 'Porridge';

  @override
  String get dishSalad => 'Salad';

  @override
  String get dishSandwich => 'Sandwich';

  @override
  String get dishSoup => 'Soup';

  @override
  String get dishYogurt => 'Yogurt';

  @override
  String get feedCookHint =>
      'Add the ingredients in order. Slip up? We\'ll simply try again.';

  @override
  String feedCookResult(String recipe, int reward, int gain) {
    String _temp0 = intl.Intl.pluralLogic(
      reward,
      locale: localeName,
      other: '$reward coins',
      one: '$reward coin',
    );
    return 'Done! $recipe · +$_temp0, food +$gain';
  }

  @override
  String get feedDishesNote =>
      'Exactly 10 dishes per spec 8.2. Prices and gains are placeholders — per spec 10.9 they are approved separately and configured from the server.';

  @override
  String feedEatResult(String dish, int gain, int price) {
    String _temp0 = intl.Intl.pluralLogic(
      price,
      locale: localeName,
      other: '$price coins',
      one: '$price coin',
    );
    return '$dish · food +$gain, −$_temp0';
  }

  @override
  String get feedFavourite => 'Favourite';

  @override
  String feedFoodGain(int gain) {
    return 'food +$gain';
  }

  @override
  String get feedHintActive =>
      'I\'ve been dashing about all day — let\'s have something filling!';

  @override
  String get feedHintAffectionate =>
      'I\'d love something sweet… with you close by.';

  @override
  String get feedHintCalm => 'Something warm and simple would be lovely.';

  @override
  String get feedHintCurious => 'Shall we cook something new?';

  @override
  String get feedHintIndependent => 'I could manage on my own. Well, almost.';

  @override
  String get feedHintReserved => 'Could I just have some fruit?';

  @override
  String get feedNotEnoughCoins => 'Not enough coins';

  @override
  String feedRecipeSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '$count step',
    );
    return '$_temp0';
  }

  @override
  String get feedRecipesNote =>
      'Exactly 5 recipes per spec 8.5: cookies and the sandwich take 3 steps, the rest take 4 to 6.';

  @override
  String feedStepProgress(int step, int total, int reward, int gain) {
    String _temp0 = intl.Intl.pluralLogic(
      reward,
      locale: localeName,
      other: '$reward coins',
      one: '$reward coin',
    );
    return 'Step $step of $total. Reward: $_temp0 and food +$gain.';
  }

  @override
  String get feedTabCook => 'Cook';

  @override
  String get feedTabReady => 'Ready meals';

  @override
  String get feedTitle => 'What shall we eat?';

  @override
  String feedWrongStep(String ingredient) {
    return 'Not quite. What we need now: $ingredient. Try again — no penalty.';
  }

  @override
  String game2048Hint(int target, int score) {
    return 'Swipe to merge equal tiles. Goal: $target. Score: $score';
  }

  @override
  String get game2048StuckHint =>
      'No moves left — start over with the button below.';

  @override
  String game2048Title(int level) {
    return '2048 · level $level';
  }

  @override
  String game2048WonHint(int target) {
    return 'You got $target! Enjoy your reward 🎉';
  }

  @override
  String gamePairsHint(int moves) {
    return 'Flip two matching cards. Moves: $moves';
  }

  @override
  String gamePairsSolvedHint(int moves) {
    String _temp0 = intl.Intl.pluralLogic(
      moves,
      locale: localeName,
      other: 'All pairs found in $moves moves 🎉',
      one: 'All pairs found in $moves move 🎉',
    );
    return '$_temp0';
  }

  @override
  String gamePairsTitle(int level) {
    return 'Memory · level $level';
  }

  @override
  String get gamePuzzleHint =>
      'Tap tiles to slide them and complete the photo.';

  @override
  String get gamePuzzleSolvedHint => 'Done! Enjoy your reward 🎉';

  @override
  String gamePuzzleTitle(int level) {
    return 'Puzzle · level $level';
  }

  @override
  String get gameRestart => 'Restart';

  @override
  String get growthAlreadyAdult => 'Your bear is all grown up';

  @override
  String get growthDurationAdult => 'onwards, no limits';

  @override
  String get growthDurationCrawling => '~2 days';

  @override
  String get growthDurationFirstSteps => '1–2 days';

  @override
  String get growthDurationGrowing => 'until around day 14';

  @override
  String get growthDurationNewborn => '1 day';

  @override
  String get growthFootnote =>
      'Names and durations come from КП 5. The mockup uses different ones (Baby, Cub, months instead of days) — that mismatch is still an open question.';

  @override
  String get growthGrowUp => 'Grow up';

  @override
  String get growthMarkNow => 'now';

  @override
  String get growthMarkPassed => 'done';

  @override
  String growthNewStage(String stage) {
    return 'New stage: $stage';
  }

  @override
  String get growthTitle => 'Growth & development';

  @override
  String get homeCareButton => 'What shall we do?';

  @override
  String get homeDevPanelTooltip => 'Rig dev panel';

  @override
  String homeScreenNotReady(String name) {
    return 'The “$name” screen isn’t ready yet';
  }

  @override
  String get ingredientApple => 'Apple';

  @override
  String get ingredientBanana => 'Banana';

  @override
  String get ingredientBread => 'Bread';

  @override
  String get ingredientButter => 'Butter';

  @override
  String get ingredientCabbage => 'Cabbage';

  @override
  String get ingredientCandy => 'Candy';

  @override
  String get ingredientCarrot => 'Carrot';

  @override
  String get ingredientCheese => 'Cheese';

  @override
  String get ingredientChocolate => 'Chocolate';

  @override
  String get ingredientFish => 'Fish';

  @override
  String get ingredientFlour => 'Flour';

  @override
  String get ingredientGreens => 'Herbs';

  @override
  String get ingredientHoney => 'Honey';

  @override
  String get ingredientMeat => 'Meat';

  @override
  String get ingredientOnion => 'Onion';

  @override
  String get ingredientOrange => 'Orange';

  @override
  String get ingredientPepper => 'Pepper';

  @override
  String get ingredientPotato => 'Potato';

  @override
  String get ingredientSalt => 'Salt';

  @override
  String get ingredientSpices => 'Spices';

  @override
  String get ingredientSugar => 'Sugar';

  @override
  String get ingredientTomato => 'Tomato';

  @override
  String get ingredientYogurt => 'Yogurt';

  @override
  String get itemAccBow => 'Bow';

  @override
  String get itemArmchair => 'Armchair';

  @override
  String get itemBall => 'Ball';

  @override
  String get itemBasket => 'Basket';

  @override
  String get itemBed => 'Bed';

  @override
  String get itemBotBlue => 'Blue Pants';

  @override
  String get itemBotSkirt => 'Pink Skirt';

  @override
  String get itemBotYellow => 'Yellow Shorts';

  @override
  String get itemCactus => 'Cactus';

  @override
  String get itemCar => 'Toy Car';

  @override
  String get itemChair => 'Chair';

  @override
  String get itemClock => 'Clock';

  @override
  String get itemCubes => 'Blocks';

  @override
  String get itemDresser => 'Dresser';

  @override
  String get itemDrum => 'Drum';

  @override
  String get itemDuck => 'Rubber Duck';

  @override
  String get itemFloorCarpet => 'Carpet Floor';

  @override
  String get itemFloorLight => 'Light Floor';

  @override
  String get itemFloorWood => 'Wooden Floor';

  @override
  String get itemGarland => 'Fairy Lights';

  @override
  String get itemHatCap => 'Hat';

  @override
  String get itemKite => 'Kite';

  @override
  String get itemLamp => 'Lamp';

  @override
  String get itemOutBear => 'Bear Costume';

  @override
  String get itemOutBee => 'Bee Costume';

  @override
  String get itemOutBerry => 'Strawberry Costume';

  @override
  String get itemOutGlasses => 'Glasses Set';

  @override
  String get itemOutSailor => 'Sailor Outfit';

  @override
  String get itemOutSport => 'Sporty Outfit';

  @override
  String get itemOutWinter => 'Winter Outfit';

  @override
  String get itemOutYellow => 'Yellow Outfit';

  @override
  String get itemPicBear => 'Bear Picture';

  @override
  String get itemPicForest => 'Forest Picture';

  @override
  String get itemPicMoon => 'Moon Picture';

  @override
  String get itemPillowHeart => 'Heart Pillow';

  @override
  String get itemPillowStar => 'Star Pillow';

  @override
  String get itemPlant => 'Plant';

  @override
  String get itemPoster => 'Poster';

  @override
  String get itemPuzzle => 'Puzzle';

  @override
  String get itemRocket => 'Rocket';

  @override
  String get itemRug => 'Rug';

  @override
  String get itemShelf => 'Bookshelf';

  @override
  String get itemTable => 'Table';

  @override
  String get itemTeddy => 'Teddy Bear';

  @override
  String get itemTopBlue => 'Blue Hoodie';

  @override
  String get itemTopRose => 'Pink Sweater';

  @override
  String get itemTopSage => 'Green Cardigan';

  @override
  String get itemTrain => 'Toy Train';

  @override
  String get itemWallRose => 'Pink Wallpaper';

  @override
  String get itemWallSage => 'Green Wallpaper';

  @override
  String get itemWallSky => 'Sky Wallpaper';

  @override
  String get itemWardrobe => 'Wardrobe';

  @override
  String get learnAdultLevelsNote =>
      'Finish a level to earn coins and unlock the next one. Difficulty grows with the level number.';

  @override
  String get learnAdultLogicSubtitle => '2048 in brand colors';

  @override
  String get learnAdultLogicTitle => 'Brain Teasers';

  @override
  String get learnAdultMemorySubtitle => 'Find the pairs';

  @override
  String get learnAdultMemoryTitle => 'Memory';

  @override
  String get learnAdultPuzzleSubtitle => 'Put together a bear photo';

  @override
  String get learnAdultPuzzleTitle => 'Puzzles';

  @override
  String get learnAgeAdultSubtitle => 'Bear puzzles, 2048, memory';

  @override
  String get learnAgeAdultTitle => 'Adult';

  @override
  String get learnAgeChildSubtitle =>
      'Colors and shapes, counting, the world around';

  @override
  String learnAgeChildTitle(int age) {
    return 'Child under $age';
  }

  @override
  String get learnAgeGateSubtitle =>
      'The set of games depends on age. You can change it anytime.';

  @override
  String get learnAgeGateTitle => 'Who\'s playing?';

  @override
  String get learnCatColorsTitle => 'Colors and Shapes';

  @override
  String get learnCatCountTitle => 'Counting and Simple Logic';

  @override
  String get learnCatWorldTitle => 'The World Around';

  @override
  String learnCorrectToast(int coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: 'Correct! +$coins coins',
      one: 'Correct! +$coins coin',
    );
    return '$_temp0';
  }

  @override
  String get learnGamesTitle => 'Games';

  @override
  String learnLevelDoneToast(int coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: 'Level complete! +$coins coins',
      one: 'Level complete! +$coins coin',
    );
    return '$_temp0';
  }

  @override
  String learnLevelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count levels',
      one: '$count level',
    );
    return '$_temp0';
  }

  @override
  String get learnLevelsNote =>
      '10 levels per category (spec 9.2). The engine is built for 300 tasks; content comes from the Client via the admin panel (spec 9.4) — three sample tasks per category for now.';

  @override
  String get learnQuizHintNote =>
      'A correct answer brings a happy animation and a reward.';

  @override
  String learnQuizTitle(String category, int level) {
    return '$category · level $level';
  }

  @override
  String get learnQuizWrongNote =>
      'Not quite. Try again — no penalty (spec 9.3).';

  @override
  String get learnTaskColorsCircle => 'Where is the circle?';

  @override
  String get learnTaskColorsGreen => 'Where is green?';

  @override
  String get learnTaskColorsRed => 'Where is red?';

  @override
  String get learnTaskCountApples => 'How many apples? 🍎🍎🍎';

  @override
  String get learnTaskCountBigger => 'Which one is bigger?';

  @override
  String get learnTaskCountNext => 'What comes next? 1, 2, 3…';

  @override
  String get learnTaskWorldApples => 'Where do apples grow?';

  @override
  String get learnTaskWorldDay => 'What shines in the daytime?';

  @override
  String get learnTaskWorldWater => 'Who lives in water?';

  @override
  String get learnTitle => 'Learning';

  @override
  String get moodDirty => 'Messy';

  @override
  String get moodHappy => 'Happy';

  @override
  String get moodHungry => 'Hungry';

  @override
  String get moodNormal => 'Content';

  @override
  String get moodSad => 'Sad';

  @override
  String get moodSleepy => 'Sleepy';

  @override
  String navLockReason(String stage) {
    return 'Unlocks at the “$stage” stage';
  }

  @override
  String get navSectionCatalog => 'Bears';

  @override
  String get navSectionHome => 'Home';

  @override
  String get navSectionLearning => 'Learning';

  @override
  String get navSectionProfile => 'Profile';

  @override
  String get navSectionRoom => 'Room';

  @override
  String get navSectionShop => 'Shop';

  @override
  String get profileAgeLabel => 'Age';

  @override
  String profileBirthFur(String hero, String fur) {
    return '$hero · $fur fur';
  }

  @override
  String get profileFootnote =>
      'Height, weight and zodiac sign are stubs: the server assigns them at birth (КП 2.2, 2.5), and the zodiac traits table comes from the Client.';

  @override
  String get profileHeightLabel => 'Height';

  @override
  String get profileHeightStub => '15 cm';

  @override
  String get profileLinkDiary => 'Diary';

  @override
  String get profileLinkDiarySubtitle => 'moments and photo album';

  @override
  String get profileLinkGrowth => 'Growth & development';

  @override
  String get profileLinkGrowthSubtitle =>
      'five stages and the road between them';

  @override
  String get profileLinkSettings => 'Settings';

  @override
  String get profileLinkSettingsSubtitle => 'language and notifications';

  @override
  String get profileSectionBirth => 'Birth card · КП 2.2';

  @override
  String get profileSectionHistory => 'Stage history · КП 14.1';

  @override
  String get profileSectionLinks => 'More';

  @override
  String get profileSectionTrait => 'Personality · КП 7';

  @override
  String get profileSexBoy => 'boy';

  @override
  String get profileSexGirl => 'girl';

  @override
  String get profileSexLabel => 'Sex';

  @override
  String get profileStageNow => 'now';

  @override
  String get profileStagePassed => 'done';

  @override
  String get profileStubBadge => 'stub';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileTraitHowLabel => 'How it\'s counted';

  @override
  String get profileTraitHowValue => 'from the last 3 days of care';

  @override
  String get profileTraitNowLabel => 'Right now';

  @override
  String get profileWeightLabel => 'Weight';

  @override
  String get profileWeightStub => '180 g';

  @override
  String get profileZodiacLabel => 'Zodiac sign';

  @override
  String get recipeCookie => 'Cookies';

  @override
  String get recipeFruitSalad => 'Fruit salad';

  @override
  String get recipeMeat => 'Meat dish';

  @override
  String get recipeSandwich => 'Sandwich';

  @override
  String get recipeVeggie => 'Veggie dish';

  @override
  String get roomFooterNote =>
      '52 items per brief section 10: furniture 10, decor 16, toys 10, clothes 16. The placement grid and room preview come next — for now an item is simply placed or put away.';

  @override
  String roomItemBought(String name) {
    return '$name purchased';
  }

  @override
  String roomItemPlaced(String name) {
    return '$name placed';
  }

  @override
  String roomItemRemoved(String name) {
    return '$name put away';
  }

  @override
  String get roomNotEnoughCoins => 'Not enough coins';

  @override
  String get roomOwnedLabel => 'Owned';

  @override
  String get roomSelectedLabel => 'Selected';

  @override
  String get roomTitle => 'My Room';

  @override
  String get settingsFootnote =>
      'Eight notification types per КП 13.1; quiet hours and frequency limits per 13.2. Account linking and legal documents (КП 14.2) arrive together with the backend.';

  @override
  String get settingsNotifEvent => 'Event';

  @override
  String get settingsNotifGift => 'Gift';

  @override
  String get settingsNotifHungry => 'Hungry';

  @override
  String get settingsNotifPlay => 'Wants to play';

  @override
  String get settingsNotifShopNews => 'Shop news';

  @override
  String get settingsNotifSleep => 'Bedtime';

  @override
  String get settingsNotifStage => 'New stage';

  @override
  String get settingsNotifTask => 'Task';

  @override
  String get settingsQuietHours => 'Quiet hours 22:00 — 8:00';

  @override
  String get settingsSectionLanguage => 'Language · КП 16.1';

  @override
  String get settingsSectionNotifications => 'Notifications · КП 13.1, 13.2';

  @override
  String get settingsTitle => 'Settings';

  @override
  String shopBuyFor(int total) {
    return 'Buy for $total';
  }

  @override
  String get shopCartDisclaimer =>
      'The cart isn\'t in the brief — it comes from the mockup and belongs to version two, but it\'s built here so the flow is visible. Prices are placeholders (brief 10.9).';

  @override
  String get shopCartEmpty => 'Cart is empty';

  @override
  String shopCheckoutDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bought $count items',
      one: 'Bought $count item',
    );
    return '$_temp0';
  }

  @override
  String get shopNotEnoughCoins => 'Not enough coins';

  @override
  String get shopOwnedLabel => 'Owned';

  @override
  String get shopTabClothes => 'Clothes';

  @override
  String get shopTabDecor => 'Decor';

  @override
  String get shopTabFurniture => 'Furniture';

  @override
  String get shopTabToys => 'Toys';

  @override
  String get shopTitle => 'Shop';

  @override
  String get skinJoy => 'JOY';

  @override
  String get skinSlow => 'SLOW';

  @override
  String get stageAdult => 'Grown-up';

  @override
  String get stageCrawling => 'Crawling baby';

  @override
  String get stageFirstSteps => 'First steps';

  @override
  String get stageGrowing => 'Growing up';

  @override
  String get stageNewborn => 'Newborn';

  @override
  String get statsFood => 'Food';

  @override
  String get statsHygiene => 'Hygiene';

  @override
  String get statsLove => 'Love';

  @override
  String get statsPlay => 'Play';

  @override
  String get statsSleep => 'Sleep';

  @override
  String get traitActive => 'Active';

  @override
  String get traitAffectionate => 'Affectionate';

  @override
  String get traitCalm => 'Calm';

  @override
  String get traitCurious => 'Curious';

  @override
  String get traitIndependent => 'Independent';

  @override
  String get traitReserved => 'Reserved';

  @override
  String get zodiacAquarius => 'Aquarius';

  @override
  String get zodiacAries => 'Aries';

  @override
  String get zodiacCancer => 'Cancer';

  @override
  String get zodiacCapricorn => 'Capricorn';

  @override
  String get zodiacGemini => 'Gemini';

  @override
  String get zodiacInfluenceAquarius =>
      'An inventive free spirit: full of surprises and their own ways.';

  @override
  String get zodiacInfluenceAries =>
      'Bold and impulsive: eager to try everything on their own from day one.';

  @override
  String get zodiacInfluenceCancer =>
      'A gentle homebody: care and long hugs make them bloom.';

  @override
  String get zodiacInfluenceCapricorn =>
      'Patient and persistent: reaches big things one small step at a time.';

  @override
  String get zodiacInfluenceGemini =>
      'Curious and sociable: reaches for anything new with both paws.';

  @override
  String get zodiacInfluenceLeo =>
      'Warm and theatrical: adores attention and gives back plenty of affection.';

  @override
  String get zodiacInfluenceLibra =>
      'A friendly peacemaker: fond of beauty, company and a gentle tone.';

  @override
  String get zodiacInfluencePisces =>
      'Dreamy and sensitive: quietly attuned to your mood.';

  @override
  String get zodiacInfluenceSagittarius =>
      'A cheerful adventurer: games and outings are their element.';

  @override
  String get zodiacInfluenceScorpio =>
      'Deep and devoted: forms bonds that are serious and lasting.';

  @override
  String get zodiacInfluenceTaurus =>
      'Calm and steady: loves comfort, good food and a familiar routine.';

  @override
  String get zodiacInfluenceVirgo =>
      'Attentive and tidy: notices the little things and likes everything in order.';

  @override
  String get zodiacLeo => 'Leo';

  @override
  String get zodiacLibra => 'Libra';

  @override
  String get zodiacPisces => 'Pisces';

  @override
  String get zodiacSagittarius => 'Sagittarius';

  @override
  String get zodiacScorpio => 'Scorpio';

  @override
  String get zodiacTaurus => 'Taurus';

  @override
  String get zodiacVirgo => 'Virgo';
}

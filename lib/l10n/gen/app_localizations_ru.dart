// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String ageDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней',
      few: '$count дня',
      one: '$count день',
    );
    return '$_temp0';
  }

  @override
  String ageMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count месяцев',
      few: '$count месяца',
      one: '$count месяц',
    );
    return '$_temp0';
  }

  @override
  String ageMonthsDays(int months, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months месяцев',
      few: '$months месяца',
      one: '$months месяц',
    );
    String _temp1 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days дней',
      few: '$days дня',
      one: '$days день',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count лет',
      few: '$count года',
      one: '$count год',
    );
    return '$_temp0';
  }

  @override
  String get appTitle => 'TeddyTales';

  @override
  String get bathActionToilet => 'В туалет';

  @override
  String get bathActionWash => 'Искупаться';

  @override
  String get bedroomActionSleep => 'Уложить спать';

  @override
  String get bedroomWakeTogether => 'Давай проснёмся вместе';

  @override
  String get bedroomAlarmQuestion => 'В какое время поставить будильник?';

  @override
  String bedroomAlarmSet(String time) {
    return 'Будильник на $time';
  }

  @override
  String get bedroomAlarmHelp => 'Когда просыпаемся?';

  @override
  String get bedroomActionWake => 'Разбудить';

  @override
  String get bedroomAlarmDone => 'Готово';

  @override
  String get bathWashSoon => 'Чиним душ — скоро сможем купать малыша';

  @override
  String get bathToiletSoon => 'Горшок ещё в работе — скоро научим';

  @override
  String bearRigMissingHint(String path) {
    return 'Положите $path';
  }

  @override
  String get bearRigMissingTitle => 'Риг ещё не подключён';

  @override
  String get birthCueAwakening => 'Малыш открывает глаза и осматривается.';

  @override
  String get birthCueCradle =>
      'Тёплая кроватка. Кто-то тихо дышит под одеялом…';

  @override
  String get birthCueFinale => 'Он успокоился. Здравствуй, малыш.';

  @override
  String get birthCueFirstBreath => 'Первый вдох…';

  @override
  String get birthCueFirstCry => 'Первый плач — он зовёт тебя.';

  @override
  String get birthCueStars => 'Звёздочки кружатся в мягком свете.';

  @override
  String get birthSceneNotReady => 'Сцена рождения ещё не собрана';

  @override
  String get birthSkip => 'Пропустить';

  @override
  String get careFeedSubtitle => 'Вкусная еда для малыша';

  @override
  String get careFeedTitle => 'Покормить';

  @override
  String get careFootnote =>
      'Поглаживания в списке нет: по разделу 8.1 ТЗ это касание экрана — тапните по мишке на главной.';

  @override
  String careLockedUntilStage(int stage) {
    return 'Откроется на стадии $stage';
  }

  @override
  String get carePlaySubtitle => 'Весёлые игры вместе';

  @override
  String get carePlayTitle => 'Играть';

  @override
  String get careSleepSubtitle => 'Спокойной ночи, малыш';

  @override
  String get careSleepTitle => 'Уложить спать';

  @override
  String get careTitle => 'Что будем делать?';

  @override
  String get careWashSubtitle => 'Пора в ванну!';

  @override
  String get careWashTitle => 'Купать';

  @override
  String get catalogCheckoutTitle => 'Оформление';

  @override
  String get catalogCountryChina => 'Китай';

  @override
  String get catalogCountryGermany => 'Германия';

  @override
  String get catalogCountryKazakhstan => 'Казахстан';

  @override
  String get catalogCountryRussia => 'Россия';

  @override
  String get catalogCountryUsa => 'США';

  @override
  String get catalogDeliveryNote =>
      'Доставка по данным магазина: США 7–9 рабочих дней, Канада 8–10, Европа 9–11, Азия 5–7. Заказ уходит в действующую систему продаж Заказчика (КП 12.5) — здесь форма без отправки.';

  @override
  String get catalogFieldAddress => 'Адрес';

  @override
  String get catalogFieldAddressHint => 'Улица, дом, квартира';

  @override
  String get catalogFieldCountry => 'Страна';

  @override
  String get catalogFieldName => 'Имя и фамилия';

  @override
  String get catalogFieldNameHint => 'Как в документах';

  @override
  String get catalogFieldPhone => 'Телефон';

  @override
  String get catalogFieldPostcode => 'Индекс';

  @override
  String catalogFootnote(String shoes, String price) {
    return 'Товары, цены и размеры — из официального магазина TeddyTales®, как требует КП 12.1. Фотографии подставлены одинаковые: настоящие снимки берутся из каталога Заказчика. Обувь там продаётся отдельно — $shoes, $price.';
  }

  @override
  String get catalogGrownSubtitle => 'и готов отправиться к тебе домой';

  @override
  String get catalogGrownTitle => 'Твой малыш вырос';

  @override
  String get catalogItemFortune => 'Карманный мишка Фортуна';

  @override
  String get catalogItemHug => 'Персиковый Обнимишка';

  @override
  String get catalogItemShortFur => 'Мишка с короткой шерсткой';

  @override
  String get catalogItemSpaceSet => 'Набор Космонавт и Невеста';

  @override
  String get catalogOrderButton => 'Оформить заказ';

  @override
  String get catalogPayPalNote => ' — и картой без аккаунта';

  @override
  String get catalogPaySection => 'Оплата · КП 12.4';

  @override
  String get catalogPayStub => 'Оплата подключается на этапе интеграции';

  @override
  String catalogSizeCm(int size) {
    return '$size см';
  }

  @override
  String get catalogSummaryItem => 'Товар';

  @override
  String get catalogSummaryPrice => 'Цена';

  @override
  String get catalogSummarySize => 'Размер';

  @override
  String get catalogTitle => 'Заказать мишку';

  @override
  String get categoryAccessory => 'Аксессуары';

  @override
  String get categoryBottom => 'Низ';

  @override
  String get categoryDecor => 'Декор';

  @override
  String get categoryFloor => 'Пол';

  @override
  String get categoryFurniture => 'Мебель';

  @override
  String get categoryHeadwear => 'Головные уборы';

  @override
  String get categoryOutfit => 'Наряды';

  @override
  String get categoryShoes => 'Обувь';

  @override
  String get categoryTop => 'Верх';

  @override
  String get categoryToy => 'Игрушки';

  @override
  String get categoryWallpaper => 'Обои';

  @override
  String get commonBack => 'Назад';

  @override
  String get commonCancel => 'Отмена';

  @override
  String commonCoins(int count) {
    return '$count монет';
  }

  @override
  String get diaryEventFavoriteToy => 'Любимая игрушка';

  @override
  String get diaryEventFirstBath => 'Первое купание';

  @override
  String get diaryEventFirstCrawl => 'Научился ползать';

  @override
  String get diaryEventFirstTooth => 'Первый зубик';

  @override
  String get diaryFootnote =>
      'Дневника нет в КП — он с макета. Отнесён ко второй версии, собран как заготовка. Фотоальбом и «Поделиться» потребуют камеры и прав на съёмку. Миниатюра события — заглушка: настоящие снимки появятся вместе с фотоальбомом.';

  @override
  String get diaryTitle => 'Дневник';

  @override
  String get dishCookie => 'Печенье';

  @override
  String get dishFruit => 'Фрукты';

  @override
  String get dishOmelette => 'Омлет';

  @override
  String get dishPasta => 'Паста';

  @override
  String get dishPie => 'Пирог';

  @override
  String get dishPorridge => 'Каша';

  @override
  String get dishSalad => 'Салат';

  @override
  String get dishSandwich => 'Сэндвич';

  @override
  String get dishSoup => 'Суп';

  @override
  String get dishYogurt => 'Йогурт';

  @override
  String get dishDescPorridge => 'с ягодами и мёдом';

  @override
  String get dishDescSoup => 'с морковкой и горошком';

  @override
  String get dishDescSandwich => 'с сыром и ветчиной';

  @override
  String get dishDescFruit => 'клубника, банан, виноград';

  @override
  String get dishDescYogurt => 'с гранолой и ягодами';

  @override
  String get dishDescCookie => 'шоколадное и мишки';

  @override
  String get dishDescSalad => 'огурец, помидоры, кукуруза';

  @override
  String get dishDescPasta => 'с томатным соусом';

  @override
  String get dishDescOmelette => 'с зелёным луком';

  @override
  String get dishDescPie => 'с малиной и черникой';

  @override
  String get feedCookHint =>
      'Добавляй продукты по порядку. Ошибёшься — просто попробуем ещё раз.';

  @override
  String feedCookResult(String recipe, int reward, int gain) {
    String _temp0 = intl.Intl.pluralLogic(
      reward,
      locale: localeName,
      other: '$reward монет',
      few: '$reward монеты',
      one: '$reward монета',
    );
    return 'Готово! $recipe · +$_temp0, еда +$gain';
  }

  @override
  String get feedDishesNote =>
      'Ровно 10 блюд по КП 8.2. Цены и прибавки — плейсхолдеры, по КП 10.9 они утверждаются отдельно и настраиваются с сервера.';

  @override
  String feedEatResult(String dish, int gain, int price) {
    String _temp0 = intl.Intl.pluralLogic(
      price,
      locale: localeName,
      other: '$price монет',
      few: '$price монеты',
      one: '$price монета',
    );
    return '$dish · еда +$gain, −$_temp0';
  }

  @override
  String get feedFavourite => 'Любимое';

  @override
  String feedFoodGain(int gain) {
    return 'еда +$gain';
  }

  @override
  String get feedHintActive =>
      'Я сегодня носился как заводной — давай посытнее!';

  @override
  String get feedHintAffectionate =>
      'Хочу что-нибудь сладкое… и чтобы ты рядом.';

  @override
  String get feedHintCalm => 'Мне бы чего-то тёплого и простого.';

  @override
  String get feedHintCurious => 'А приготовим что-нибудь новенькое?';

  @override
  String get feedHintIndependent => 'Я бы и сам справился. Ну, почти.';

  @override
  String get feedHintReserved => 'Можно просто фрукты?';

  @override
  String get feedNotEnoughCoins => 'Не хватает монет';

  @override
  String feedRecipeSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count шагов',
      few: '$count шага',
      one: '$count шаг',
    );
    return '$_temp0';
  }

  @override
  String get feedRecipesNote =>
      'Ровно 5 рецептов по КП 8.5: печенье и сэндвич — по 3 шага, остальные — от 4 до 6.';

  @override
  String feedStepProgress(int step, int total, int reward, int gain) {
    String _temp0 = intl.Intl.pluralLogic(
      reward,
      locale: localeName,
      other: '$reward монет',
      few: '$reward монеты',
      one: '$reward монета',
    );
    return 'Шаг $step из $total. Награда: $_temp0 и еда +$gain.';
  }

  @override
  String get feedTabCook => 'Приготовить';

  @override
  String get feedTabReady => 'Готовые блюда';

  @override
  String get feedTitle => 'Чем покормим?';

  @override
  String feedWrongStep(String ingredient) {
    return 'Не то. Сейчас нужно: $ingredient. Попробуй ещё раз — штрафа нет.';
  }

  @override
  String game2048Hint(int target, int score) {
    return 'Свайпайте: равные плитки сливаются. Цель — $target. Счёт: $score';
  }

  @override
  String get game2048StuckHint =>
      'Ходов не осталось — начните заново кнопкой ниже.';

  @override
  String game2048Title(int level) {
    return '2048 · уровень $level';
  }

  @override
  String game2048WonHint(int target) {
    return 'Есть $target! Забирайте награду 🎉';
  }

  @override
  String gamePairsHint(int moves) {
    return 'Откройте две одинаковые карточки. Ходы: $moves';
  }

  @override
  String gamePairsSolvedHint(int moves) {
    String _temp0 = intl.Intl.pluralLogic(
      moves,
      locale: localeName,
      other: 'Все пары найдены за $moves ходов 🎉',
      few: 'Все пары найдены за $moves хода 🎉',
      one: 'Все пары найдены за $moves ход 🎉',
    );
    return '$_temp0';
  }

  @override
  String gamePairsTitle(int level) {
    return 'Память · уровень $level';
  }

  @override
  String get gamePuzzleHint => 'Двигайте плитки тапом — соберите фото.';

  @override
  String get gamePuzzleSolvedHint => 'Собрано! Забирайте награду 🎉';

  @override
  String gamePuzzleTitle(int level) {
    return 'Пазл · уровень $level';
  }

  @override
  String get gameRestart => 'Заново';

  @override
  String get growthAlreadyAdult => 'Мишка уже взрослый';

  @override
  String get growthDurationAdult => 'дальше без ограничений';

  @override
  String get growthDurationCrawling => '~2 дня';

  @override
  String get growthDurationFirstSteps => '1–2 дня';

  @override
  String get growthDurationGrowing => 'до ~14 дня';

  @override
  String get growthDurationNewborn => '1 день';

  @override
  String get growthFootnote =>
      'Названия и длительности — из КП 5. На макете они другие (Малыш, Детёныш, месяцы вместо дней) — это расхождение висит открытым вопросом.';

  @override
  String get growthGrowUp => 'Повзрослеть';

  @override
  String get growthMarkNow => 'сейчас';

  @override
  String get growthMarkPassed => 'пройдено';

  @override
  String growthNewStage(String stage) {
    return 'Новая стадия: $stage';
  }

  @override
  String get growthTitle => 'Рост и развитие';

  @override
  String get homeCareButton => 'Что будем делать?';

  @override
  String get homeDevPanelTooltip => 'Дев-панель рига';

  @override
  String homeScreenNotReady(String name) {
    return 'Экран для «$name» ещё не собран';
  }

  @override
  String get ingredientApple => 'Яблоко';

  @override
  String get ingredientBanana => 'Банан';

  @override
  String get ingredientBread => 'Хлеб';

  @override
  String get ingredientButter => 'Масло';

  @override
  String get ingredientCabbage => 'Капуста';

  @override
  String get ingredientCandy => 'Конфета';

  @override
  String get ingredientCarrot => 'Морковь';

  @override
  String get ingredientCheese => 'Сыр';

  @override
  String get ingredientChocolate => 'Шоколад';

  @override
  String get ingredientFish => 'Рыба';

  @override
  String get ingredientFlour => 'Мука';

  @override
  String get ingredientGreens => 'Зелень';

  @override
  String get ingredientHoney => 'Мёд';

  @override
  String get ingredientMeat => 'Мясо';

  @override
  String get ingredientOnion => 'Лук';

  @override
  String get ingredientOrange => 'Апельсин';

  @override
  String get ingredientPepper => 'Перец';

  @override
  String get ingredientPotato => 'Картофель';

  @override
  String get ingredientSalt => 'Соль';

  @override
  String get ingredientSpices => 'Специи';

  @override
  String get ingredientSugar => 'Сахар';

  @override
  String get ingredientTomato => 'Помидор';

  @override
  String get ingredientYogurt => 'Йогурт';

  @override
  String get itemAccBow => 'Бантик';

  @override
  String get itemArmchair => 'Кресло';

  @override
  String get itemBall => 'Мячик';

  @override
  String get itemBasket => 'Корзина';

  @override
  String get itemShelfHouse => 'Полка-домик';

  @override
  String get itemShelfMoon => 'Полка-месяц';

  @override
  String get itemArmchairSage => 'Кресло мятное';

  @override
  String get itemArmchairBean => 'Кресло-пуф';

  @override
  String get itemArmchairFlower => 'Кресло-цветок';

  @override
  String get itemArmchairWing => 'Кресло с ушками';

  @override
  String get itemSwing => 'Подвесное кресло';

  @override
  String get itemBasketStar => 'Корзина со звездой';

  @override
  String get itemRugCloud => 'Ковёр-облако';

  @override
  String get itemRugHeart => 'Ковёр с сердцем';

  @override
  String get itemPicHeart => 'Картина с сердцем';

  @override
  String get itemPlantIvy => 'Плющ на подставке';

  @override
  String get itemPlantBear => 'Цветок в кашпо-мишке';

  @override
  String get itemFlowersDaisy => 'Ромашки в банке';

  @override
  String get itemFlowersOrchid => 'Орхидея';

  @override
  String get itemFlowersEuc => 'Эвкалипт в вазе';

  @override
  String get itemTeddyCream => 'Мишка кремовый';

  @override
  String get itemBunny => 'Зайчик';

  @override
  String get itemBunnyPink => 'Зайчик розовый';

  @override
  String get itemPyramid => 'Пирамидка';

  @override
  String get itemDollhouse => 'Кукольный домик';

  @override
  String get itemHouseFelt => 'Домик из фетра';

  @override
  String get itemBed => 'Кроватка';

  @override
  String get itemBotBlue => 'Штаны синие';

  @override
  String get itemBotSkirt => 'Юбка розовая';

  @override
  String get itemBotYellow => 'Шорты жёлтые';

  @override
  String get itemCactus => 'Кактус';

  @override
  String get itemCar => 'Машинка';

  @override
  String get itemChair => 'Стул';

  @override
  String get itemClock => 'Часы';

  @override
  String get itemCubes => 'Кубики';

  @override
  String get itemDresser => 'Комод';

  @override
  String get itemDrum => 'Барабан';

  @override
  String get itemDuck => 'Уточка';

  @override
  String get itemFloorCarpet => 'Пол ковролин';

  @override
  String get itemFloorLight => 'Пол светлый';

  @override
  String get itemFloorWood => 'Пол дерево';

  @override
  String get itemGarland => 'Гирлянда';

  @override
  String get itemHatCap => 'Шапка';

  @override
  String get itemKite => 'Воздушный змей';

  @override
  String get itemLamp => 'Светильник';

  @override
  String get itemOutBear => 'Костюм мишки';

  @override
  String get itemOutBee => 'Костюм пчёлка';

  @override
  String get itemOutBerry => 'Костюм клубника';

  @override
  String get itemOutGlasses => 'Комплект очкарик';

  @override
  String get itemOutSailor => 'Комплект матрос';

  @override
  String get itemOutSport => 'Комплект спорт';

  @override
  String get itemOutWinter => 'Комплект зимний';

  @override
  String get itemOutYellow => 'Комплект жёлтый';

  @override
  String get itemPicBear => 'Картина мишка';

  @override
  String get itemPicForest => 'Картина лес';

  @override
  String get itemPicMoon => 'Картина луна';

  @override
  String get itemPillowHeart => 'Подушка сердце';

  @override
  String get itemPillowStar => 'Подушка звезда';

  @override
  String get itemPlant => 'Растение';

  @override
  String get itemPoster => 'Постер';

  @override
  String get itemPuzzle => 'Пазл';

  @override
  String get itemRocket => 'Ракета';

  @override
  String get itemRug => 'Ковёр';

  @override
  String get itemShelf => 'Книжная полка';

  @override
  String get itemTable => 'Стол';

  @override
  String get itemTeddy => 'Мишка';

  @override
  String get itemTopBlue => 'Толстовка голубая';

  @override
  String get itemTopRose => 'Свитер розовый';

  @override
  String get itemTopSage => 'Кофта зелёная';

  @override
  String get itemTrain => 'Паровозик';

  @override
  String get itemWallRose => 'Обои розовые';

  @override
  String get itemWallSage => 'Обои зелёные';

  @override
  String get itemWallSky => 'Обои небо';

  @override
  String get itemWardrobe => 'Шкаф';

  @override
  String get learnAdultLevelsNote =>
      'Уровень пройден — монеты в кошелёк, следующий открывается. Сложность растёт с номером уровня.';

  @override
  String get learnAdultLogicSubtitle => '2048 в фирменных цветах';

  @override
  String get learnAdultLogicTitle => 'Головоломки';

  @override
  String get learnAdultMemorySubtitle => 'Найдите пары';

  @override
  String get learnAdultMemoryTitle => 'Память';

  @override
  String get learnAdultPuzzleSubtitle => 'Соберите фото мишки';

  @override
  String get learnAdultPuzzleTitle => 'Пазлы';

  @override
  String get learnAgeAdultSubtitle => 'Пазлы с мишками, 2048, память';

  @override
  String get learnAgeAdultTitle => 'Взрослый';

  @override
  String get learnAgeChildSubtitle => 'Цвета и формы, счёт, окружающий мир';

  @override
  String learnAgeChildTitle(int age) {
    return 'Ребёнок до $age';
  }

  @override
  String get learnAgeGateSubtitle =>
      'От возраста зависит набор игр. Поменять можно в любой момент.';

  @override
  String get learnAgeGateTitle => 'Кто будет играть?';

  @override
  String get learnCatColorsTitle => 'Цвета и формы';

  @override
  String get learnCatCountTitle => 'Счёт и простая логика';

  @override
  String learnCatLocked(String stage) {
    return 'Откроется на стадии «$stage»';
  }

  @override
  String get learnCatWorldTitle => 'Окружающий мир';

  @override
  String learnCorrectToast(int coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: 'Верно! +$coins монет',
      few: 'Верно! +$coins монеты',
      one: 'Верно! +$coins монета',
    );
    return '$_temp0';
  }

  @override
  String get learnGamesTitle => 'Игры';

  @override
  String learnLevelDoneToast(int coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: 'Уровень пройден! +$coins монет',
      few: 'Уровень пройден! +$coins монеты',
      one: 'Уровень пройден! +$coins монета',
    );
    return '$_temp0';
  }

  @override
  String learnLevelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count уровней',
      few: '$count уровня',
      one: '$count уровень',
    );
    return '$_temp0';
  }

  @override
  String get learnLevelsNote =>
      'По 10 уровней в каждой категории (КП 9.2). Движок рассчитан на 300 заданий, контент даёт Заказчик через панель (КП 9.4) — здесь по три задания на категорию для примера.';

  @override
  String get learnQuizHintNote => 'Верный ответ — анимация радости и награда.';

  @override
  String learnQuizTitle(String category, int level) {
    return '$category · уровень $level';
  }

  @override
  String get learnQuizWrongNote =>
      'Не угадали. Попробуйте ещё раз — штрафа нет (КП 9.3).';

  @override
  String get learnTaskColorsCircle => 'Где круг?';

  @override
  String get learnTaskColorsGreen => 'Где зелёный?';

  @override
  String get learnTaskColorsRed => 'Где красный?';

  @override
  String get learnTaskCountApples => 'Сколько яблок? 🍎🍎🍎';

  @override
  String get learnTaskCountBigger => 'Что больше?';

  @override
  String get learnTaskCountNext => 'Что дальше? 1, 2, 3…';

  @override
  String learnTaskProgress(int current, int total) {
    return 'Задание $current из $total';
  }

  @override
  String get learnTaskWorldApples => 'Где растут яблоки?';

  @override
  String get learnTaskWorldDay => 'Что светит днём?';

  @override
  String get learnTaskWorldWater => 'Кто живёт в воде?';

  @override
  String get learnTitle => 'Обучение';

  @override
  String get moodDirty => 'Чумазый';

  @override
  String get moodHappy => 'Радостный';

  @override
  String get moodHungry => 'Голодный';

  @override
  String get moodNormal => 'Спокойный';

  @override
  String get moodSad => 'Грустный';

  @override
  String get moodSleepy => 'Сонный';

  @override
  String nameChanged(String name) {
    return 'Теперь малыша зовут $name';
  }

  @override
  String get nameFirstLead =>
      'Малыш появился на свет. Как его назовёте? Имя можно будет поменять в профиле.';

  @override
  String get nameFirstSave => 'Назвать';

  @override
  String get nameFirstLater => 'Позже';

  @override
  String get nameDialogHint => 'Имя питомца';

  @override
  String nameDialogNote(int min, int max) {
    return 'От $min до $max знаков. Буквы, пробел и дефис.';
  }

  @override
  String get nameDialogSave => 'Сохранить';

  @override
  String get nameDialogTitle => 'Как зовут малыша?';

  @override
  String get nameErrorBlocked => 'Такое имя не подойдёт малышу';

  @override
  String get nameErrorCharacters => 'Только буквы, пробел и дефис';

  @override
  String get nameErrorEmpty => 'Впишите имя';

  @override
  String nameErrorLong(int max) {
    return 'Не длиннее $max знаков';
  }

  @override
  String get nameErrorNetwork => 'Не получилось сохранить — попробуйте ещё раз';

  @override
  String nameErrorShort(int min) {
    return 'Не короче $min знаков';
  }

  @override
  String navLockReason(String stage) {
    return 'Откроется на стадии «$stage»';
  }

  @override
  String get navSectionCatalog => 'Мишки';

  @override
  String get navSectionHome => 'Главная';

  @override
  String get navSectionLearning => 'Обучение';

  @override
  String get navSectionProfile => 'Профиль';

  @override
  String get navSectionRoom => 'Обставить';

  @override
  String get navSectionShop => 'Магазин';

  @override
  String get petDefaultName => 'Мой малыш';

  @override
  String get profileAgeLabel => 'Возраст';

  @override
  String profileBirthFur(String hero, String fur) {
    return '$hero · мех $fur';
  }

  @override
  String get profileFootnote =>
      'Рост, вес и знак зодиака — заглушки: их определяет сервер при рождении (КП 2.2, 2.5), а таблицу склонностей по знакам даёт Заказчик.';

  @override
  String get profileHeightLabel => 'Рост';

  @override
  String get profileHeightStub => '15 см';

  @override
  String get profileLinkDiary => 'Дневник';

  @override
  String get profileLinkDiarySubtitle => 'события и фотоальбом';

  @override
  String get profileLinkGrowth => 'Рост и развитие';

  @override
  String get profileLinkGrowthSubtitle => 'пять стадий и переходы';

  @override
  String get profileLinkSettings => 'Настройки';

  @override
  String get profileLinkSettingsSubtitle => 'язык и уведомления';

  @override
  String get profileRename => 'Изменить имя';

  @override
  String get profileSectionBirth => 'Карточка рождения · КП 2.2';

  @override
  String get profileSectionHistory => 'История стадий · КП 14.1';

  @override
  String get profileSectionLinks => 'Разделы';

  @override
  String get profileSectionTrait => 'Характер · КП 7';

  @override
  String get profileSexBoy => 'мальчик';

  @override
  String get profileSexGirl => 'девочка';

  @override
  String get profileSexLabel => 'Пол';

  @override
  String get profileStageNow => 'сейчас';

  @override
  String get profileStagePassed => 'пройдено';

  @override
  String get profileStubBadge => 'заглушка';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get profileTraitHowLabel => 'Как считается';

  @override
  String get profileTraitHowValue => 'из действий за 3 дня';

  @override
  String get profileTraitNowLabel => 'Сейчас';

  @override
  String get profileWeightLabel => 'Вес';

  @override
  String get profileWeightStub => '180 г';

  @override
  String get profileZodiacLabel => 'Знак зодиака';

  @override
  String get recipeCookie => 'Печенье';

  @override
  String get recipeFruitSalad => 'Фруктовый салат';

  @override
  String get recipeMeat => 'Мясное блюдо';

  @override
  String get recipeSandwich => 'Сэндвич';

  @override
  String get recipeVeggie => 'Овощное блюдо';

  @override
  String get roomFooterNote =>
      '52 предмета по КП 10: мебель 10, декор 16, игрушки 10, одежда 16. Сетка мест и предпросмотр — следующий шаг, сейчас предмет просто ставится или убирается.';

  @override
  String roomItemBought(String name) {
    return 'Куплено: $name';
  }

  @override
  String roomItemPlaced(String name) {
    return '$name поставлено';
  }

  @override
  String roomItemRemoved(String name) {
    return '$name убрано';
  }

  @override
  String get roomKindBath => 'Ванная';

  @override
  String get roomKindKitchen => 'Кухня';

  @override
  String get roomKindNursery => 'Детская';

  @override
  String get roomNotEnoughCoins => 'Не хватает монет';

  @override
  String get roomOwnedLabel => 'Куплено';

  @override
  String get roomSelectedLabel => 'Выбрано';

  @override
  String get roomSheetOwned => 'уже есть';

  @override
  String get roomSheetRemove => 'Убрать из комнаты';

  @override
  String get roomSheetReplace => 'Заменить на';

  @override
  String get roomSlotEmpty => 'Свободное место';

  @override
  String get roomSlotPut => 'Поставить';

  @override
  String get roomTitle => 'Моя комната';

  @override
  String get settingsFootnote =>
      'Восемь типов уведомлений по КП 13.1, тихие часы и ограничение частоты — по 13.2. Привязка аккаунта и правовые документы (КП 14.2) появятся вместе с бэкендом.';

  @override
  String get settingsNotifEvent => 'Событие';

  @override
  String get settingsNotifGift => 'Подарок';

  @override
  String get settingsNotifHungry => 'Голоден';

  @override
  String get settingsNotifPlay => 'Хочет играть';

  @override
  String get settingsNotifShopNews => 'Новинки магазина';

  @override
  String get settingsNotifSleep => 'Пора спать';

  @override
  String get settingsNotifStage => 'Новая стадия';

  @override
  String get settingsNotifTask => 'Задание';

  @override
  String get settingsQuietHours => 'Тихие часы 22:00 — 8:00';

  @override
  String get settingsSectionAccount => 'Аккаунт';

  @override
  String get settingsSectionLanguage => 'Язык · КП 16.1';

  @override
  String get settingsSectionNotifications => 'Уведомления · КП 13.1, 13.2';

  @override
  String get settingsSignOut => 'Выйти';

  @override
  String get settingsSignOutConfirmBody =>
      'Прогресс останется на сервере и вернётся при следующем входе.';

  @override
  String get settingsSignOutConfirmTitle => 'Выйти из аккаунта?';

  @override
  String get settingsSignOutHint => 'Вернёт к выбору способа входа';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsVersion => 'Версия';

  @override
  String get shopGroupLater => 'Пригодится, когда подрастёт';

  @override
  String get shopGroupNow => 'Малышу сейчас';

  @override
  String get shopNotEnoughCoins => 'Не хватает монет';

  @override
  String get furnishPickItem => 'Выбери вещь';

  @override
  String get furnishPickSlot => 'Теперь выбери место';

  @override
  String get furnishDone => 'Готово';

  @override
  String get furnishBuyMore => 'Купить ещё';

  @override
  String furnishPlaced(String name) {
    return '$name на месте';
  }

  @override
  String furnishRemoved(String name) {
    return '$name убрали';
  }

  @override
  String get furnishNoSlot => 'Для этой вещи здесь нет места';

  @override
  String get shopZoom => 'Рассмотреть';

  @override
  String get shopOwnedLabel => 'Куплено';

  @override
  String get shopTabClothes => 'Одежда';

  @override
  String get shopTabDecor => 'Декор';

  @override
  String get shopTabFurniture => 'Мебель';

  @override
  String get shopTabToys => 'Игрушки';

  @override
  String get shopTitle => 'Магазин';

  @override
  String get signInAlipay => 'Войти через Alipay';

  @override
  String get signInApple => 'Войти через Apple';

  @override
  String get signInGoogle => 'Войти через Google';

  @override
  String get signInLegal =>
      'Продолжая, вы принимаете условия использования и политику конфиденциальности';

  @override
  String get signInPrompt => 'Выберите способ входа';

  @override
  String get signInQq => 'Войти через QQ';

  @override
  String get signInSkip => 'Пропустить и посмотреть приложение';

  @override
  String signInSoonBody(String method) {
    return 'Вход через $method появится позже. Пока зарегистрируйтесь или войдите по почте.';
  }

  @override
  String get signInSoonTitle => 'Данная функция ещё в разработке';

  @override
  String get signInTagline => 'Плюшевый малыш, который растёт вместе с тобой';

  @override
  String get signInWeChat => 'Войти через WeChat';

  @override
  String get skinJoy => 'JOY';

  @override
  String get skinSlow => 'SLOW';

  @override
  String get stageAdult => 'Взрослый';

  @override
  String get stageCrawling => 'Ползающий малыш';

  @override
  String get stageFirstSteps => 'Первые шаги';

  @override
  String get stageGrowing => 'Подрастающий';

  @override
  String get stageNewborn => 'Новорождённый';

  @override
  String get statsFood => 'Еда';

  @override
  String get statsHygiene => 'Гигиена';

  @override
  String get statsLove => 'Любовь';

  @override
  String get statsShow => 'Показать уход';

  @override
  String get statsHide => 'Свернуть уход';

  @override
  String get statsPlay => 'Игра';

  @override
  String get statsSleep => 'Сон';

  @override
  String get traitActive => 'Активный';

  @override
  String get traitAffectionate => 'Ласковый';

  @override
  String get traitCalm => 'Спокойный';

  @override
  String get traitCurious => 'Любознательный';

  @override
  String get traitIndependent => 'Самостоятельный';

  @override
  String get traitReserved => 'Замкнутый';

  @override
  String get zodiacAquarius => 'Водолей';

  @override
  String get zodiacAries => 'Овен';

  @override
  String get zodiacCancer => 'Рак';

  @override
  String get zodiacCapricorn => 'Козерог';

  @override
  String get zodiacGemini => 'Близнецы';

  @override
  String get zodiacInfluenceAquarius =>
      'Выдумщик и вольнодум: удивляет и находит свои пути.';

  @override
  String get zodiacInfluenceAries =>
      'Смелый и порывистый: с первых дней норовит всё попробовать сам.';

  @override
  String get zodiacInfluenceCancer =>
      'Нежный домосед: расцветает от заботы и долгих объятий.';

  @override
  String get zodiacInfluenceCapricorn =>
      'Терпеливый и упорный: маленькими шагами добирается до большого.';

  @override
  String get zodiacInfluenceGemini =>
      'Любопытный и общительный: тянется ко всему новому обеими лапами.';

  @override
  String get zodiacInfluenceLeo =>
      'Тёплый и артистичный: обожает внимание и щедро отвечает лаской.';

  @override
  String get zodiacInfluenceLibra =>
      'Дружелюбный миротворец: ценит красоту, компанию и мягкий тон.';

  @override
  String get zodiacInfluencePisces =>
      'Мечтательный и чуткий: тонко чувствует твоё настроение.';

  @override
  String get zodiacInfluenceSagittarius =>
      'Весёлый искатель приключений: игры и прогулки — его стихия.';

  @override
  String get zodiacInfluenceScorpio =>
      'Глубокий и преданный: привязывается всерьёз и надолго.';

  @override
  String get zodiacInfluenceTaurus =>
      'Спокойный и основательный: любит уют, вкусную еду и свой распорядок.';

  @override
  String get zodiacInfluenceVirgo =>
      'Внимательный и аккуратный: замечает мелочи и любит порядок.';

  @override
  String get zodiacLeo => 'Лев';

  @override
  String get zodiacLibra => 'Весы';

  @override
  String get zodiacPisces => 'Рыбы';

  @override
  String get zodiacSagittarius => 'Стрелец';

  @override
  String get zodiacScorpio => 'Скорпион';

  @override
  String get zodiacTaurus => 'Телец';

  @override
  String get zodiacVirgo => 'Дева';

  @override
  String get shopGroupAll => 'Все';

  @override
  String get shopGroupBeds => 'Кроватки';

  @override
  String get shopGroupChairs => 'Кресла';

  @override
  String get shopGroupDressers => 'Комоды';

  @override
  String get shopGroupTables => 'Столики';

  @override
  String get shopGroupBaskets => 'Корзины для игрушек';

  @override
  String get shopGroupShelves => 'Настенные полки';

  @override
  String get shopGroupLamps => 'Светильники';

  @override
  String get shopGroupRugs => 'Ковры';

  @override
  String get shopGroupPictures => 'Картины';

  @override
  String get shopGroupPlants => 'Растения';

  @override
  String get shopGroupFlowers => 'Цветы';

  @override
  String get shopGroupPillows => 'Подушки';

  @override
  String get shopGroupWalls => 'Обои';

  @override
  String get shopGroupFloors => 'Полы';

  @override
  String get shopGroupPlush => 'Мягкие игрушки';

  @override
  String get shopGroupHouses => 'Домики';

  @override
  String get shopGroupToys => 'Игрушки';

  @override
  String get shopGroupOutfits => 'Комплекты';

  @override
  String get shopGroupTops => 'Верх';

  @override
  String get shopGroupBottoms => 'Низ';

  @override
  String get shopGroupHats => 'Головные уборы';

  @override
  String get shopGroupShoes => 'Обувь';

  @override
  String get shopGroupExtras => 'Аксессуары';

  @override
  String get shopGroupSeats => 'Стулья';

  @override
  String get shopGroupWardrobes => 'Шкафы';

  @override
  String get shopGroupClocks => 'Часы';

  @override
  String get shopGroupGarlands => 'Гирлянды';

  @override
  String wakeAlarmLabel(String name) {
    return 'Проснёмся вместе с $name';
  }

  @override
  String wakeAlarmBody(String name) {
    return '$name уже не спит и ждёт тебя';
  }

  @override
  String get wakeAlarmStop => 'Проснулись';

  @override
  String wakeAlarmClock(String time) {
    return 'Будильник на $time стоит в «Часах» телефона';
  }

  @override
  String wakeAlarmClockOld(String time) {
    return 'Прежний, на $time, остался в «Часах» — выключите его там';
  }

  @override
  String get wakeAlarmOpenClock => 'Открыть часы';

  @override
  String wakeAlarmSystem(String time) {
    return 'Будильник на $time поставлен. Зазвонит и в беззвучном режиме';
  }

  @override
  String wakeAlarmNotification(String time) {
    return 'Разбудим в $time уведомлением со звуком. В беззвучном режиме будет только вибрация';
  }

  @override
  String wakeAlarmPreview(String time) {
    return 'На телефоне будильник на $time встанет в «Часы» Android или зазвонит как системный на iPhone. В этой версии для просмотра он не звонит';
  }

  @override
  String get wakeAlarmDenied =>
      'Без разрешения будильник не поставить. Включите уведомления для Teddy Tales в настройках телефона';

  @override
  String get wakeAlarmFailed =>
      'Будильник поставить не удалось. Попробуйте ещё раз';

  @override
  String get signInEmail => 'Регистрация по почте';

  @override
  String get emailTitle => 'Почта';

  @override
  String get emailTabSignUp => 'Регистрация';

  @override
  String get emailTabSignIn => 'Вход';

  @override
  String get emailField => 'Электронная почта';

  @override
  String get emailPassword => 'Пароль';

  @override
  String emailPasswordHint(int min) {
    return 'Не короче $min знаков';
  }

  @override
  String get emailSubmitSignUp => 'Зарегистрироваться';

  @override
  String get emailSubmitSignIn => 'Войти';

  @override
  String get emailLeadSignUp =>
      'Малыш появится на свет в день регистрации — от этого дня считаются его возраст и знак зодиака.';

  @override
  String get emailLeadSignIn =>
      'Войдите — мишка, кошелёк и покупки вернутся на любом телефоне.';

  @override
  String get emailErrorInvalid => 'Проверьте адрес почты';

  @override
  String emailErrorPassword(int min) {
    return 'Пароль не короче $min знаков';
  }

  @override
  String get emailErrorExists => 'Эта почта уже зарегистрирована — войдите';

  @override
  String get emailErrorCredentials => 'Неверная почта или пароль';

  @override
  String get emailErrorNotConfirmed =>
      'Почта не подтверждена — введите код из письма';

  @override
  String get emailErrorDisabled => 'Регистрация по почте пока выключена';

  @override
  String get emailErrorRateLimit =>
      'Слишком много писем подряд — попробуйте позже';

  @override
  String get emailErrorNetwork => 'Нет связи с сервером — попробуйте ещё раз';

  @override
  String get emailErrorUnknown => 'Не получилось — попробуйте ещё раз';

  @override
  String get profileBirthdayLabel => 'День рождения';

  @override
  String get profileSectionAccount => 'Личный кабинет';

  @override
  String get profileAccountLogin => 'Вход';

  @override
  String get profileAccountGuest => 'Без регистрации';

  @override
  String profileAccountUnconfirmed(String email) {
    return '$email · не подтверждена';
  }

  @override
  String get profileAccountRegistered => 'Зарегистрирован';

  @override
  String get profileAccountWallet => 'Кошелёк';

  @override
  String get emailCodeTitle => 'Введите код из письма';

  @override
  String emailCodeBody(String email, int length) {
    return 'Мы отправили код из $length цифр на $email. Если письма нет, загляните в «Спам».';
  }

  @override
  String get emailCodeField => 'Код';

  @override
  String get emailCodeSubmit => 'Подтвердить';

  @override
  String get emailCodeResend => 'Отправить код ещё раз';

  @override
  String emailCodeResendIn(int seconds) {
    return 'Отправить ещё раз через $seconds с';
  }

  @override
  String get emailCodeSent => 'Новый код отправлен';

  @override
  String get emailCodeChangeEmail => 'Изменить почту';

  @override
  String get emailEnterCode => 'Ввести код из письма';

  @override
  String get emailErrorCode => 'Код неверный или устарел — запросите новый';

  @override
  String get buyConfirmTitle => 'Подтвердите покупку';

  @override
  String buyConfirmBalance(int coins, int left) {
    return 'На счету $coins · останется $left';
  }

  @override
  String get buyConfirmAction => 'Купить';

  @override
  String get buyConfirmCancel => 'Отмена';

  @override
  String get buyNotEnoughTitle => 'Не хватает монет';

  @override
  String buyNotEnough(int missing) {
    String _temp0 = intl.Intl.pluralLogic(
      missing,
      locale: localeName,
      other: 'Не хватает $missing монет',
      one: 'Не хватает $missing монеты',
    );
    return '$_temp0';
  }

  @override
  String get buyNotEnoughOk => 'Понятно';
}

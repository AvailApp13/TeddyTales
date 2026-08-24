import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('zh'),
  ];

  /// No description provided for @ageDays.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} день} few{{count} дня} other{{count} дней}}'**
  String ageDays(int count);

  /// No description provided for @ageMonths.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} месяц} few{{count} месяца} other{{count} месяцев}}'**
  String ageMonths(int count);

  /// No description provided for @ageMonthsDays.
  ///
  /// In ru, this message translates to:
  /// **'{months, plural, one{{months} месяц} few{{months} месяца} other{{months} месяцев}} {days, plural, one{{days} день} few{{days} дня} other{{days} дней}}'**
  String ageMonthsDays(int months, int days);

  /// No description provided for @ageYears.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} год} few{{count} года} other{{count} лет}}'**
  String ageYears(int count);

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'TeddyTales'**
  String get appTitle;

  /// No description provided for @bearRigMissingHint.
  ///
  /// In ru, this message translates to:
  /// **'Положите {path}'**
  String bearRigMissingHint(String path);

  /// No description provided for @bearRigMissingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Риг ещё не подключён'**
  String get bearRigMissingTitle;

  /// No description provided for @birthCueAwakening.
  ///
  /// In ru, this message translates to:
  /// **'Малыш открывает глаза и осматривается.'**
  String get birthCueAwakening;

  /// No description provided for @birthCueCradle.
  ///
  /// In ru, this message translates to:
  /// **'Тёплая кроватка. Кто-то тихо дышит под одеялом…'**
  String get birthCueCradle;

  /// No description provided for @birthCueFinale.
  ///
  /// In ru, this message translates to:
  /// **'Он успокоился. Здравствуй, малыш.'**
  String get birthCueFinale;

  /// No description provided for @birthCueFirstBreath.
  ///
  /// In ru, this message translates to:
  /// **'Первый вдох…'**
  String get birthCueFirstBreath;

  /// No description provided for @birthCueFirstCry.
  ///
  /// In ru, this message translates to:
  /// **'Первый плач — он зовёт тебя.'**
  String get birthCueFirstCry;

  /// No description provided for @birthCueStars.
  ///
  /// In ru, this message translates to:
  /// **'Звёздочки кружатся в мягком свете.'**
  String get birthCueStars;

  /// No description provided for @birthSceneNotReady.
  ///
  /// In ru, this message translates to:
  /// **'Сцена рождения ещё не собрана'**
  String get birthSceneNotReady;

  /// No description provided for @birthSkip.
  ///
  /// In ru, this message translates to:
  /// **'Пропустить'**
  String get birthSkip;

  /// No description provided for @careFeedSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Вкусная еда для малыша'**
  String get careFeedSubtitle;

  /// No description provided for @careFeedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Покормить'**
  String get careFeedTitle;

  /// No description provided for @careFootnote.
  ///
  /// In ru, this message translates to:
  /// **'Поглаживания в списке нет: по разделу 8.1 ТЗ это касание экрана — тапните по мишке на главной.'**
  String get careFootnote;

  /// No description provided for @careLockedUntilStage.
  ///
  /// In ru, this message translates to:
  /// **'Откроется на стадии {stage}'**
  String careLockedUntilStage(int stage);

  /// No description provided for @carePlaySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Весёлые игры вместе'**
  String get carePlaySubtitle;

  /// No description provided for @carePlayTitle.
  ///
  /// In ru, this message translates to:
  /// **'Играть'**
  String get carePlayTitle;

  /// No description provided for @careSleepSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Спокойной ночи, малыш'**
  String get careSleepSubtitle;

  /// No description provided for @careSleepTitle.
  ///
  /// In ru, this message translates to:
  /// **'Уложить спать'**
  String get careSleepTitle;

  /// No description provided for @careTitle.
  ///
  /// In ru, this message translates to:
  /// **'Что будем делать?'**
  String get careTitle;

  /// No description provided for @careWashSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Пора в ванну!'**
  String get careWashSubtitle;

  /// No description provided for @careWashTitle.
  ///
  /// In ru, this message translates to:
  /// **'Купать'**
  String get careWashTitle;

  /// No description provided for @catalogCheckoutTitle.
  ///
  /// In ru, this message translates to:
  /// **'Оформление'**
  String get catalogCheckoutTitle;

  /// No description provided for @catalogCountryChina.
  ///
  /// In ru, this message translates to:
  /// **'Китай'**
  String get catalogCountryChina;

  /// No description provided for @catalogCountryGermany.
  ///
  /// In ru, this message translates to:
  /// **'Германия'**
  String get catalogCountryGermany;

  /// No description provided for @catalogCountryKazakhstan.
  ///
  /// In ru, this message translates to:
  /// **'Казахстан'**
  String get catalogCountryKazakhstan;

  /// No description provided for @catalogCountryRussia.
  ///
  /// In ru, this message translates to:
  /// **'Россия'**
  String get catalogCountryRussia;

  /// No description provided for @catalogCountryUsa.
  ///
  /// In ru, this message translates to:
  /// **'США'**
  String get catalogCountryUsa;

  /// No description provided for @catalogDeliveryNote.
  ///
  /// In ru, this message translates to:
  /// **'Доставка по данным магазина: США 7–9 рабочих дней, Канада 8–10, Европа 9–11, Азия 5–7. Заказ уходит в действующую систему продаж Заказчика (КП 12.5) — здесь форма без отправки.'**
  String get catalogDeliveryNote;

  /// No description provided for @catalogFieldAddress.
  ///
  /// In ru, this message translates to:
  /// **'Адрес'**
  String get catalogFieldAddress;

  /// No description provided for @catalogFieldAddressHint.
  ///
  /// In ru, this message translates to:
  /// **'Улица, дом, квартира'**
  String get catalogFieldAddressHint;

  /// No description provided for @catalogFieldCountry.
  ///
  /// In ru, this message translates to:
  /// **'Страна'**
  String get catalogFieldCountry;

  /// No description provided for @catalogFieldName.
  ///
  /// In ru, this message translates to:
  /// **'Имя и фамилия'**
  String get catalogFieldName;

  /// No description provided for @catalogFieldNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Как в документах'**
  String get catalogFieldNameHint;

  /// No description provided for @catalogFieldPhone.
  ///
  /// In ru, this message translates to:
  /// **'Телефон'**
  String get catalogFieldPhone;

  /// No description provided for @catalogFieldPostcode.
  ///
  /// In ru, this message translates to:
  /// **'Индекс'**
  String get catalogFieldPostcode;

  /// No description provided for @catalogFootnote.
  ///
  /// In ru, this message translates to:
  /// **'Товары, цены и размеры — из официального магазина TeddyTales®, как требует КП 12.1. Фотографии подставлены одинаковые: настоящие снимки берутся из каталога Заказчика. Обувь там продаётся отдельно — {shoes}, {price}.'**
  String catalogFootnote(String shoes, String price);

  /// No description provided for @catalogGrownSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'и готов отправиться к тебе домой'**
  String get catalogGrownSubtitle;

  /// No description provided for @catalogGrownTitle.
  ///
  /// In ru, this message translates to:
  /// **'Твой малыш вырос'**
  String get catalogGrownTitle;

  /// No description provided for @catalogItemFortune.
  ///
  /// In ru, this message translates to:
  /// **'Карманный мишка Фортуна'**
  String get catalogItemFortune;

  /// No description provided for @catalogItemHug.
  ///
  /// In ru, this message translates to:
  /// **'Персиковый Обнимишка'**
  String get catalogItemHug;

  /// No description provided for @catalogItemShortFur.
  ///
  /// In ru, this message translates to:
  /// **'Мишка с короткой шерсткой'**
  String get catalogItemShortFur;

  /// No description provided for @catalogItemSpaceSet.
  ///
  /// In ru, this message translates to:
  /// **'Набор Космонавт и Невеста'**
  String get catalogItemSpaceSet;

  /// No description provided for @catalogOrderButton.
  ///
  /// In ru, this message translates to:
  /// **'Оформить заказ'**
  String get catalogOrderButton;

  /// No description provided for @catalogPayPalNote.
  ///
  /// In ru, this message translates to:
  /// **' — и картой без аккаунта'**
  String get catalogPayPalNote;

  /// No description provided for @catalogPaySection.
  ///
  /// In ru, this message translates to:
  /// **'Оплата · КП 12.4'**
  String get catalogPaySection;

  /// No description provided for @catalogPayStub.
  ///
  /// In ru, this message translates to:
  /// **'Оплата подключается на этапе интеграции'**
  String get catalogPayStub;

  /// No description provided for @catalogSizeCm.
  ///
  /// In ru, this message translates to:
  /// **'{size} см'**
  String catalogSizeCm(int size);

  /// No description provided for @catalogSummaryItem.
  ///
  /// In ru, this message translates to:
  /// **'Товар'**
  String get catalogSummaryItem;

  /// No description provided for @catalogSummaryPrice.
  ///
  /// In ru, this message translates to:
  /// **'Цена'**
  String get catalogSummaryPrice;

  /// No description provided for @catalogSummarySize.
  ///
  /// In ru, this message translates to:
  /// **'Размер'**
  String get catalogSummarySize;

  /// No description provided for @catalogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Заказать мишку'**
  String get catalogTitle;

  /// No description provided for @categoryAccessory.
  ///
  /// In ru, this message translates to:
  /// **'Аксессуары'**
  String get categoryAccessory;

  /// No description provided for @categoryBottom.
  ///
  /// In ru, this message translates to:
  /// **'Низ'**
  String get categoryBottom;

  /// No description provided for @categoryDecor.
  ///
  /// In ru, this message translates to:
  /// **'Декор'**
  String get categoryDecor;

  /// No description provided for @categoryFloor.
  ///
  /// In ru, this message translates to:
  /// **'Пол'**
  String get categoryFloor;

  /// No description provided for @categoryFurniture.
  ///
  /// In ru, this message translates to:
  /// **'Мебель'**
  String get categoryFurniture;

  /// No description provided for @categoryHeadwear.
  ///
  /// In ru, this message translates to:
  /// **'Головные уборы'**
  String get categoryHeadwear;

  /// No description provided for @categoryOutfit.
  ///
  /// In ru, this message translates to:
  /// **'Наряды'**
  String get categoryOutfit;

  /// No description provided for @categoryShoes.
  ///
  /// In ru, this message translates to:
  /// **'Обувь'**
  String get categoryShoes;

  /// No description provided for @categoryTop.
  ///
  /// In ru, this message translates to:
  /// **'Верх'**
  String get categoryTop;

  /// No description provided for @categoryToy.
  ///
  /// In ru, this message translates to:
  /// **'Игрушки'**
  String get categoryToy;

  /// No description provided for @categoryWallpaper.
  ///
  /// In ru, this message translates to:
  /// **'Обои'**
  String get categoryWallpaper;

  /// No description provided for @commonBack.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get commonBack;

  /// No description provided for @commonCoins.
  ///
  /// In ru, this message translates to:
  /// **'{count} монет'**
  String commonCoins(int count);

  /// No description provided for @diaryEventFavoriteToy.
  ///
  /// In ru, this message translates to:
  /// **'Любимая игрушка'**
  String get diaryEventFavoriteToy;

  /// No description provided for @diaryEventFirstBath.
  ///
  /// In ru, this message translates to:
  /// **'Первое купание'**
  String get diaryEventFirstBath;

  /// No description provided for @diaryEventFirstCrawl.
  ///
  /// In ru, this message translates to:
  /// **'Научился ползать'**
  String get diaryEventFirstCrawl;

  /// No description provided for @diaryEventFirstTooth.
  ///
  /// In ru, this message translates to:
  /// **'Первый зубик'**
  String get diaryEventFirstTooth;

  /// No description provided for @diaryFootnote.
  ///
  /// In ru, this message translates to:
  /// **'Дневника нет в КП — он с макета. Отнесён ко второй версии, собран как заготовка. Фотоальбом и «Поделиться» потребуют камеры и прав на съёмку. Миниатюра события — заглушка: настоящие снимки появятся вместе с фотоальбомом.'**
  String get diaryFootnote;

  /// No description provided for @diaryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Дневник'**
  String get diaryTitle;

  /// No description provided for @dishCookie.
  ///
  /// In ru, this message translates to:
  /// **'Печенье'**
  String get dishCookie;

  /// No description provided for @dishFruit.
  ///
  /// In ru, this message translates to:
  /// **'Фрукты'**
  String get dishFruit;

  /// No description provided for @dishOmelette.
  ///
  /// In ru, this message translates to:
  /// **'Омлет'**
  String get dishOmelette;

  /// No description provided for @dishPasta.
  ///
  /// In ru, this message translates to:
  /// **'Паста'**
  String get dishPasta;

  /// No description provided for @dishPie.
  ///
  /// In ru, this message translates to:
  /// **'Пирог'**
  String get dishPie;

  /// No description provided for @dishPorridge.
  ///
  /// In ru, this message translates to:
  /// **'Каша'**
  String get dishPorridge;

  /// No description provided for @dishSalad.
  ///
  /// In ru, this message translates to:
  /// **'Салат'**
  String get dishSalad;

  /// No description provided for @dishSandwich.
  ///
  /// In ru, this message translates to:
  /// **'Сэндвич'**
  String get dishSandwich;

  /// No description provided for @dishSoup.
  ///
  /// In ru, this message translates to:
  /// **'Суп'**
  String get dishSoup;

  /// No description provided for @dishYogurt.
  ///
  /// In ru, this message translates to:
  /// **'Йогурт'**
  String get dishYogurt;

  /// No description provided for @feedCookHint.
  ///
  /// In ru, this message translates to:
  /// **'Добавляй продукты по порядку. Ошибёшься — просто попробуем ещё раз.'**
  String get feedCookHint;

  /// No description provided for @feedCookResult.
  ///
  /// In ru, this message translates to:
  /// **'Готово! {recipe} · +{reward, plural, one{{reward} монета} few{{reward} монеты} other{{reward} монет}}, еда +{gain}'**
  String feedCookResult(String recipe, int reward, int gain);

  /// No description provided for @feedDishesNote.
  ///
  /// In ru, this message translates to:
  /// **'Ровно 10 блюд по КП 8.2. Цены и прибавки — плейсхолдеры, по КП 10.9 они утверждаются отдельно и настраиваются с сервера.'**
  String get feedDishesNote;

  /// No description provided for @feedEatResult.
  ///
  /// In ru, this message translates to:
  /// **'{dish} · еда +{gain}, −{price, plural, one{{price} монета} few{{price} монеты} other{{price} монет}}'**
  String feedEatResult(String dish, int gain, int price);

  /// No description provided for @feedFavourite.
  ///
  /// In ru, this message translates to:
  /// **'Любимое'**
  String get feedFavourite;

  /// No description provided for @feedFoodGain.
  ///
  /// In ru, this message translates to:
  /// **'еда +{gain}'**
  String feedFoodGain(int gain);

  /// No description provided for @feedHintActive.
  ///
  /// In ru, this message translates to:
  /// **'Я сегодня носился как заводной — давай посытнее!'**
  String get feedHintActive;

  /// No description provided for @feedHintAffectionate.
  ///
  /// In ru, this message translates to:
  /// **'Хочу что-нибудь сладкое… и чтобы ты рядом.'**
  String get feedHintAffectionate;

  /// No description provided for @feedHintCalm.
  ///
  /// In ru, this message translates to:
  /// **'Мне бы чего-то тёплого и простого.'**
  String get feedHintCalm;

  /// No description provided for @feedHintCurious.
  ///
  /// In ru, this message translates to:
  /// **'А приготовим что-нибудь новенькое?'**
  String get feedHintCurious;

  /// No description provided for @feedHintIndependent.
  ///
  /// In ru, this message translates to:
  /// **'Я бы и сам справился. Ну, почти.'**
  String get feedHintIndependent;

  /// No description provided for @feedHintReserved.
  ///
  /// In ru, this message translates to:
  /// **'Можно просто фрукты?'**
  String get feedHintReserved;

  /// No description provided for @feedNotEnoughCoins.
  ///
  /// In ru, this message translates to:
  /// **'Не хватает монет'**
  String get feedNotEnoughCoins;

  /// No description provided for @feedRecipeSteps.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} шаг} few{{count} шага} other{{count} шагов}}'**
  String feedRecipeSteps(int count);

  /// No description provided for @feedRecipesNote.
  ///
  /// In ru, this message translates to:
  /// **'Ровно 5 рецептов по КП 8.5: печенье и сэндвич — по 3 шага, остальные — от 4 до 6.'**
  String get feedRecipesNote;

  /// No description provided for @feedStepProgress.
  ///
  /// In ru, this message translates to:
  /// **'Шаг {step} из {total}. Награда: {reward, plural, one{{reward} монета} few{{reward} монеты} other{{reward} монет}} и еда +{gain}.'**
  String feedStepProgress(int step, int total, int reward, int gain);

  /// No description provided for @feedTabCook.
  ///
  /// In ru, this message translates to:
  /// **'Приготовить'**
  String get feedTabCook;

  /// No description provided for @feedTabReady.
  ///
  /// In ru, this message translates to:
  /// **'Готовые блюда'**
  String get feedTabReady;

  /// No description provided for @feedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Чем покормим?'**
  String get feedTitle;

  /// No description provided for @feedWrongStep.
  ///
  /// In ru, this message translates to:
  /// **'Не то. Сейчас нужно: {ingredient}. Попробуй ещё раз — штрафа нет.'**
  String feedWrongStep(String ingredient);

  /// No description provided for @game2048Hint.
  ///
  /// In ru, this message translates to:
  /// **'Свайпайте: равные плитки сливаются. Цель — {target}. Счёт: {score}'**
  String game2048Hint(int target, int score);

  /// No description provided for @game2048StuckHint.
  ///
  /// In ru, this message translates to:
  /// **'Ходов не осталось — начните заново кнопкой ниже.'**
  String get game2048StuckHint;

  /// No description provided for @game2048Title.
  ///
  /// In ru, this message translates to:
  /// **'2048 · уровень {level}'**
  String game2048Title(int level);

  /// No description provided for @game2048WonHint.
  ///
  /// In ru, this message translates to:
  /// **'Есть {target}! Забирайте награду 🎉'**
  String game2048WonHint(int target);

  /// No description provided for @gamePairsHint.
  ///
  /// In ru, this message translates to:
  /// **'Откройте две одинаковые карточки. Ходы: {moves}'**
  String gamePairsHint(int moves);

  /// No description provided for @gamePairsSolvedHint.
  ///
  /// In ru, this message translates to:
  /// **'{moves, plural, one{Все пары найдены за {moves} ход 🎉} few{Все пары найдены за {moves} хода 🎉} other{Все пары найдены за {moves} ходов 🎉}}'**
  String gamePairsSolvedHint(int moves);

  /// No description provided for @gamePairsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Память · уровень {level}'**
  String gamePairsTitle(int level);

  /// No description provided for @gamePuzzleHint.
  ///
  /// In ru, this message translates to:
  /// **'Двигайте плитки тапом — соберите фото.'**
  String get gamePuzzleHint;

  /// No description provided for @gamePuzzleSolvedHint.
  ///
  /// In ru, this message translates to:
  /// **'Собрано! Забирайте награду 🎉'**
  String get gamePuzzleSolvedHint;

  /// No description provided for @gamePuzzleTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пазл · уровень {level}'**
  String gamePuzzleTitle(int level);

  /// No description provided for @gameRestart.
  ///
  /// In ru, this message translates to:
  /// **'Заново'**
  String get gameRestart;

  /// No description provided for @growthAlreadyAdult.
  ///
  /// In ru, this message translates to:
  /// **'Мишка уже взрослый'**
  String get growthAlreadyAdult;

  /// No description provided for @growthDurationAdult.
  ///
  /// In ru, this message translates to:
  /// **'дальше без ограничений'**
  String get growthDurationAdult;

  /// No description provided for @growthDurationCrawling.
  ///
  /// In ru, this message translates to:
  /// **'~2 дня'**
  String get growthDurationCrawling;

  /// No description provided for @growthDurationFirstSteps.
  ///
  /// In ru, this message translates to:
  /// **'1–2 дня'**
  String get growthDurationFirstSteps;

  /// No description provided for @growthDurationGrowing.
  ///
  /// In ru, this message translates to:
  /// **'до ~14 дня'**
  String get growthDurationGrowing;

  /// No description provided for @growthDurationNewborn.
  ///
  /// In ru, this message translates to:
  /// **'1 день'**
  String get growthDurationNewborn;

  /// No description provided for @growthFootnote.
  ///
  /// In ru, this message translates to:
  /// **'Названия и длительности — из КП 5. На макете они другие (Малыш, Детёныш, месяцы вместо дней) — это расхождение висит открытым вопросом.'**
  String get growthFootnote;

  /// No description provided for @growthGrowUp.
  ///
  /// In ru, this message translates to:
  /// **'Повзрослеть'**
  String get growthGrowUp;

  /// No description provided for @growthMarkNow.
  ///
  /// In ru, this message translates to:
  /// **'сейчас'**
  String get growthMarkNow;

  /// No description provided for @growthMarkPassed.
  ///
  /// In ru, this message translates to:
  /// **'пройдено'**
  String get growthMarkPassed;

  /// No description provided for @growthNewStage.
  ///
  /// In ru, this message translates to:
  /// **'Новая стадия: {stage}'**
  String growthNewStage(String stage);

  /// No description provided for @growthTitle.
  ///
  /// In ru, this message translates to:
  /// **'Рост и развитие'**
  String get growthTitle;

  /// No description provided for @homeCareButton.
  ///
  /// In ru, this message translates to:
  /// **'Что будем делать?'**
  String get homeCareButton;

  /// No description provided for @homeDevPanelTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Дев-панель рига'**
  String get homeDevPanelTooltip;

  /// No description provided for @homeScreenNotReady.
  ///
  /// In ru, this message translates to:
  /// **'Экран для «{name}» ещё не собран'**
  String homeScreenNotReady(String name);

  /// No description provided for @ingredientApple.
  ///
  /// In ru, this message translates to:
  /// **'Яблоко'**
  String get ingredientApple;

  /// No description provided for @ingredientBanana.
  ///
  /// In ru, this message translates to:
  /// **'Банан'**
  String get ingredientBanana;

  /// No description provided for @ingredientBread.
  ///
  /// In ru, this message translates to:
  /// **'Хлеб'**
  String get ingredientBread;

  /// No description provided for @ingredientButter.
  ///
  /// In ru, this message translates to:
  /// **'Масло'**
  String get ingredientButter;

  /// No description provided for @ingredientCabbage.
  ///
  /// In ru, this message translates to:
  /// **'Капуста'**
  String get ingredientCabbage;

  /// No description provided for @ingredientCandy.
  ///
  /// In ru, this message translates to:
  /// **'Конфета'**
  String get ingredientCandy;

  /// No description provided for @ingredientCarrot.
  ///
  /// In ru, this message translates to:
  /// **'Морковь'**
  String get ingredientCarrot;

  /// No description provided for @ingredientCheese.
  ///
  /// In ru, this message translates to:
  /// **'Сыр'**
  String get ingredientCheese;

  /// No description provided for @ingredientChocolate.
  ///
  /// In ru, this message translates to:
  /// **'Шоколад'**
  String get ingredientChocolate;

  /// No description provided for @ingredientFish.
  ///
  /// In ru, this message translates to:
  /// **'Рыба'**
  String get ingredientFish;

  /// No description provided for @ingredientFlour.
  ///
  /// In ru, this message translates to:
  /// **'Мука'**
  String get ingredientFlour;

  /// No description provided for @ingredientGreens.
  ///
  /// In ru, this message translates to:
  /// **'Зелень'**
  String get ingredientGreens;

  /// No description provided for @ingredientHoney.
  ///
  /// In ru, this message translates to:
  /// **'Мёд'**
  String get ingredientHoney;

  /// No description provided for @ingredientMeat.
  ///
  /// In ru, this message translates to:
  /// **'Мясо'**
  String get ingredientMeat;

  /// No description provided for @ingredientOnion.
  ///
  /// In ru, this message translates to:
  /// **'Лук'**
  String get ingredientOnion;

  /// No description provided for @ingredientOrange.
  ///
  /// In ru, this message translates to:
  /// **'Апельсин'**
  String get ingredientOrange;

  /// No description provided for @ingredientPepper.
  ///
  /// In ru, this message translates to:
  /// **'Перец'**
  String get ingredientPepper;

  /// No description provided for @ingredientPotato.
  ///
  /// In ru, this message translates to:
  /// **'Картофель'**
  String get ingredientPotato;

  /// No description provided for @ingredientSalt.
  ///
  /// In ru, this message translates to:
  /// **'Соль'**
  String get ingredientSalt;

  /// No description provided for @ingredientSpices.
  ///
  /// In ru, this message translates to:
  /// **'Специи'**
  String get ingredientSpices;

  /// No description provided for @ingredientSugar.
  ///
  /// In ru, this message translates to:
  /// **'Сахар'**
  String get ingredientSugar;

  /// No description provided for @ingredientTomato.
  ///
  /// In ru, this message translates to:
  /// **'Помидор'**
  String get ingredientTomato;

  /// No description provided for @ingredientYogurt.
  ///
  /// In ru, this message translates to:
  /// **'Йогурт'**
  String get ingredientYogurt;

  /// No description provided for @itemAccBow.
  ///
  /// In ru, this message translates to:
  /// **'Бантик'**
  String get itemAccBow;

  /// No description provided for @itemArmchair.
  ///
  /// In ru, this message translates to:
  /// **'Кресло'**
  String get itemArmchair;

  /// No description provided for @itemBall.
  ///
  /// In ru, this message translates to:
  /// **'Мячик'**
  String get itemBall;

  /// No description provided for @itemBasket.
  ///
  /// In ru, this message translates to:
  /// **'Корзина'**
  String get itemBasket;

  /// No description provided for @itemBed.
  ///
  /// In ru, this message translates to:
  /// **'Кроватка'**
  String get itemBed;

  /// No description provided for @itemBotBlue.
  ///
  /// In ru, this message translates to:
  /// **'Штаны синие'**
  String get itemBotBlue;

  /// No description provided for @itemBotSkirt.
  ///
  /// In ru, this message translates to:
  /// **'Юбка розовая'**
  String get itemBotSkirt;

  /// No description provided for @itemBotYellow.
  ///
  /// In ru, this message translates to:
  /// **'Шорты жёлтые'**
  String get itemBotYellow;

  /// No description provided for @itemCactus.
  ///
  /// In ru, this message translates to:
  /// **'Кактус'**
  String get itemCactus;

  /// No description provided for @itemCar.
  ///
  /// In ru, this message translates to:
  /// **'Машинка'**
  String get itemCar;

  /// No description provided for @itemChair.
  ///
  /// In ru, this message translates to:
  /// **'Стул'**
  String get itemChair;

  /// No description provided for @itemClock.
  ///
  /// In ru, this message translates to:
  /// **'Часы'**
  String get itemClock;

  /// No description provided for @itemCubes.
  ///
  /// In ru, this message translates to:
  /// **'Кубики'**
  String get itemCubes;

  /// No description provided for @itemDresser.
  ///
  /// In ru, this message translates to:
  /// **'Комод'**
  String get itemDresser;

  /// No description provided for @itemDrum.
  ///
  /// In ru, this message translates to:
  /// **'Барабан'**
  String get itemDrum;

  /// No description provided for @itemDuck.
  ///
  /// In ru, this message translates to:
  /// **'Уточка'**
  String get itemDuck;

  /// No description provided for @itemFloorCarpet.
  ///
  /// In ru, this message translates to:
  /// **'Пол ковролин'**
  String get itemFloorCarpet;

  /// No description provided for @itemFloorLight.
  ///
  /// In ru, this message translates to:
  /// **'Пол светлый'**
  String get itemFloorLight;

  /// No description provided for @itemFloorWood.
  ///
  /// In ru, this message translates to:
  /// **'Пол дерево'**
  String get itemFloorWood;

  /// No description provided for @itemGarland.
  ///
  /// In ru, this message translates to:
  /// **'Гирлянда'**
  String get itemGarland;

  /// No description provided for @itemHatCap.
  ///
  /// In ru, this message translates to:
  /// **'Шапка'**
  String get itemHatCap;

  /// No description provided for @itemKite.
  ///
  /// In ru, this message translates to:
  /// **'Воздушный змей'**
  String get itemKite;

  /// No description provided for @itemLamp.
  ///
  /// In ru, this message translates to:
  /// **'Светильник'**
  String get itemLamp;

  /// No description provided for @itemOutBear.
  ///
  /// In ru, this message translates to:
  /// **'Костюм мишки'**
  String get itemOutBear;

  /// No description provided for @itemOutBee.
  ///
  /// In ru, this message translates to:
  /// **'Костюм пчёлка'**
  String get itemOutBee;

  /// No description provided for @itemOutBerry.
  ///
  /// In ru, this message translates to:
  /// **'Костюм клубника'**
  String get itemOutBerry;

  /// No description provided for @itemOutGlasses.
  ///
  /// In ru, this message translates to:
  /// **'Комплект очкарик'**
  String get itemOutGlasses;

  /// No description provided for @itemOutSailor.
  ///
  /// In ru, this message translates to:
  /// **'Комплект матрос'**
  String get itemOutSailor;

  /// No description provided for @itemOutSport.
  ///
  /// In ru, this message translates to:
  /// **'Комплект спорт'**
  String get itemOutSport;

  /// No description provided for @itemOutWinter.
  ///
  /// In ru, this message translates to:
  /// **'Комплект зимний'**
  String get itemOutWinter;

  /// No description provided for @itemOutYellow.
  ///
  /// In ru, this message translates to:
  /// **'Комплект жёлтый'**
  String get itemOutYellow;

  /// No description provided for @itemPicBear.
  ///
  /// In ru, this message translates to:
  /// **'Картина мишка'**
  String get itemPicBear;

  /// No description provided for @itemPicForest.
  ///
  /// In ru, this message translates to:
  /// **'Картина лес'**
  String get itemPicForest;

  /// No description provided for @itemPicMoon.
  ///
  /// In ru, this message translates to:
  /// **'Картина луна'**
  String get itemPicMoon;

  /// No description provided for @itemPillowHeart.
  ///
  /// In ru, this message translates to:
  /// **'Подушка сердце'**
  String get itemPillowHeart;

  /// No description provided for @itemPillowStar.
  ///
  /// In ru, this message translates to:
  /// **'Подушка звезда'**
  String get itemPillowStar;

  /// No description provided for @itemPlant.
  ///
  /// In ru, this message translates to:
  /// **'Растение'**
  String get itemPlant;

  /// No description provided for @itemPoster.
  ///
  /// In ru, this message translates to:
  /// **'Постер'**
  String get itemPoster;

  /// No description provided for @itemPuzzle.
  ///
  /// In ru, this message translates to:
  /// **'Пазл'**
  String get itemPuzzle;

  /// No description provided for @itemRocket.
  ///
  /// In ru, this message translates to:
  /// **'Ракета'**
  String get itemRocket;

  /// No description provided for @itemRug.
  ///
  /// In ru, this message translates to:
  /// **'Ковёр'**
  String get itemRug;

  /// No description provided for @itemShelf.
  ///
  /// In ru, this message translates to:
  /// **'Книжная полка'**
  String get itemShelf;

  /// No description provided for @itemTable.
  ///
  /// In ru, this message translates to:
  /// **'Стол'**
  String get itemTable;

  /// No description provided for @itemTeddy.
  ///
  /// In ru, this message translates to:
  /// **'Мишка'**
  String get itemTeddy;

  /// No description provided for @itemTopBlue.
  ///
  /// In ru, this message translates to:
  /// **'Толстовка голубая'**
  String get itemTopBlue;

  /// No description provided for @itemTopRose.
  ///
  /// In ru, this message translates to:
  /// **'Свитер розовый'**
  String get itemTopRose;

  /// No description provided for @itemTopSage.
  ///
  /// In ru, this message translates to:
  /// **'Кофта зелёная'**
  String get itemTopSage;

  /// No description provided for @itemTrain.
  ///
  /// In ru, this message translates to:
  /// **'Паровозик'**
  String get itemTrain;

  /// No description provided for @itemWallRose.
  ///
  /// In ru, this message translates to:
  /// **'Обои розовые'**
  String get itemWallRose;

  /// No description provided for @itemWallSage.
  ///
  /// In ru, this message translates to:
  /// **'Обои зелёные'**
  String get itemWallSage;

  /// No description provided for @itemWallSky.
  ///
  /// In ru, this message translates to:
  /// **'Обои небо'**
  String get itemWallSky;

  /// No description provided for @itemWardrobe.
  ///
  /// In ru, this message translates to:
  /// **'Шкаф'**
  String get itemWardrobe;

  /// No description provided for @learnAdultLevelsNote.
  ///
  /// In ru, this message translates to:
  /// **'Уровень пройден — монеты в кошелёк, следующий открывается. Сложность растёт с номером уровня.'**
  String get learnAdultLevelsNote;

  /// No description provided for @learnAdultLogicSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'2048 в фирменных цветах'**
  String get learnAdultLogicSubtitle;

  /// No description provided for @learnAdultLogicTitle.
  ///
  /// In ru, this message translates to:
  /// **'Головоломки'**
  String get learnAdultLogicTitle;

  /// No description provided for @learnAdultMemorySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Найдите пары'**
  String get learnAdultMemorySubtitle;

  /// No description provided for @learnAdultMemoryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Память'**
  String get learnAdultMemoryTitle;

  /// No description provided for @learnAdultPuzzleSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Соберите фото мишки'**
  String get learnAdultPuzzleSubtitle;

  /// No description provided for @learnAdultPuzzleTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пазлы'**
  String get learnAdultPuzzleTitle;

  /// No description provided for @learnAgeAdultSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Пазлы с мишками, 2048, память'**
  String get learnAgeAdultSubtitle;

  /// No description provided for @learnAgeAdultTitle.
  ///
  /// In ru, this message translates to:
  /// **'Взрослый'**
  String get learnAgeAdultTitle;

  /// No description provided for @learnAgeChildSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Цвета и формы, счёт, окружающий мир'**
  String get learnAgeChildSubtitle;

  /// No description provided for @learnAgeChildTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ребёнок до {age}'**
  String learnAgeChildTitle(int age);

  /// No description provided for @learnAgeGateSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'От возраста зависит набор игр. Поменять можно в любой момент.'**
  String get learnAgeGateSubtitle;

  /// No description provided for @learnAgeGateTitle.
  ///
  /// In ru, this message translates to:
  /// **'Кто будет играть?'**
  String get learnAgeGateTitle;

  /// No description provided for @learnCatColorsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Цвета и формы'**
  String get learnCatColorsTitle;

  /// No description provided for @learnCatCountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Счёт и простая логика'**
  String get learnCatCountTitle;

  /// No description provided for @learnCatWorldTitle.
  ///
  /// In ru, this message translates to:
  /// **'Окружающий мир'**
  String get learnCatWorldTitle;

  /// No description provided for @learnCorrectToast.
  ///
  /// In ru, this message translates to:
  /// **'{coins, plural, one{Верно! +{coins} монета} few{Верно! +{coins} монеты} other{Верно! +{coins} монет}}'**
  String learnCorrectToast(int coins);

  /// No description provided for @learnGamesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Игры'**
  String get learnGamesTitle;

  /// No description provided for @learnLevelDoneToast.
  ///
  /// In ru, this message translates to:
  /// **'{coins, plural, one{Уровень пройден! +{coins} монета} few{Уровень пройден! +{coins} монеты} other{Уровень пройден! +{coins} монет}}'**
  String learnLevelDoneToast(int coins);

  /// No description provided for @learnLevelsCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} уровень} few{{count} уровня} other{{count} уровней}}'**
  String learnLevelsCount(int count);

  /// No description provided for @learnLevelsNote.
  ///
  /// In ru, this message translates to:
  /// **'По 10 уровней в каждой категории (КП 9.2). Движок рассчитан на 300 заданий, контент даёт Заказчик через панель (КП 9.4) — здесь по три задания на категорию для примера.'**
  String get learnLevelsNote;

  /// No description provided for @learnQuizHintNote.
  ///
  /// In ru, this message translates to:
  /// **'Верный ответ — анимация радости и награда.'**
  String get learnQuizHintNote;

  /// No description provided for @learnQuizTitle.
  ///
  /// In ru, this message translates to:
  /// **'{category} · уровень {level}'**
  String learnQuizTitle(String category, int level);

  /// No description provided for @learnQuizWrongNote.
  ///
  /// In ru, this message translates to:
  /// **'Не угадали. Попробуйте ещё раз — штрафа нет (КП 9.3).'**
  String get learnQuizWrongNote;

  /// No description provided for @learnTaskColorsCircle.
  ///
  /// In ru, this message translates to:
  /// **'Где круг?'**
  String get learnTaskColorsCircle;

  /// No description provided for @learnTaskColorsGreen.
  ///
  /// In ru, this message translates to:
  /// **'Где зелёный?'**
  String get learnTaskColorsGreen;

  /// No description provided for @learnTaskColorsRed.
  ///
  /// In ru, this message translates to:
  /// **'Где красный?'**
  String get learnTaskColorsRed;

  /// No description provided for @learnTaskCountApples.
  ///
  /// In ru, this message translates to:
  /// **'Сколько яблок? 🍎🍎🍎'**
  String get learnTaskCountApples;

  /// No description provided for @learnTaskCountBigger.
  ///
  /// In ru, this message translates to:
  /// **'Что больше?'**
  String get learnTaskCountBigger;

  /// No description provided for @learnTaskCountNext.
  ///
  /// In ru, this message translates to:
  /// **'Что дальше? 1, 2, 3…'**
  String get learnTaskCountNext;

  /// No description provided for @learnTaskWorldApples.
  ///
  /// In ru, this message translates to:
  /// **'Где растут яблоки?'**
  String get learnTaskWorldApples;

  /// No description provided for @learnTaskWorldDay.
  ///
  /// In ru, this message translates to:
  /// **'Что светит днём?'**
  String get learnTaskWorldDay;

  /// No description provided for @learnTaskWorldWater.
  ///
  /// In ru, this message translates to:
  /// **'Кто живёт в воде?'**
  String get learnTaskWorldWater;

  /// No description provided for @learnTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get learnTitle;

  /// No description provided for @moodDirty.
  ///
  /// In ru, this message translates to:
  /// **'Чумазый'**
  String get moodDirty;

  /// No description provided for @moodHappy.
  ///
  /// In ru, this message translates to:
  /// **'Радостный'**
  String get moodHappy;

  /// No description provided for @moodHungry.
  ///
  /// In ru, this message translates to:
  /// **'Голодный'**
  String get moodHungry;

  /// No description provided for @moodNormal.
  ///
  /// In ru, this message translates to:
  /// **'Спокойный'**
  String get moodNormal;

  /// No description provided for @moodSad.
  ///
  /// In ru, this message translates to:
  /// **'Грустный'**
  String get moodSad;

  /// No description provided for @moodSleepy.
  ///
  /// In ru, this message translates to:
  /// **'Сонный'**
  String get moodSleepy;

  /// No description provided for @navLockReason.
  ///
  /// In ru, this message translates to:
  /// **'Откроется на стадии «{stage}»'**
  String navLockReason(String stage);

  /// No description provided for @navSectionCatalog.
  ///
  /// In ru, this message translates to:
  /// **'Мишки'**
  String get navSectionCatalog;

  /// No description provided for @navSectionHome.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get navSectionHome;

  /// No description provided for @navSectionLearning.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get navSectionLearning;

  /// No description provided for @navSectionProfile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get navSectionProfile;

  /// No description provided for @navSectionRoom.
  ///
  /// In ru, this message translates to:
  /// **'Комната'**
  String get navSectionRoom;

  /// No description provided for @navSectionShop.
  ///
  /// In ru, this message translates to:
  /// **'Магазин'**
  String get navSectionShop;

  /// No description provided for @profileAgeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Возраст'**
  String get profileAgeLabel;

  /// No description provided for @profileBirthFur.
  ///
  /// In ru, this message translates to:
  /// **'{hero} · мех {fur}'**
  String profileBirthFur(String hero, String fur);

  /// No description provided for @profileFootnote.
  ///
  /// In ru, this message translates to:
  /// **'Рост, вес и знак зодиака — заглушки: их определяет сервер при рождении (КП 2.2, 2.5), а таблицу склонностей по знакам даёт Заказчик.'**
  String get profileFootnote;

  /// No description provided for @profileHeightLabel.
  ///
  /// In ru, this message translates to:
  /// **'Рост'**
  String get profileHeightLabel;

  /// No description provided for @profileHeightStub.
  ///
  /// In ru, this message translates to:
  /// **'15 см'**
  String get profileHeightStub;

  /// No description provided for @profileLinkDiary.
  ///
  /// In ru, this message translates to:
  /// **'Дневник'**
  String get profileLinkDiary;

  /// No description provided for @profileLinkDiarySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'события и фотоальбом'**
  String get profileLinkDiarySubtitle;

  /// No description provided for @profileLinkGrowth.
  ///
  /// In ru, this message translates to:
  /// **'Рост и развитие'**
  String get profileLinkGrowth;

  /// No description provided for @profileLinkGrowthSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'пять стадий и переходы'**
  String get profileLinkGrowthSubtitle;

  /// No description provided for @profileLinkSettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get profileLinkSettings;

  /// No description provided for @profileLinkSettingsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'язык и уведомления'**
  String get profileLinkSettingsSubtitle;

  /// No description provided for @profileSectionBirth.
  ///
  /// In ru, this message translates to:
  /// **'Карточка рождения · КП 2.2'**
  String get profileSectionBirth;

  /// No description provided for @profileSectionHistory.
  ///
  /// In ru, this message translates to:
  /// **'История стадий · КП 14.1'**
  String get profileSectionHistory;

  /// No description provided for @profileSectionLinks.
  ///
  /// In ru, this message translates to:
  /// **'Разделы'**
  String get profileSectionLinks;

  /// No description provided for @profileSectionTrait.
  ///
  /// In ru, this message translates to:
  /// **'Характер · КП 7'**
  String get profileSectionTrait;

  /// No description provided for @profileSexBoy.
  ///
  /// In ru, this message translates to:
  /// **'мальчик'**
  String get profileSexBoy;

  /// No description provided for @profileSexGirl.
  ///
  /// In ru, this message translates to:
  /// **'девочка'**
  String get profileSexGirl;

  /// No description provided for @profileSexLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пол'**
  String get profileSexLabel;

  /// No description provided for @profileStageNow.
  ///
  /// In ru, this message translates to:
  /// **'сейчас'**
  String get profileStageNow;

  /// No description provided for @profileStagePassed.
  ///
  /// In ru, this message translates to:
  /// **'пройдено'**
  String get profileStagePassed;

  /// No description provided for @profileStubBadge.
  ///
  /// In ru, this message translates to:
  /// **'заглушка'**
  String get profileStubBadge;

  /// No description provided for @profileTitle.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profileTitle;

  /// No description provided for @profileTraitHowLabel.
  ///
  /// In ru, this message translates to:
  /// **'Как считается'**
  String get profileTraitHowLabel;

  /// No description provided for @profileTraitHowValue.
  ///
  /// In ru, this message translates to:
  /// **'из действий за 3 дня'**
  String get profileTraitHowValue;

  /// No description provided for @profileTraitNowLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас'**
  String get profileTraitNowLabel;

  /// No description provided for @profileWeightLabel.
  ///
  /// In ru, this message translates to:
  /// **'Вес'**
  String get profileWeightLabel;

  /// No description provided for @profileWeightStub.
  ///
  /// In ru, this message translates to:
  /// **'180 г'**
  String get profileWeightStub;

  /// No description provided for @profileZodiacLabel.
  ///
  /// In ru, this message translates to:
  /// **'Знак зодиака'**
  String get profileZodiacLabel;

  /// No description provided for @recipeCookie.
  ///
  /// In ru, this message translates to:
  /// **'Печенье'**
  String get recipeCookie;

  /// No description provided for @recipeFruitSalad.
  ///
  /// In ru, this message translates to:
  /// **'Фруктовый салат'**
  String get recipeFruitSalad;

  /// No description provided for @recipeMeat.
  ///
  /// In ru, this message translates to:
  /// **'Мясное блюдо'**
  String get recipeMeat;

  /// No description provided for @recipeSandwich.
  ///
  /// In ru, this message translates to:
  /// **'Сэндвич'**
  String get recipeSandwich;

  /// No description provided for @recipeVeggie.
  ///
  /// In ru, this message translates to:
  /// **'Овощное блюдо'**
  String get recipeVeggie;

  /// No description provided for @roomFooterNote.
  ///
  /// In ru, this message translates to:
  /// **'52 предмета по КП 10: мебель 10, декор 16, игрушки 10, одежда 16. Сетка мест и предпросмотр — следующий шаг, сейчас предмет просто ставится или убирается.'**
  String get roomFooterNote;

  /// No description provided for @roomItemBought.
  ///
  /// In ru, this message translates to:
  /// **'{name} куплено'**
  String roomItemBought(String name);

  /// No description provided for @roomItemPlaced.
  ///
  /// In ru, this message translates to:
  /// **'{name} поставлено'**
  String roomItemPlaced(String name);

  /// No description provided for @roomItemRemoved.
  ///
  /// In ru, this message translates to:
  /// **'{name} убрано'**
  String roomItemRemoved(String name);

  /// No description provided for @roomNotEnoughCoins.
  ///
  /// In ru, this message translates to:
  /// **'Не хватает монет'**
  String get roomNotEnoughCoins;

  /// No description provided for @roomOwnedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Куплено'**
  String get roomOwnedLabel;

  /// No description provided for @roomSelectedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выбрано'**
  String get roomSelectedLabel;

  /// No description provided for @roomTitle.
  ///
  /// In ru, this message translates to:
  /// **'Моя комната'**
  String get roomTitle;

  /// No description provided for @settingsFootnote.
  ///
  /// In ru, this message translates to:
  /// **'Восемь типов уведомлений по КП 13.1, тихие часы и ограничение частоты — по 13.2. Привязка аккаунта и правовые документы (КП 14.2) появятся вместе с бэкендом.'**
  String get settingsFootnote;

  /// No description provided for @settingsNotifEvent.
  ///
  /// In ru, this message translates to:
  /// **'Событие'**
  String get settingsNotifEvent;

  /// No description provided for @settingsNotifGift.
  ///
  /// In ru, this message translates to:
  /// **'Подарок'**
  String get settingsNotifGift;

  /// No description provided for @settingsNotifHungry.
  ///
  /// In ru, this message translates to:
  /// **'Голоден'**
  String get settingsNotifHungry;

  /// No description provided for @settingsNotifPlay.
  ///
  /// In ru, this message translates to:
  /// **'Хочет играть'**
  String get settingsNotifPlay;

  /// No description provided for @settingsNotifShopNews.
  ///
  /// In ru, this message translates to:
  /// **'Новинки магазина'**
  String get settingsNotifShopNews;

  /// No description provided for @settingsNotifSleep.
  ///
  /// In ru, this message translates to:
  /// **'Пора спать'**
  String get settingsNotifSleep;

  /// No description provided for @settingsNotifStage.
  ///
  /// In ru, this message translates to:
  /// **'Новая стадия'**
  String get settingsNotifStage;

  /// No description provided for @settingsNotifTask.
  ///
  /// In ru, this message translates to:
  /// **'Задание'**
  String get settingsNotifTask;

  /// No description provided for @settingsQuietHours.
  ///
  /// In ru, this message translates to:
  /// **'Тихие часы 22:00 — 8:00'**
  String get settingsQuietHours;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык · КП 16.1'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsSectionNotifications.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления · КП 13.1, 13.2'**
  String get settingsSectionNotifications;

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @shopBuyFor.
  ///
  /// In ru, this message translates to:
  /// **'Купить за {total}'**
  String shopBuyFor(int total);

  /// No description provided for @shopCartDisclaimer.
  ///
  /// In ru, this message translates to:
  /// **'Корзины нет в КП — она с макета, я её отношу ко второй версии, но собрал, чтобы было видно поведение. Цены — плейсхолдеры (КП 10.9).'**
  String get shopCartDisclaimer;

  /// No description provided for @shopCartEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Корзина пуста'**
  String get shopCartEmpty;

  /// No description provided for @shopCheckoutDone.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{Куплен {count} предмет} few{Куплено {count} предмета} other{Куплено {count} предметов}}'**
  String shopCheckoutDone(int count);

  /// No description provided for @shopNotEnoughCoins.
  ///
  /// In ru, this message translates to:
  /// **'Не хватает монет'**
  String get shopNotEnoughCoins;

  /// No description provided for @shopOwnedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Куплено'**
  String get shopOwnedLabel;

  /// No description provided for @shopTabClothes.
  ///
  /// In ru, this message translates to:
  /// **'Одежда'**
  String get shopTabClothes;

  /// No description provided for @shopTabDecor.
  ///
  /// In ru, this message translates to:
  /// **'Декор'**
  String get shopTabDecor;

  /// No description provided for @shopTabFurniture.
  ///
  /// In ru, this message translates to:
  /// **'Мебель'**
  String get shopTabFurniture;

  /// No description provided for @shopTabToys.
  ///
  /// In ru, this message translates to:
  /// **'Игрушки'**
  String get shopTabToys;

  /// No description provided for @shopTitle.
  ///
  /// In ru, this message translates to:
  /// **'Магазин'**
  String get shopTitle;

  /// No description provided for @skinJoy.
  ///
  /// In ru, this message translates to:
  /// **'JOY'**
  String get skinJoy;

  /// No description provided for @skinSlow.
  ///
  /// In ru, this message translates to:
  /// **'SLOW'**
  String get skinSlow;

  /// No description provided for @stageAdult.
  ///
  /// In ru, this message translates to:
  /// **'Взрослый'**
  String get stageAdult;

  /// No description provided for @stageCrawling.
  ///
  /// In ru, this message translates to:
  /// **'Ползающий малыш'**
  String get stageCrawling;

  /// No description provided for @stageFirstSteps.
  ///
  /// In ru, this message translates to:
  /// **'Первые шаги'**
  String get stageFirstSteps;

  /// No description provided for @stageGrowing.
  ///
  /// In ru, this message translates to:
  /// **'Подрастающий'**
  String get stageGrowing;

  /// No description provided for @stageNewborn.
  ///
  /// In ru, this message translates to:
  /// **'Новорождённый'**
  String get stageNewborn;

  /// No description provided for @statsFood.
  ///
  /// In ru, this message translates to:
  /// **'Еда'**
  String get statsFood;

  /// No description provided for @statsHygiene.
  ///
  /// In ru, this message translates to:
  /// **'Гигиена'**
  String get statsHygiene;

  /// No description provided for @statsLove.
  ///
  /// In ru, this message translates to:
  /// **'Любовь'**
  String get statsLove;

  /// No description provided for @statsPlay.
  ///
  /// In ru, this message translates to:
  /// **'Игра'**
  String get statsPlay;

  /// No description provided for @statsSleep.
  ///
  /// In ru, this message translates to:
  /// **'Сон'**
  String get statsSleep;

  /// No description provided for @traitActive.
  ///
  /// In ru, this message translates to:
  /// **'Активный'**
  String get traitActive;

  /// No description provided for @traitAffectionate.
  ///
  /// In ru, this message translates to:
  /// **'Ласковый'**
  String get traitAffectionate;

  /// No description provided for @traitCalm.
  ///
  /// In ru, this message translates to:
  /// **'Спокойный'**
  String get traitCalm;

  /// No description provided for @traitCurious.
  ///
  /// In ru, this message translates to:
  /// **'Любознательный'**
  String get traitCurious;

  /// No description provided for @traitIndependent.
  ///
  /// In ru, this message translates to:
  /// **'Самостоятельный'**
  String get traitIndependent;

  /// No description provided for @traitReserved.
  ///
  /// In ru, this message translates to:
  /// **'Замкнутый'**
  String get traitReserved;

  /// No description provided for @zodiacAquarius.
  ///
  /// In ru, this message translates to:
  /// **'Водолей'**
  String get zodiacAquarius;

  /// No description provided for @zodiacAries.
  ///
  /// In ru, this message translates to:
  /// **'Овен'**
  String get zodiacAries;

  /// No description provided for @zodiacCancer.
  ///
  /// In ru, this message translates to:
  /// **'Рак'**
  String get zodiacCancer;

  /// No description provided for @zodiacCapricorn.
  ///
  /// In ru, this message translates to:
  /// **'Козерог'**
  String get zodiacCapricorn;

  /// No description provided for @zodiacGemini.
  ///
  /// In ru, this message translates to:
  /// **'Близнецы'**
  String get zodiacGemini;

  /// No description provided for @zodiacInfluenceAquarius.
  ///
  /// In ru, this message translates to:
  /// **'Выдумщик и вольнодум: удивляет и находит свои пути.'**
  String get zodiacInfluenceAquarius;

  /// No description provided for @zodiacInfluenceAries.
  ///
  /// In ru, this message translates to:
  /// **'Смелый и порывистый: с первых дней норовит всё попробовать сам.'**
  String get zodiacInfluenceAries;

  /// No description provided for @zodiacInfluenceCancer.
  ///
  /// In ru, this message translates to:
  /// **'Нежный домосед: расцветает от заботы и долгих объятий.'**
  String get zodiacInfluenceCancer;

  /// No description provided for @zodiacInfluenceCapricorn.
  ///
  /// In ru, this message translates to:
  /// **'Терпеливый и упорный: маленькими шагами добирается до большого.'**
  String get zodiacInfluenceCapricorn;

  /// No description provided for @zodiacInfluenceGemini.
  ///
  /// In ru, this message translates to:
  /// **'Любопытный и общительный: тянется ко всему новому обеими лапами.'**
  String get zodiacInfluenceGemini;

  /// No description provided for @zodiacInfluenceLeo.
  ///
  /// In ru, this message translates to:
  /// **'Тёплый и артистичный: обожает внимание и щедро отвечает лаской.'**
  String get zodiacInfluenceLeo;

  /// No description provided for @zodiacInfluenceLibra.
  ///
  /// In ru, this message translates to:
  /// **'Дружелюбный миротворец: ценит красоту, компанию и мягкий тон.'**
  String get zodiacInfluenceLibra;

  /// No description provided for @zodiacInfluencePisces.
  ///
  /// In ru, this message translates to:
  /// **'Мечтательный и чуткий: тонко чувствует твоё настроение.'**
  String get zodiacInfluencePisces;

  /// No description provided for @zodiacInfluenceSagittarius.
  ///
  /// In ru, this message translates to:
  /// **'Весёлый искатель приключений: игры и прогулки — его стихия.'**
  String get zodiacInfluenceSagittarius;

  /// No description provided for @zodiacInfluenceScorpio.
  ///
  /// In ru, this message translates to:
  /// **'Глубокий и преданный: привязывается всерьёз и надолго.'**
  String get zodiacInfluenceScorpio;

  /// No description provided for @zodiacInfluenceTaurus.
  ///
  /// In ru, this message translates to:
  /// **'Спокойный и основательный: любит уют, вкусную еду и свой распорядок.'**
  String get zodiacInfluenceTaurus;

  /// No description provided for @zodiacInfluenceVirgo.
  ///
  /// In ru, this message translates to:
  /// **'Внимательный и аккуратный: замечает мелочи и любит порядок.'**
  String get zodiacInfluenceVirgo;

  /// No description provided for @zodiacLeo.
  ///
  /// In ru, this message translates to:
  /// **'Лев'**
  String get zodiacLeo;

  /// No description provided for @zodiacLibra.
  ///
  /// In ru, this message translates to:
  /// **'Весы'**
  String get zodiacLibra;

  /// No description provided for @zodiacPisces.
  ///
  /// In ru, this message translates to:
  /// **'Рыбы'**
  String get zodiacPisces;

  /// No description provided for @zodiacSagittarius.
  ///
  /// In ru, this message translates to:
  /// **'Стрелец'**
  String get zodiacSagittarius;

  /// No description provided for @zodiacScorpio.
  ///
  /// In ru, this message translates to:
  /// **'Скорпион'**
  String get zodiacScorpio;

  /// No description provided for @zodiacTaurus.
  ///
  /// In ru, this message translates to:
  /// **'Телец'**
  String get zodiacTaurus;

  /// No description provided for @zodiacVirgo.
  ///
  /// In ru, this message translates to:
  /// **'Дева'**
  String get zodiacVirgo;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

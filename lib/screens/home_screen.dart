import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../bear/bear.dart';
import '../bear/rive_bear_trial.dart';
import '../alarm/wake_alarm.dart';
import '../game/app_section.dart';
import '../game/game_calendar.dart';
import '../game/eaten_dishes.dart';
import '../game/food.dart';
import '../game/game_state.dart';
import '../game/pet_name.dart';
import '../game/test_stubs.dart';
import '../game/room_kind.dart';
import '../game/room_slots.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/food_l10n.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart' show petDisplayName, stageTitle;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/emotion_test_strip.dart';
import '../widgets/alarm_sheet.dart';
import '../widgets/bedroom_scene.dart';
import '../widgets/kitchen_cooking.dart';
import '../widgets/kitchen_scene.dart';
import '../widgets/night_window.dart';
import '../widgets/sleep_thought.dart';
import '../widgets/care_stats_panel.dart';
import '../widgets/dish_carousel.dart';
import '../widgets/daily_sheet.dart';
import '../widgets/share_card.dart';
import '../widgets/sleeping_elsewhere.dart';
import '../widgets/gift_reveal.dart' show showCoinReward;
import '../widgets/glass_panel.dart' show glassRoute;
import '../widgets/notify_prompt.dart';
import '../widgets/sleep_countdown.dart';
import '../game/referral_info.dart';
import '../widgets/feed_burst.dart';
import '../widgets/furnish_bar.dart';
import '../widgets/paw_menu.dart';
import '../widgets/pet_header.dart';
import '../widgets/pet_speech_bubble.dart';
import '../widgets/kitchen_bear.dart';
import '../widgets/stats_test_panel.dart';
import '../bear/bear_life.dart';
import '../widgets/room_item_sheet.dart';
import '../widgets/room_ceiling.dart';
import '../widgets/room_slot_layer.dart';
import '../widgets/room_scene_backdrop.dart';
import '../widgets/purchase_confirm.dart';
import '../widgets/room_surfaces.dart';
import '../widgets/sleep_zzz.dart';
import '../widgets/section_sheet.dart';
import 'care_screen.dart';
import 'catalog_screen.dart';
import 'diary_screen.dart';
import 'feed_screen.dart';
import 'growth_screen.dart';
import 'learning_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import '../widgets/top_toast.dart';

/// Главный экран — комната с питомцем (КП 3).
///
/// Собран по макету, но без механик, которых нет в КП: полосы уровня, счётчика
/// сердец, кнопок камеры и подарка, вкладки «Достижения». Всё это отнесено во
/// вторую версию — см. `docs/design-review.md`.
///
/// Фон комнаты пока однотонный: сцена комнаты с мебелью — это раздел 10 КП,
/// отдельная работа с ассетами.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.game,
    required this.language,
    required this.onLanguageChanged,
    this.calendar = const GameCalendar(),
    this.onOpenDevPanel,
    this.onSignOut,
    this.onRename,
    this.riveAssetPath = BearRigSpec.assetPath,
    this.wakeAlarm,
  });

  final BearController controller;

  /// Кошелёк, инвентарь и прогресс — всё, что не уезжает в риг.
  final GameState game;

  final GameCalendar calendar;

  /// Язык живёт выше по дереву: тот же выбор управляет репликами питомца
  /// и текстами уведомлений, поэтому экран настроек им не владеет.
  final BearLanguage language;
  final ValueChanged<BearLanguage> onLanguageChanged;

  /// Открыть дев-панель со всеми входами State Machine. `null` в релизе —
  /// кнопки просто нет.
  final void Function(BuildContext context)? onOpenDevPanel;

  /// Выход из аккаунта (КП 14.2). `null` — пункта выхода нет ни в профиле,
  /// ни в настройках.
  final VoidCallback? onSignOut;

  /// Переименовать питомца (КП 2.3). `null` — карандаша рядом с именем нет.
  final Future<PetNameError?> Function(String name)? onRename;

  /// Какой `.riv` показывать. Пока настоящий риг не собран, сюда можно
  /// подставить [BearRigSpec.demoAssetPath] и убедиться, что пайплайн живой.
  final String riveAssetPath;

  /// Будильник «проснёмся вместе»: ставит время в будильник телефона.
  /// `null` — только запомнить время (тесты, старые вызовы).
  final WakeAlarm? wakeAlarm;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  /// Открытая комната. Живёт в памяти экрана: это не прогресс, а взгляд —
  /// куда человек сейчас смотрит. Уходить на сервер здесь нечему.
  RoomKind _room = RoomKind.nursery;

  /// Мишку уложили спать: глаза закрыты, кнопка на ковре убрана.
  /// Сон живёт на сервере (миграция 0016): уложили — спит, пока не
  /// разбудят, не покормят, не займутся им или не выспится сам; уход из
  /// спальни его не будит.
  bool get _asleep => widget.game.asleep;

  /// ⚠ Проверка файла аниматора в игровой (заказчик 26.09): выражения
  /// лица мишки из `bear_boy_v2.riv`.
  final BearFaceCue _faceCue = BearFaceCue();

  /// Облачко-реплика мишки над кольцами (КП 3.4, 13.3). Заказчик 26.09:
  /// пока скрыто во всех комнатах, вернём позже — включить здесь.
  /// Пузырь вернулся в игровую (заказчик 27.09, живой мишка): реплика по
  /// состоянию и нужде (`BearLife`), тап — действие. В других комнатах —
  /// пока нет (заказчик 26.09).
  static const bool _showSpeechBubble = true;

  /// Живой мишка: состояние по показателям с гистерезисом, однократные
  /// реакции на события (голод, покормили, проснулся, вошли).
  late final BearLife _life = BearLife(
    controller: widget.controller,
    cue: _faceCue,
  );
  Timer? _lifeTimer;

  /// Картинки спальни раскодированы заранее — один раз на экран.
  bool _bedroomWarm = false;

  void _showRoom(RoomKind room) {
    if (room == _room) return;
    _life
      ..present = room == RoomKind.nursery || room == RoomKind.kitchen
      ..inKitchen = room == RoomKind.kitchen;
    setState(() {
      _room = room;
      // Ушли с кухни — блюда и готовка со стола убираются.
      _dishesShown = false;
      _recipesShown = false;
      _cooking = null;
      _dropCookPending();
      _resetArc();
    });
  }

  /// Кнопки на ковре: «Уложить спать» — мишка засыпает и закрывает глаза,
  /// «Разбудить» — открывает и дальше просто моргает.
  ///
  /// Заказчик 22.09 отложил связь с показателем сна «следующим шагом»; 25.09
  /// утвердил ночной режим: уложенный мишка спит на сервере, сон
  /// восстанавливается постепенно, остальные потребности падают вчетверо
  /// медленнее, уложил вовремя (20–23) — бонус (миграция 0016). Шкала сна
  /// сразу не прыгает до 100 — как и просил заказчик.
  void _putToBed() {
    widget.game.setAsleep(true);
    widget.controller.putToSleep(amount: 10);
  }

  void _wake() {
    widget.game.setAsleep(false);
    widget.controller.wakeBear();
  }

  /// На какое время поставлен будильник «проснёмся вместе».
  ///
  /// Само время живёт в памяти экрана, а звонит будильник телефона:
  /// «Часы» на Android, системный будильник на iPhone с iOS 26, на старых
  /// iPhone — уведомление со звуком (заказчик 24.09). Привязка к аккаунту
  /// на Supabase — отдельным шагом.
  TimeOfDay? _alarm;

  Future<void> _pickAlarm() async {
    final picked = await showAlarmSheet(
      context: context,
      initial: _alarm ?? const TimeOfDay(hour: 7, minute: 30),
    );
    if (picked == null || !mounted) return;
    final previous = _alarm;
    setState(() => _alarm = picked);

    final alarm = widget.wakeAlarm;
    if (alarm == null) return;
    final l10n = context.l10n;
    final name = widget.game.profile.name;
    final outcome = await alarm.set(
      picked,
      label: l10n.wakeAlarmLabel(name),
      stop: l10n.wakeAlarmStop,
      body: l10n.wakeAlarmBody(name),
    );
    if (!mounted) return;
    _toastWake(outcome, picked, previous, alarm);
  }

  /// Что стало с будильником — уведомлением сверху.
  void _toastWake(
    WakeAlarmOutcome outcome,
    TimeOfDay time,
    TimeOfDay? previous,
    WakeAlarm alarm,
  ) {
    final l10n = context.l10n;
    final format = MaterialLocalizations.of(context);
    String show(TimeOfDay t) =>
        format.formatTimeOfDay(t, alwaysUse24HourFormat: true);
    final at = show(time);
    final text = switch (outcome) {
      WakeAlarmOutcome.clock =>
        previous != null && previous != time
            // Из чужих «Часов» старый будильник не убрать — честно
            // говорим, где он остался.
            ? '${l10n.wakeAlarmClock(at)}. ${l10n.wakeAlarmClockOld(show(previous))}'
            : l10n.wakeAlarmClock(at),
      WakeAlarmOutcome.alarmKit => l10n.wakeAlarmSystem(at),
      WakeAlarmOutcome.notification => l10n.wakeAlarmNotification(at),
      WakeAlarmOutcome.preview => l10n.wakeAlarmPreview(at),
      WakeAlarmOutcome.denied => l10n.wakeAlarmDenied,
      WakeAlarmOutcome.failed => l10n.wakeAlarmFailed,
    };
    // Сверху, а не над кнопками на ковре: «Разбудить» и будильник
    // остаются под рукой, пока строка висит. Текст длинный — держится дольше.
    showTopToast(
      context,
      text,
      icon: Icons.alarm_rounded,
      duration: const Duration(seconds: 5),
      actionLabel: outcome == WakeAlarmOutcome.clock
          ? l10n.wakeAlarmOpenClock
          : null,
      onAction: outcome == WakeAlarmOutcome.clock ? alarm.openClock : null,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bedroomWarm) return;
    _bedroomWarm = true;
    // Сцена сна собрана из десятка картинок; если грузить их в момент
    // открытия, мишка появляется по частям. Греем, пока человек на главной.
    BedroomScene.warmUp(context);
    KitchenScene.warmUp(context);
  }

  void _runAction(BearAction action) {
    final controller = widget.controller;

    // Комната — следствие действия (`roomForAction`), а не отдельный выбор.
    final room = roomForAction(action);
    if (room != null) _showRoom(room);

    // Спит — кольца «Игра» и «Гигиена» только приводят в комнату, как
    // «Еда» на кухню (заказчик 26.09). Иначе «поиграть» и «помыть» уходили
    // на сервер, тот будил мишку, и панель «Мишка спит» мелькала и
    // пропадала. Будить — кнопкой на панели.
    if (_asleep && (action == BearAction.play || action == BearAction.wash)) {
      return;
    }

    switch (action) {
      // Кормление само по себе ничего не открывает: по решению заказчика
      // 20.09 «Еда» просто приводит мишку на кухню, а что он будет есть,
      // выбирается уже там — двумя кнопками на столе. Иначе комната
      // мелькала бы и тут же закрывалась листом, и нажатие выглядело бы
      // так, будто кухня ни при чём.
      case BearAction.feed:
        break;
      // Заказчик 27.09: кольца только переключают комнаты, показатели
      // от нажатия не растут — мыть, играть, гладить надо по-настоящему.
      case BearAction.wash:
        break;
      // Сон так же: кольцо только приводит в спальню, показатель не
      // пополняет — заказчик 22.09: «при нажатии кнопки на сон оно не
      // должно пополняться до 100%». Уложить — кнопкой на ковре.
      case BearAction.sleep:
        break;
      case BearAction.play:
        break;
      case BearAction.pet:
        break;
      case BearAction.wake:
        controller.wakeBear();
      // Обучение, гардероб и редактор комнаты живут в своих разделах —
      // отсюда только отмечаем намерение, экранов ещё нет.
      case BearAction.learn:
      case BearAction.dressUp:
      case BearAction.decorate:
        _notImplemented(action);
    }
  }

  /// Открывает экран поверх главного и возвращает вкладку на «Главную»:
  /// у разделов свои полноэкранные виды с кнопкой «назад», как на макете.
  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Экран поверх размытой комнаты (заказчик 26.09): профиль, рост,
  /// дневник, настройки — комната остаётся сзади.
  Future<void> _openGlass(Widget screen) =>
      Navigator.of(context).push<void>(glassRoute(screen));

  /// Раздел открывается листом поверх комнаты, а не отдельным экраном
  /// (решение заказчика 20.09). Мишка при этом остаётся виден над листом —
  /// покупка и обучение происходят при нём, а не вместо него.
  Future<T?> _openSheet<T>(Widget screen) =>
      showSectionSheet<T>(context: context, builder: (_) => screen);

  /// Включён ли режим обустройства и какая вещь сейчас в руках.
  ///
  /// Заказчик 20.09 согласился развести магазин и комнату: магазин — касса,
  /// комната — только «куда поставить». Расстановка живёт прямо здесь, на
  /// сцене, а не на отдельном экране: расстановка — это примерка, а уйти
  /// на другой экран, выбрать вещь вслепую и вернуться смотреть — уже не
  /// примерка.
  bool _furnishing = false;
  ShopItem? _picked;

  /// Стены или пол, которые примеряют, пока открыто окно покупки.
  ShopItem? _surfacePreview;

  /// В ленте открыты «Стены» или «Пол»: крестиков мест нет, тапы по местам
  /// ничего не делают (заказчик 09.10: крестики — только когда ставят вещи).
  bool _surfaceTab = false;

  /// Высота ленты обустройства: комната приподнимается над ней, чтобы
  /// нижние места (ковёр) не прятались под лентой (заказчик 10.10).
  double _furnishBarHeight = 0;

  /// Выбор стен или пола в ленте обустройства. Свои и бесплатные ставятся
  /// сразу; платные сначала примеряются — комната уже в новом цвете, пока
  /// человек решает в окне покупки, — и остаются, только если купили.
  Future<void> _pickSurface(ShopItem item) async {
    final game = widget.game;
    if (game.isPlaced(item.id)) return;
    if (!game.isOwned(item.id)) {
      if (item.price == 0) {
        if (!game.buy(item.id)) return;
      } else {
        setState(() => _surfacePreview = item);
        final ok = await buyItemConfirmed(
          context: context,
          game: game,
          item: item,
        );
        if (!mounted) return;
        setState(() => _surfacePreview = null);
        if (!ok) return;
      }
    }
    game.togglePlaced(item.id);
    setState(() {});
  }

  void _startFurnishing() => setState(() {
    // Обставляется только детская: кухня и ванная — снятые кадры, мест в них
    // нет (заказчик 21.09: «они статичны»). Нажать «Обставить», стоя на
    // кухне, человек может — и попадёт туда, где обставлять есть что, а не
    // в пустую ленту без единого места.
    if (slotsOf(_room).isEmpty) _room = RoomKind.nursery;
    _furnishing = true;
    _picked = null;
    _surfaceTab = false;
  });

  void _stopFurnishing() => setState(() {
    _furnishing = false;
    _picked = null;
    _surfaceTab = false;
  });

  /// Тап по месту в режиме обустройства.
  void _useSlot(RoomSlot slot) {
    if (_surfaceTab) return;
    final game = widget.game;
    final l10n = context.l10n;
    final picked = _picked;

    if (picked != null) {
      if (!slot.takes(picked)) {
        _toastFurnish(l10n.furnishNoSlot);
        return;
      }
      game.placeInSlot(slot.id, picked.id);
      _toastFurnish(l10n.furnishPlaced(shopItemName(l10n, picked.id)));
      setState(() => _picked = null);
      return;
    }

    // Вещь не выбрана: тап по занятому месту убирает вещь обратно к себе.
    final standing = game.itemInSlot(slot.id);
    if (standing == null) return;

    game.clearSlot(slot.id);
    _toastFurnish(l10n.furnishRemoved(shopItemName(l10n, standing)));
    setState(() {});
  }

  void _toastFurnish(String text) => showTopToast(context, text);

  void _openSection(AppSection section) {
    switch (section) {
      // «Комната» больше не список с ценами, а режим прямо на сцене.
      case AppSection.room:
        _startFurnishing();
      case AppSection.shop:
        _openShop();
      case AppSection.learning:
        _openSheet(LearningScreen(game: widget.game));
      case AppSection.catalog:
        _openSheet(CatalogScreen(controller: widget.controller));
      case AppSection.profile:
        _openGlass(_profileScreen());
      // «Главная» — это и есть комната на экране. Отдельного перехода у неё
      // нет: закрыл лист — ты дома.
      case AppSection.home:
        break;
    }
  }

  /// Магазин — стеклянной панелью на полэкрана (заказчик 10.10): над ней
  /// видна комната, и купленное встаёт в ней прямо на глазах. Вещь для
  /// игровой — сразу показываем игровую, где бы ни стоял человек.
  Future<void> _openShop() => showShopSheet(
    context,
    game: widget.game,
    onApplied: (_) => _showRoom(RoomKind.nursery),
  );

  /// Профиль — единственный экран с ветвлением: из него открываются рост,
  /// дневник и настройки (КП 14.1, 14.2).
  Widget _profileScreen() => ProfileScreen(
    controller: widget.controller,
    game: widget.game,
    calendar: widget.calendar,
    language: widget.language,
    onOpenGrowth: () => _openGlass(
      GrowthScreen(controller: widget.controller, profile: widget.game.profile),
    ),
    onOpenDiary: () => _openGlass(const DiaryScreen()),
    onSignOut: widget.onSignOut == null ? null : _signOut,
    onRename: widget.onRename,
    onOpenSettings: () => _openGlass(
      SettingsScreen(
        game: widget.game,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
        onSignOut: widget.onSignOut == null ? null : _signOut,
      ),
    ),
  );

  /// Выход: сначала закрываем всё, что открыто поверх главного экрана, и
  /// только потом сообщаем наверх.
  ///
  /// Порядок здесь не косметический. Приложение по этому вызову подменяет
  /// корневой экран на вход, но профиль и настройки лежат в стеке **над**
  /// ним и сами никуда не денутся — вышедший человек остался бы смотреть на
  /// свой же профиль, а под ним висел бы экран входа.
  void _signOut() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onSignOut?.call();
  }

  /// Тап по месту в комнате — занятому или свободному.
  ///
  /// Один обработчик на оба случая: для человека это одно действие —
  /// решить, что здесь стоит. Лист сам покажет «убрать», если место занято.
  void _openSlotSheet(RoomSlot slot) {
    showSlotSheet(context: context, game: widget.game, slot: slot);
  }

  /// Горшок в ванной. Механики в КП нет — кнопка стоит, чтобы заказчик
  /// видел состав ванной целиком, и честно говорит, что её ещё нет.
  void _toilet() => _soon(context.l10n.bathToiletSoon);

  /// Купание. Показатель гигиены поднимался, а самого купания не было: ни
  /// пены, ни воды, ни анимации — просто росла цифра. Заказчик 20.09
  /// попросил и здесь говорить честно, как про горшок: «мы чиним душ, скоро
  /// будет работать».
  ///
  /// Поэтому кнопка больше ничего не поднимает. Механика мытья цела
  /// (`controller.washBear`) и вернётся сюда, когда у аниматора будет сцена
  /// купания.
  void _wash() => _soon(context.l10n.bathWashSoon);

  /// Бутылочка и подгузник новорождённого (КП 5, заказчик 26.09: «с
  /// заглушками до анимации»). ⚠ Ждут клипов аниматора — пока честное
  /// «скоро», как у душа и горшка.
  void _bottle() => _soon(context.l10n.kitchenBottleSoon);
  void _diaper() => _soon(context.l10n.bathDiaperSoon);

  /// Сообщение «этого ещё нет». Нарочно одинаковое для всех недоделок:
  /// тестировщик по нему сразу понимает, что нажатие обработано, а работы
  /// ещё идут.
  void _soon(String text, {String? actionLabel, VoidCallback? onAction}) =>
      showTopToast(
        context,
        text,
        actionLabel: actionLabel,
        onAction: onAction,
        // С кнопкой — дольше: чтобы успеть нажать.
        duration: onAction == null
            ? TopToasts.defaultDuration
            : const Duration(seconds: 5),
      );

  /// Последнее кормление: по нему мишка на кухне ест и радуется.
  KitchenMeal? _meal;
  int _meals = 0;

  /// Стоят ли готовые блюда на столе (дуга, заказчик 24.09).
  bool _dishesShown = false;

  /// Любимое блюдо, которое мишка сейчас просит: о нём подсказка над
  /// кнопками, у него сердечко на табло.
  String? _craving;
  final math.Random _random = math.Random();

  /// Съеденные блюда: их нет на столе до следующего голода (заказчик
  /// 24.09). Пока список поднимается с телефона — пустой.
  EatenDishes _eaten = EatenDishes(returnAfter: null);

  /// Проверка «не проголодался ли мишка» — раз в полминуты: блюда
  /// возвращаются на стол без перезахода на кухню.
  Timer? _hungerTimer;

  /// Блюда на столе — каталог без съеденных, в том же порядке.
  List<Dish> _table = FoodCatalog.dishes;

  /// Какое блюдо перед мишкой. При входе на кухню — паста.
  final DishArc _dishArc = DishArc(
    count: FoodCatalog.dishes.length,
    initial: FoodCatalog.dishes.indexWhere((d) => d.id == 'pasta'),
  );

  /// Рецепты на столе — та же дуга, что у готовых блюд (готовка на кухне,
  /// вариант A, заказчик 24.09). Перед мишкой сначала сэндвич, как в
  /// утверждённом макете.
  bool _recipesShown = false;
  final DishArc _recipeArc = DishArc(
    count: FoodCatalog.recipes.length,
    initial: FoodCatalog.recipes.indexWhere((r) => r.id == 'sandwich'),
  );

  /// Что сейчас готовится. Пока готовится — стол пустой, продукты под
  /// столом. Номер — чтобы новая готовка начиналась с чистого листа.
  Recipe? _cooking;
  int _cookRun = 0;

  /// Сколько раз положили не тот продукт: мишка мотает головой.
  int _refusals = 0;

  /// Пузырь сытости (заказчик 24.09): съеденное летит пузырьком с «+N» в
  /// кружок «Еда», монеты делают «у-у» в момент удара. Заменил строку
  /// «Пирог · еда +40, −15 монет» внизу экрана.
  final FeedFx _fx = FeedFx();

  /// Касание где угодно на главном экране (заказчик 10.10): кольца
  /// показателей начинают отсчёт бездействия заново.
  final _Activity _activity = _Activity();

  /// Готовка засчитана, а пузырь ещё не вылетел: мишка ест.
  Recipe? _cookPending;

  /// Где на экране тарелка перед мишкой — оттуда рождается пузырь.
  static Offset Function(Size) _plateSpot(String plateId) => (size) {
    final frame = RoomFrame.of(size, RoomKind.kitchen).rect;
    final plate = DishArcGeometry.plate(
      plateId,
      0,
      frame.size,
    ).shift(frame.topLeft);
    return Offset(plate.center.dx, plate.bottom - plate.width * 0.3);
  };

  /// Запомнить числа до еды: на экране они сменятся, когда пузырь ударит.
  void _holdStats() => _fx.hold(
    food: widget.controller.stats.food,
    coins: widget.game.profile.coins,
  );

  /// Готовку бросили после того, как блюдо засчитали: пузыря не будет,
  /// числа просто добегают до настоящих.
  void _dropCookPending() {
    if (_cookPending == null) return;
    _cookPending = null;
    _fx.settle();
  }

  @override
  void initState() {
    super.initState();
    _closeGap =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 650),
        )..addListener(
          () =>
              _dishArc.gap = 1 - Curves.easeOutCubic.transform(_closeGap.value),
        );
    _eaten.addListener(_onEatenChanged);
    EatenDishes.open().then((eaten) {
      if (!mounted) {
        eaten.dispose();
        return;
      }
      _eaten
        ..removeListener(_onEatenChanged)
        ..dispose();
      _eaten = eaten..addListener(_onEatenChanged);
      _refreshEaten();
      _onEatenChanged();
    });
    _hungerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshEaten(),
    );
    widget.game.addListener(_onGame);
    _life
      ..addListener(_onLife)
      ..asleep = widget.game.asleep
      ..present = _room == RoomKind.nursery || _room == RoomKind.kitchen
      ..inKitchen = _room == RoomKind.kitchen;
    _lifeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _life.tick(),
    );
    // Долго не заходил — мишка гостил у бабушки (миграция 0016): одна
    // тёплая строка при входе вместо молчаливо подросших шкал.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        // Первый запуск (рождение, имя, код друга) — сначала он.
        await _afterOnboarding();
        if (!mounted) return;
        // Сначала праздник пригласившего (друг пришёл по коду), потом
        // окно «Сегодня» — не друг поверх друга.
        await _maybeInviterReward();
        if (mounted) await _maybeShowDaily();
        if (mounted) await _maybeRedeemLink();
        // Мишке исполнился день — «Напоминать о малыше?» (КП 13.1).
        if (mounted) await maybeAskNotifications(context, widget.game);
        // «Гостил у бабушки» — последним, когда окна закрыты: строка не
        // должна прятаться под «Сегодня» или «Родился малыш!».
        if (mounted) _maybeWelcomeBack();
      }());
    });
  }

  void _maybeWelcomeBack() {
    if (!widget.game.welcomeBack) return;
    widget.game.welcomeBack = false;
    _soon(
      context.l10n.welcomeBackGrandma(
        petDisplayName(context.l10n, widget.game.profile.name),
      ),
    );
  }

  /// Сон пришёл с сервера (уложили на другом устройстве, выспался сам,
  /// разбудила еда) — спальня перерисовывается. Мишка подрос на сервере —
  /// праздник одной строкой (КП 5.6).
  void _onLife() {
    if (mounted) setState(() {});
  }

  void _onGame() {
    _life.asleep = widget.game.asleep;
    if (!mounted) return;
    setState(() {});
    final stage = widget.game.stageUp;
    if (stage != null) {
      widget.game.stageUp = null;
      final l10n = context.l10n;
      _soon(
        l10n.stageUpCelebrate(
          petDisplayName(l10n, widget.game.profile.name),
          stageTitle(l10n, stage),
        ),
        // Сверх ТЗ (заказчик 25.09): «подрос!» — карточкой в соцсети.
        actionLabel: l10n.shareAction,
        onAction: () => showShareCard(
          context,
          game: widget.game,
          stage: stage,
          grown: true,
        ),
      );
    }
  }

  /// Пришли по ссылке приглашения (`?ref=КОД`, веб-версия): код друга
  /// вводится сам, один раз за запуск. Отказы молча — код можно ввести и
  /// в профиле.
  static bool _linkTried = false;

  Future<void> _maybeRedeemLink() async {
    if (_linkTried || !kIsWeb) return;
    _linkTried = true;
    final code = Uri.base.queryParameters['ref']?.trim() ?? '';
    if (code.isEmpty) return;
    final info = await widget.game.referral();
    if (info == null || !info.canRedeem || info.code == code.toUpperCase()) {
      return;
    }
    final result = await widget.game.redeemReferral(code);
    if (mounted && result == RedeemResult.ok) {
      await showCoinReward(
        context,
        amount: info.coins,
        total: widget.game.coins,
        title: context.l10n.rewardFromFriend,
      );
    }
  }

  /// Ждёт, пока закончится первый запуск: окна не должны открываться
  /// поверх «Родился малыш!» и выбора имени.
  Future<void> _afterOnboarding() async {
    final flag = widget.game.onboarding;
    if (!flag.value) return;
    final done = Completer<void>();
    void listener() {
      if (!flag.value && !done.isCompleted) done.complete();
    }

    flag.addListener(listener);
    await done.future;
    flag.removeListener(listener);
  }

  /// По коду пригласившего пришёл друг (заказчик 26.09): при входе —
  /// праздник монет, а не тихая прибавка в кошельке. Что уже показано,
  /// помнит телефон; сервер отдаёт, сколько всего принесли приглашения.
  static bool _inviterChecked = false;

  Future<void> _maybeInviterReward() async {
    if (_inviterChecked) return;
    _inviterChecked = true;
    final info = await widget.game.referral();
    if (info == null || !mounted) return;
    int? seen;
    final key = 'referral_earned_seen_${info.code}';
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getInt(key);
      await prefs.setInt(key, info.earned);
    } on Object {
      return;
    }
    final gained = info.earned - (seen ?? 0);
    if (gained <= 0 || !mounted) return;
    await showCoinReward(
      context,
      amount: gained,
      total: widget.game.coins,
      title: context.l10n.rewardInviter,
    );
  }

  /// Подарок дня не забран — окно «Сегодня» открывается само, один раз за
  /// запуск (миграция 0017).
  static bool _dailyShown = false;

  Future<void> _maybeShowDaily() async {
    if (_dailyShown || !widget.game.daily.giftAvailable) return;
    _dailyShown = true;
    await showDailySheet(context, widget.game);
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _activity.dispose();
    _closeGap.dispose();
    _hungerTimer?.cancel();
    _lifeTimer?.cancel();
    _life
      ..removeListener(_onLife)
      ..dispose();
    _eaten
      ..removeListener(_onEatenChanged)
      ..dispose();
    _dishArc.dispose();
    _recipeArc.dispose();
    _fx.dispose();
    _faceCue.dispose();
    super.dispose();
  }

  void _refreshEaten() => _eaten.refresh(food: widget.controller.stats.food);

  /// Состав стола поменялся: перед мишкой остаётся то же блюдо, а если его
  /// съели — следующее за ним.
  void _onEatenChanged() {
    final before = _table;
    final after = [
      for (final dish in FoodCatalog.dishes)
        if (!_eaten.isEaten(dish.id)) dish,
    ];
    if (after.length == before.length) return;
    var current = 0;
    if (before.isNotEmpty && after.isNotEmpty) {
      final at = _dishArc.current.clamp(0, before.length - 1);
      for (var k = 0; k < before.length; k++) {
        final index = after.indexOf(before[(at + k) % before.length]);
        if (index >= 0) {
          current = index;
          break;
        }
      }
    }
    // Съели блюдо перед мишкой — на его месте пусто, и блюда справа
    // плавно съезжают туда (заказчик 24.09: «происходит сдвиг блюд»).
    final eatenCenter =
        after.length < before.length &&
        before.isNotEmpty &&
        _eaten.isEaten(before[_dishArc.current.clamp(0, before.length - 1)].id);
    setState(() {
      _table = after;
      _dishArc.reset(count: after.length, current: current);
    });
    if (eatenCenter && _dishesShown && after.isNotEmpty) {
      _dishArc.gap = 1;
      _closeGap.forward(from: 0);
    }
  }

  /// Сдвиг блюд на место съеденного — плавно, с торможением, в тон
  /// доводке после свайпа. Создаётся сразу в initState.
  late final AnimationController _closeGap;

  /// Вход на кухню — перед мишкой паста (или первое, что осталось).
  void _resetArc() {
    final pasta = _table.indexWhere((d) => d.id == 'pasta');
    _dishArc.reset(count: _table.length, current: pasta < 0 ? 0 : pasta);
  }

  void _toggleDishes() {
    if (!_dishesShown) {
      _refreshEaten();
      if (_table.isEmpty) {
        _soon(context.l10n.dishesAllEaten);
        return;
      }
    }
    setState(() {
      _dishesShown = !_dishesShown;
      // На столе что-то одно: готовые блюда или готовка.
      if (_dishesShown) {
        // Мишка просит одно из любимых блюд — каждый раз случайное (КП 8.1,
        // 7.4; заказчик 01.10).
        _craving = pickCraving(
          widget.controller.state.trait,
          _random,
          available: [for (final d in _table) d.id],
        );
        _recipesShown = false;
        _cooking = null;
        _dropCookPending();
      }
    });
  }

  /// «Приготовить»: рецепты выезжают на стол; ещё раз — убираются. Если
  /// уже готовится — готовка бросается.
  void _toggleRecipes() {
    setState(() {
      if (_cooking != null) {
        _cooking = null;
        _recipesShown = false;
        _dropCookPending();
        return;
      }
      _recipesShown = !_recipesShown;
      if (_recipesShown) _dishesShown = false;
    });
  }

  /// Крестик под табло рецептов.
  void _hideRecipes() => setState(() => _recipesShown = false);

  /// Нажали на рецепт перед мишкой — стол пустеет, под столом продукты.
  void _startCooking(Recipe recipe) {
    setState(() {
      _recipesShown = false;
      _cooking = recipe;
      _cookRun++;
    });
  }

  /// Крестик во время готовки — бросить её.
  void _stopCooking() => setState(() {
    _cooking = null;
    _dropCookPending();
  });

  /// Положили не тот продукт — мишка мотает головой.
  void _wrongIngredient() => setState(() => _refusals++);

  /// Всё собрано, блюдо появилось на столе: награда и еда — те же, что
  /// у готовки в листе кормления (КП 8.5). На экране они появятся, когда
  /// мишка доест и пузырь ударит в кружок «Еда».
  void _cooked(Recipe recipe) {
    _holdStats();
    widget.game.completeRecipe(recipe);
    _cookPending = recipe;
  }

  /// Мишка доел приготовленное — тарелка тает, вылетает пузырь.
  void _cookEaten(Recipe recipe) {
    if (_cookPending == null) return;
    _cookPending = null;
    _fx.launch(
      FeedLaunch(
        origin: _plateSpot(recipe.id),
        gain: recipe.foodGain.round(),
        coins: recipe.reward,
      ),
    );
  }

  /// Блюдо стоит перед мишкой — он ест. Любимое блюдо характера нежит.
  void _serveCooked(Recipe recipe) {
    final dish = recipe.id == 'fruit_salad' ? 'fruit' : recipe.id;
    final favourite = isFavouriteDish(widget.controller.state.trait, dish);
    setState(
      () => _meal = KitchenMeal(
        id: ++_meals,
        mood: favourite ? KitchenMood.love : KitchenMood.happy,
      ),
    );
  }

  /// Мишка доел, тарелка ушла.
  void _finishCooking() => setState(() {
    _cooking = null;
    _dropCookPending();
  });

  /// Крестик под табло — блюда уходят со стола.
  void _hideDishes() => setState(() => _dishesShown = false);

  /// Блюдо перед мишкой: нажали — мишка сразу ест. Окна подтверждения на
  /// кухне нет (заказчик 24.09: «в комнате еда убираем подтверждение —
  /// сразу он кушает»; само нажатие на блюдо и есть выбор). Монеты
  /// списываются, блюда уходят со стола, мишка ест и показывает эмоцию —
  /// любимое блюдо его характера нежит, остальное радует.
  void _buyDish(Dish dish) {
    final l10n = context.l10n;
    final food = widget.controller.stats.food;
    final coins = widget.game.profile.coins;
    if (!widget.game.feedWithDish(dish)) {
      _soon(l10n.feedNotEnoughCoins);
      return;
    }
    // Тарелка уходит со стола — на её месте рождается пузырь с «+N». Числа
    // наверху сменятся, когда он ударит в кружок «Еда» (заказчик 24.09).
    _fx.hold(food: food, coins: coins);
    _fx.launch(
      FeedLaunch(
        origin: _plateSpot(dish.id),
        gain: dish.foodGain.round(),
        coins: -dish.price,
      ),
    );
    // Съеденное уходит со стола до следующего голода (заказчик 24.09),
    // остальные сдвигаются на его место.
    _eaten.eat(dish.id);
    final favourite = isFavouriteDish(widget.controller.state.trait, dish.id);
    // Стол закрывается, только когда мишка наелся — шкала «Еда» полна; или
    // когда блюд не осталось. Иначе можно сразу выбрать следующее.
    final full = widget.controller.stats.food >= 99.5;
    setState(() {
      if (full || _table.isEmpty) _dishesShown = false;
      _meal = KitchenMeal(
        id: ++_meals,
        mood: favourite ? KitchenMood.love : KitchenMood.happy,
      );
    });
  }

  /// Поглаживания (КП 7.6): показатель любви растёт, а мишка на кухне
  /// отзывается на руку. Счётчик — чтобы сцена увидела каждое касание.
  int _pets = 0;

  void _petBear() {
    widget.controller.petBear();
    setState(() => _pets++);
  }

  /// Открыть кормление с кухни, на нужной вкладке (КП 8.1). Лист
  /// возвращает настроение после еды — и сцена кухни играет её.
  Future<void> _openFeed(FeedTab tab) async {
    final mood = await _openSheet<KitchenMood>(
      FeedScreen(
        controller: widget.controller,
        game: widget.game,
        initialTab: tab,
      ),
    );
    if (mood == null || !mounted) return;
    setState(() => _meal = KitchenMeal(id: ++_meals, mood: mood));
  }

  void _notImplemented(BearAction action) =>
      showTopToast(context, context.l10n.homeScreenNotReady(action.name));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.game]),
      builder: (context, _) {
        final state = widget.controller.state;
        final profile = widget.game.profile;
        final age = widget.calendar.ageAt(profile.birthAt);

        return Scaffold(
          // Комната занимает весь телефон, включая полосу под нижним меню
          // (решение заказчика 20.09). Шапка и показатели лежат поверх неё
          // отдельными слоями, а не делят с ней высоту колонкой.
          extendBody: true,
          // Любое касание экрана — «человек здесь»: кольца показателей не
          // сворачиваются, пока им пользуются (заказчик 10.10). Слушатель
          // касания не забирает — оно идёт дальше, куда шло.
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _activity.ping(),
            // StackFit.expand обязателен: слой управления — колонка по высоте
            // содержимого, и без него стек сжался бы до её высоты, а комната
            // вместе с ним.
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _RoomScene(
                    controller: widget.controller,
                    mood: _life.mood,
                    forgotten: _life.forgotten,
                    showBubble: _showSpeechBubble,
                    language: widget.language,
                    onAcceptInitiative: _runAction,
                    riveAssetPath: widget.riveAssetPath,
                    game: widget.game,
                    onSlotTap: _furnishing ? _useSlot : _openSlotSheet,
                    furnishing: _furnishing,
                    slotHints: _furnishing && !_surfaceTab,
                    furnishBarHeight: _furnishing && !_surfaceTab
                        ? _furnishBarHeight
                        : 0,
                    picked: _picked,
                    surfacePreview: _surfacePreview,
                    room: _room,
                    onRoomChanged: _showRoom,
                    asleep: _asleep,
                    meal: _meal,
                    pets: _pets,
                    onPet: _petBear,
                    onPutToBed: _putToBed,
                    onWake: _wake,
                    alarm: _alarm,
                    onPickAlarm: _pickAlarm,
                    onOpenFeed: _openFeed,
                    dishesShown: _dishesShown,
                    craving: _craving,
                    dishArc: _dishArc,
                    dishes: _table,
                    onToggleDishes: _toggleDishes,
                    onHideDishes: _hideDishes,
                    onBuyDish: _buyDish,
                    recipesShown: _recipesShown,
                    recipeArc: _recipeArc,
                    cooking: _cooking,
                    cookRun: _cookRun,
                    refusals: _refusals,
                    onToggleRecipes: _toggleRecipes,
                    onHideRecipes: _hideRecipes,
                    onStartCooking: _startCooking,
                    cookCallbacks: (
                      onClose: _stopCooking,
                      onWrong: _wrongIngredient,
                      onCooked: _cooked,
                      onServe: _serveCooked,
                      onEaten: _cookEaten,
                      onFinished: _finishCooking,
                    ),
                    onWash: _wash,
                    onToilet: _toilet,
                    onBottle: _bottle,
                    onDiaper: _diaper,
                    faceCue: _faceCue,
                    onOpenCare: () => _open(
                      CareScreen(
                        controller: widget.controller,
                        onOpenFeed: () => _openSheet(
                          FeedScreen(
                            controller: widget.controller,
                            game: widget.game,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Слой управления: шапка и кольца показателей вверху, над
                // потолком. Пустота под ними касания не ловит — погладить
                // мишку можно прямо через неё.
                //
                // В режиме обустройства его не видно: комната должна быть
                // видна целиком, иначе не разглядеть, что получается.
                if (!_furnishing)
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.pagePadding,
                            ),
                            child: PetHeader(
                              profile: profile,
                              age: age,
                              fx: _fx,
                              onOpenProfile: () => _openGlass(_profileScreen()),
                              onShare: () => showShareCard(
                                context,
                                game: widget.game,
                                stage: state.stage,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Во всю ширину: свёрнутый круг уезжает к самому краю
                          // экрана «язычком» и должен нажиматься и там.
                          CareStatsPanel(
                            stats: state.stats,
                            stage: state.stage,
                            onAction: _runAction,
                            fx: _fx,
                            activity: _activity,
                            edgePadding: AppDimens.pagePadding,
                          ),
                          const SizedBox(height: 10),
                          // Реплика идёт следом за кольцами в одной колонке, а
                          // не висит на своей высоте поверх них. Раньше высота
                          // была числом (178), а подписи колец занимают разное
                          // место: на телефоне с высоким вырезом пузырь ложился
                          // прямо на «Еда» и «Гигиена» — заказчик 20.09: «здесь
                          // у нас идут наложения, это никак не катит».
                          //
                          // Справа оставлено место под кнопку профиля и лапу.
                          //
                          // В спальне реплики нет вовсе: заказчик 22.09 — «во
                          // время сна они не должны присутствовать, убрать с
                          // комнаты сон». Нужна ли она там потом и в каком
                          // виде — решение отдельное.
                          //
                          // Заказчик 26.09: реплику пока убрать из всех
                          // комнат — вернём, когда решим, с какой логикой.
                          // С 27.09 пузырь — над головой мишки, в сцене
                          // (`_RoomScene`), не здесь.
                        ],
                      ),
                    ),
                  ),
                // Пузырь сытости летит над комнатой и кольцами. Касаний не
                // ловит.
                Positioned.fill(
                  child: IgnorePointer(
                    child: FeedBurstLayer(
                      fx: _fx,
                      liveFood: () => widget.controller.stats.food,
                      liveCoins: () => widget.game.profile.coins,
                    ),
                  ),
                ),
                // Разделы. Лежат выше всего: разлетевшиеся кружки должны
                // перекрывать и комнату, и кольца показателей.
                if (!_furnishing)
                  PawMenu(stage: state.stage, onSelected: _openSection),
                if (_furnishing)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _HeightReport(
                      onHeight: (h) {
                        if ((h - _furnishBarHeight).abs() < 0.5) return;
                        setState(() => _furnishBarHeight = h);
                      },
                      child: FurnishBar(
                        game: widget.game,
                        room: _room,
                        picked: _picked,
                        onPick: (item) => setState(() => _picked = item),
                        onSurface: _pickSurface,
                        onSurfaceTab: (on) => setState(() => _surfaceTab = on),
                        onShop: () {
                          _stopFurnishing();
                          _openShop();
                        },
                        onDone: _stopFurnishing,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Дев-панель уехала влево: справа внизу теперь лапа.
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: _furnishing || widget.onOpenDevPanel == null
              ? null
              : FloatingActionButton.small(
                  onPressed: () => widget.onOpenDevPanel!(context),
                  tooltip: context.l10n.homeDevPanelTooltip,
                  child: const Icon(Icons.tune),
                ),
        );
      },
    );
  }
}

/// Сообщает высоту ребёнка после раскладки — для ленты обустройства.
class _HeightReport extends SingleChildRenderObjectWidget {
  const _HeightReport({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReport(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReport renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReport extends RenderProxyBox {
  _RenderHeightReport(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // Не посреди раскладки: setState сейчас запрещён.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}

/// Касание где угодно на главном экране — сигнал «человек здесь».
class _Activity extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Характер для кухни. Заглушка `kTestKitchenTrait` — снять любую
/// реакцию на угощение без смены характера.
BearTrait _kitchenTrait(BearTrait trait) {
  final forced = BearTrait.values.where((t) => t.name == kTestKitchenTrait);
  return forced.isNotEmpty ? forced.first : trait;
}

class _RoomScene extends StatelessWidget {
  const _RoomScene({
    required this.controller,
    required this.mood,
    required this.forgotten,
    required this.showBubble,
    required this.language,
    required this.onAcceptInitiative,
    required this.riveAssetPath,
    required this.onOpenCare,
    required this.game,
    required this.onSlotTap,
    required this.furnishing,
    required this.slotHints,
    this.furnishBarHeight = 0,
    required this.picked,
    this.surfacePreview,
    required this.room,
    required this.onRoomChanged,
    required this.asleep,
    required this.meal,
    required this.pets,
    required this.onPet,
    required this.onPutToBed,
    required this.onWake,
    required this.alarm,
    required this.onPickAlarm,
    required this.onOpenFeed,
    required this.dishesShown,
    this.craving,
    required this.dishArc,
    required this.dishes,
    required this.onToggleDishes,
    required this.onHideDishes,
    required this.onBuyDish,
    required this.recipesShown,
    required this.recipeArc,
    required this.cooking,
    required this.cookRun,
    required this.refusals,
    required this.onToggleRecipes,
    required this.onHideRecipes,
    required this.onStartCooking,
    required this.cookCallbacks,
    required this.onWash,
    required this.onToilet,
    required this.onBottle,
    required this.onDiaper,
    required this.faceCue,
  });

  final BearController controller;

  /// Состояние покоя мишки по показателям (`BearLife`).
  final BearMood mood;

  /// Нужда ниже 15 — «Ты про меня забыл?».
  final bool forgotten;

  /// Облачко-реплика слева от мишки (заказчик 27.09, место — 10.10).
  final bool showBubble;
  final BearLanguage language;
  final ValueChanged<BearAction> onAcceptInitiative;
  final String riveAssetPath;

  /// Обстановка комнаты и кошелёк: сцена показывает, что где стоит.
  final GameState game;

  /// Тап по месту — занятому или свободному.
  final ValueChanged<RoomSlot> onSlotTap;

  /// Идёт ли обустройство: тогда свободные места подсвечены, а занятые
  /// отдают вещь обратно по тапу.
  final bool furnishing;

  /// Подсвечивать ли места крестиками: в обустройстве, но не на вкладках
  /// «Стены» и «Пол».
  final bool slotHints;

  /// Высота ленты обустройства внизу экрана; 0 — ленты нет. Комната
  /// приподнимается над ней ровно настолько, чтобы места, куда встанет вещь
  /// в руках, вышли из-под ленты ([furnishLift]).
  final double furnishBarHeight;

  /// Вещь в руках: подсвечиваются только те места, куда она встанет.
  final ShopItem? picked;

  /// Стены или пол, которые примеряют до покупки (лента «Стены» / «Пол»).
  final ShopItem? surfacePreview;

  /// Какая комната показана и что делать при переключении.
  final RoomKind room;
  final ValueChanged<RoomKind> onRoomChanged;

  /// Спит ли мишка, как уложить и как разбудить: кнопки на ковре спальни.
  final bool asleep;
  final VoidCallback onPutToBed;

  /// Последнее кормление — мишка на кухне ест и показывает эмоцию.
  final KitchenMeal? meal;

  /// Сколько раз погладили и что делать при поглаживании: на кухне мишка
  /// отзывается на руку (`act_pet`).
  final int pets;
  final VoidCallback onPet;
  final VoidCallback onWake;

  /// Будильник «проснёмся вместе»: на какое время стоит и как поменять.
  final TimeOfDay? alarm;
  final VoidCallback onPickAlarm;

  /// Открыть кормление с кухни на выбранной вкладке.
  final ValueChanged<FeedTab> onOpenFeed;

  /// Готовые блюда на столе: показаны ли, как открыть и убрать, что делать
  /// при покупке блюда перед мишкой.
  final bool dishesShown;

  /// Любимое блюдо, которое мишка просит (КП 8.1, 7.4).
  final String? craving;
  final DishArc dishArc;

  /// Блюда на столе — без съеденных.
  final List<Dish> dishes;
  final VoidCallback onToggleDishes;

  /// Крестик под табло.
  final VoidCallback onHideDishes;
  final ValueChanged<Dish> onBuyDish;

  /// «Приготовить» (вариант A, заказчик 24.09): рецепты на той же дуге
  /// стола, что и готовые блюда; выбрали — стол пустеет, продукты под
  /// столом ([KitchenCooking]). [cookRun] — номер готовки, [refusals] —
  /// сколько раз мишка мотал головой.
  final bool recipesShown;
  final DishArc recipeArc;
  final Recipe? cooking;
  final int cookRun;
  final int refusals;
  final VoidCallback onToggleRecipes;
  final VoidCallback onHideRecipes;
  final ValueChanged<Recipe> onStartCooking;
  final CookCallbacks cookCallbacks;

  /// Купание и горшок. Механики пока нет — кнопки честно об этом говорят.
  final VoidCallback onWash;
  final VoidCallback onToilet;

  /// Новорождённый (КП 5): бутылочка на кухне и подгузник в ванной вместо
  /// горшка. ⚠ Ждут анимации — пока честное «скоро», как у душа.
  final VoidCallback onBottle;
  final VoidCallback onDiaper;

  /// Выражения лица мишки-проверки в игровой.
  final BearFaceCue faceCue;

  /// Открыть список действий ухода (КП 6.4). На макете это отдельный экран
  /// «Что будем делать?», но кнопки, ведущей туда, в макете не видно —
  /// ДОПУЩЕНИЕ: ставим её в угол комнаты.
  final VoidCallback onOpenCare;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final frame = RoomFrame.of(Size(c.maxWidth, c.maxHeight), room);
        final held = picked;
        final lift = furnishBarHeight <= 0
            ? 0.0
            : furnishLift(
                game: game,
                slots: [
                  for (final slot in slotsOf(room))
                    if (held == null || slot.takes(held)) slot,
                ],
                frame: frame.rect,
                barTop: c.maxHeight - furnishBarHeight,
                topInset: MediaQuery.paddingOf(context).top,
              );
        return ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: lift),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, dy, child) =>
                Transform.translate(offset: Offset(0, -dy), child: child),
            child: _build(context, frame),
          ),
        );
      },
    );
  }

  Widget _build(BuildContext context, RoomFrame frame) {
    final newborn = controller.state.stage == BearStage.newborn;
    return Stack(
      children: [
        // Потолок — всё, что выше кадра комнаты. Рисуется кодом, пока нет
        // арта, и сходится в ту же точку, что и доски пола на картинке.
        if (frame.ceilingHeight > 0)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: frame.ceilingHeight,
            child: RoomCeiling(
              room: room,
              vanishingY: frame.vanishingY,
              centerX: frame.centerX,
            ),
          ),
        // Кадр комнаты: фон прижат к низу, чтобы пол доходил до края
        // экрана.
        Positioned.fromRect(
          rect: frame.rect,
          child: RoomSceneBackdrop(room: room),
        ),
        // Игровая: выбранные стены и пол — слои поверх картинки (09.10).
        if (room == RoomKind.nursery)
          Positioned.fromRect(
            rect: frame.rect,
            child: RoomSurfaces(game: game, preview: surfacePreview),
          ),
        // Спальня живая: мишка лежит отдельным слоем поверх комнаты, дышит
        // и моргает, а передний край одеяла и свет ночника идут над ним.
        // Буквы z рисуются последними — они выше всего, в просвете стены.
        // Кухня живая так же: мишка за столом собран из частей, дышит,
        // моргает, ест и радуется. Голоден — иногда грустит (ТЗ:
        // `idle_hungry`).
        // Спит — на кухне его нет (заказчик 26.09: он в спальне); разбудили
        // — плавно появляется за столом.
        if (room == RoomKind.bedroom) ...[
          // Окно живёт под мишкой: луна и звёзды мерцают, звёзды падают.
          Positioned.fromRect(rect: frame.rect, child: const NightWindow()),
          Positioned.fromRect(
            rect: frame.rect,
            child: BedroomScene(asleep: asleep),
          ),
          // Буквы z и облако мыслей ждут одного момента: мишку уложили и
          // он закрыл глаза.
          Positioned.fromRect(
            rect: frame.rect,
            child: SleepZzz(shown: asleep),
          ),
          Positioned.fromRect(
            rect: frame.rect,
            child: SleepThought(shown: asleep),
          ),
          // Секунды до сна — на одеяле, пока мишка засыпает (заказчик 25.09).
          Positioned.fromRect(
            rect: frame.rect,
            child: SleepCountdown(shown: asleep),
          ),
        ],
        // Погладить (КП 7.6) ловится самым нижним слоем, а не самим
        // мишкой. Мишка лежит между двумя слоями мест, и будь тап на нём —
        // он перехватывал бы касания по дальним вещам, которые рисуются
        // под ним. Внизу же он проигрывает всему, что выше: сначала вещи,
        // и только если тапнули мимо — поглаживание.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPet,
          ),
        ),
        // Мишка на кухне — над слоем «погладить», чтобы палец доходил до
        // него самого: тап — реакция на касание, ведёт по голове — ласка,
        // по животу — щекотка (заказчик 27.09: «включи поглаживание на
        // кухне»). Рисуется он по-прежнему под местами и блюдами.
        // ⚠ Пока спрятан ([_kitchenBearShown]).
        if (room == RoomKind.kitchen && _kitchenBearShown)
          Positioned.fromRect(
            rect: frame.rect,
            child: IgnorePointer(
              ignoring: asleep,
              child: AnimatedOpacity(
                opacity: asleep ? 0 : 1,
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOut,
                // С 27.09 на кухне тот же анимированный мишка, что в
                // игровой (заказчик: «переноси мишку на кухню»; ножки под
                // столом убраны — наши скрыты скатертью).
                child: KitchenBear(
                  cue: faceCue,
                  mood: mood,
                  trait: _kitchenTrait(controller.state.trait),
                  meal: meal,
                  pet: pets,
                  refuse: refusals,
                  onTap: controller.petBear,
                ),
              ),
            ),
          ),
        // Дальние места — под мишкой: он стоит на трети глубины комнаты,
        // и кроватка у задней стены должна быть за ним, а не поперёк него.
        // Оба слоя мест лежат ровно в кадре комнаты: их координаты —
        // доли кадра, а не экрана.
        Positioned.fromRect(
          rect: frame.rect,
          child: RoomSlotLayer(
            game: game,
            room: room,
            depth: SlotDepth.behind,
            hint: slotHints,
            picked: picked,
            onTapItem: (slot, _) => onSlotTap(slot),
            onTapEmpty: onSlotTap,
          ),
        ),
        // Герой стоит на линии пола комнаты и занимает свою долю её кадра.
        // Касания не ловит — их ловит слой под ним.
        //
        // Рисуется полосами: в кухне стол идёт от края до края, и мишка
        // сидит за ним — видны голова с плечами над столешницей и лапы в
        // просвете под скатертью, а сам стол проходит между ними. Мебель
        // нарисована на фоне, то есть лежит под мишкой, и без этого его
        // ноги оказались бы поверх столешницы.
        //
        // Заказчик 24.09: «убрать мишку с главного, где комната игра, и в
        // душевой; во сне и на кухне оставляем». Там мишка — часть живой
        // сцены (KitchenScene, BedroomScene), здесь же был бы временный
        // демонстрационный, поэтому в игровой и душевой его пока нет.
        if ((room == RoomKind.kitchen && !asleep) || room == RoomKind.bedroom)
          for (final slice in frame.bearSlices)
            Positioned(
              left: frame.bearCenterX - frame.rect.width / 2,
              top: slice.top,
              width: frame.rect.width,
              height: slice.bottom - slice.top,
              child: IgnorePointer(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: frame.bearHeight,
                    maxHeight: frame.bearHeight,
                    child: Transform.translate(
                      // Полоса показывает свой кусок одного и того же тела:
                      // смещаем его так, чтобы в окне оказалась именно эта
                      // часть, а не начало снова и снова.
                      offset: Offset(0, frame.bearTop - slice.top),
                      child: BearView(
                        controller: controller,
                        assetPath: riveAssetPath,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        // ⚠ Проверка файла аниматора (заказчик 26.09: «ставь в игровую на
        // проверку»): мишка из bear_boy_v2.riv — живой покой, касания —
        // выражения по кругу, «Игра» — смех.
        // Не финальный: действий ухода в файле нет.
        if (room == RoomKind.nursery && !asleep && !furnishing)
          Positioned(
            left: frame.bearCenterX - frame.bearHeight * 0.6,
            top: frame.bearTop,
            width: frame.bearHeight * 1.2,
            height: frame.bearHeight,
            // Без приветственной эмоции при входе (заказчик 26.09): мишка
            // просто стоит и дышит.
            child: RiveBearTrial(
              cue: faceCue,
              trait: controller.state.trait,
              mood: mood,
              onTap: controller.petBear,
            ),
          ),
        // Облачко-реплика слева от мишки, у окна, на уровне головы
        // (заказчик 10.10): над головой оно закрывало картины на стене.
        if (showBubble && room == RoomKind.nursery && !asleep && !furnishing)
          _bubble(context, frame),
        // Ближние места — поверх мишки. Слой занимает только площадь мест,
        // остальное прозрачно для касаний: погладить мишку по-прежнему
        // можно где угодно.
        Positioned.fromRect(
          rect: frame.rect,
          child: RoomSlotLayer(
            game: game,
            room: room,
            hint: slotHints,
            picked: picked,
            onTapItem: (slot, _) => onSlotTap(slot),
            onTapEmpty: onSlotTap,
          ),
        ),
        // Действия стоят в самой комнате, а не открываются поверх неё:
        // решение заказчика 20.09. На кухне это выбор еды, в ванной — что
        // именно делаем с гигиеной.
        // Справа оставлено место под лапу: она круглая, стоит в углу и
        // занимает 86 пикселей от края. Раньше здесь было 100, и кнопка
        // «Приготовить» подходила к ней вплотную — заказчик 20.09 прочитал
        // это как наложение.
        // Готовые блюда дугой на столе (заказчик 24.09): появляются и
        // уходят по кнопке «Готовые блюда». Лежат поверх мишки целиком:
        // на лету блюдо может пройти по нему, но ничем не срезается
        // (заказчик 24.09: «никаких масок»). Касания ловятся в полосе
        // стола — мимо неё мишку по-прежнему можно погладить.
        if (room == RoomKind.kitchen)
          Positioned.fromRect(
            rect: frame.rect,
            child: AnimatedOpacity(
              opacity: dishesShown ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              child: DishPlates(
                arc: dishArc,
                dishes: dishes,
                shown: dishesShown,
                // Блюдо, которое мишка просит, — с сердечком на табло.
                board: (l10n, dish) =>
                    dishBoard(l10n, dish, favourite: craving),
              ),
            ),
          ),
        if (room == RoomKind.kitchen && dishesShown)
          Positioned.fromRect(
            rect: frame.rect,
            child: DishCarousel(
              arc: dishArc,
              dishes: dishes,
              spinTo: craving,
              onBuy: onBuyDish,
              onTapElsewhere: onPet,
              onClose: onHideDishes,
            ),
          ),
        // Рецепты — на той же дуге стола, что готовые блюда; нажали на
        // рецепт перед мишкой — начинается готовка.
        if (room == RoomKind.kitchen && recipesShown) ...[
          Positioned.fromRect(
            rect: frame.rect,
            child: DishPlates<Recipe>(
              arc: recipeArc,
              dishes: FoodCatalog.recipes,
              board: recipeBoard,
              tag: 'recipe',
            ),
          ),
          Positioned.fromRect(
            rect: frame.rect,
            child: DishCarousel<Recipe>(
              arc: recipeArc,
              dishes: FoodCatalog.recipes,
              onBuy: onStartCooking,
              onTapElsewhere: onPet,
              onClose: onHideRecipes,
              closeLabel: context.l10n.cookClose,
              tag: 'recipe',
            ),
          ),
        ],
        // Готовка: стол пустой, продукты под столом, блюдо появится на
        // столе, когда всё собрано.
        if (room == RoomKind.kitchen && cooking != null)
          Positioned.fill(
            child: KitchenCooking(
              key: ValueKey('cook-$cookRun'),
              frame: frame.rect,
              recipe: cooking!,
              onClose: cookCallbacks.onClose,
              onWrong: cookCallbacks.onWrong,
              onCooked: cookCallbacks.onCooked,
              onServe: cookCallbacks.onServe,
              onEaten: cookCallbacks.onEaten,
              onFinished: cookCallbacks.onFinished,
            ),
          ),
        // Подсказка от характера (КП 8.1) — над кнопками, пока на столе
        // готовые блюда: какое из любимых мишке сейчас хочется.
        if (room == RoomKind.kitchen && !asleep && !newborn)
          Positioned(
            left: 16,
            right: _pawSpace,
            bottom: 34 + 44 + 12,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: switch (dishesShown ? craving : null) {
                  final dish? => _KitchenHint(
                    key: ValueKey('kitchen-hint-$dish'),
                    text:
                        cravingText(
                          context.l10n,
                          controller.state.trait,
                          dish,
                        ) ??
                        '',
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        if (room == RoomKind.kitchen && !asleep)
          Positioned(
            left: 16,
            right: _pawSpace,
            bottom: 34,
            child: _KitchenMenu(
              onBottle: newborn ? onBottle : null,
              dishesShown: dishesShown,
              onToggleDishes: onToggleDishes,
              cookShown: recipesShown || cooking != null,
              onToggleCook: onToggleRecipes,
            ),
          ),
        // В спальне — «Уложить спать» на ковре, там, где заказчик 22.09
        // обвёл на скрине. Когда уснул, на её месте — «Разбудить», а выше
        // над ней «Давай проснёмся вместе»: на какое время будильник.
        if (room == RoomKind.bedroom)
          Positioned(
            left: 16,
            right: _pawSpace,
            bottom: 34,
            child: _BedroomMenu(
              asleep: asleep,
              onPutToBed: onPutToBed,
              onWake: onWake,
            ),
          ),
        if (room == RoomKind.bedroom && asleep)
          Positioned(
            left: 16,
            right: _pawSpace,
            bottom: 34 + 44 + 12,
            child: _WakeMenu(alarm: alarm, onPickAlarm: onPickAlarm),
          ),
        if (room == RoomKind.bath && !asleep)
          Positioned(
            left: 16,
            right: _pawSpace,
            bottom: 34,
            child: _BathMenu(
              onWash: onWash,
              onToilet: onToilet,
              onDiaper: newborn ? onDiaper : null,
            ),
          ),
        // ⚠ Проверка показателей живого мишки — снять перед публикацией.
        // Одной строкой над лентой эмоций, под ногами мишки (заказчик
        // 10.10: столбиком справа закрывала шкаф и полку).
        if (room == RoomKind.nursery && !asleep && !furnishing)
          Positioned(
            left: 12,
            right: 12,
            bottom: _stripBottom + EmotionTestStrip.height + 6,
            child: Center(child: StatsTestPanel(controller: controller)),
          ),
        // ⚠ Проверочная лента всех 33 эмоций под мишкой — снять перед
        // публикацией (заказчик 30.09: пронумеровать, подписать, листать
        // влево-вправо — для заказчицы). Стоит над лапой в углу.
        if (room == RoomKind.nursery && !asleep && !furnishing)
          Positioned(
            left: 0,
            right: 0,
            bottom: _stripBottom,
            child: EmotionTestStrip(cue: faceCue),
          ),
        // Мишка спит, а мы в другой комнате (заказчик 26.09): посередине —
        // «Мишка спит»: разбудить и позвать сюда или оставить спать.
        if (asleep && room != RoomKind.bedroom && !furnishing)
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, 0.15),
              child: SleepingElsewhere(
                room: room,
                sleep: controller.stats.sleep,
                onWake: onWake,
                onLetSleep: () => onRoomChanged(RoomKind.bedroom),
              ),
            ),
          ),
      ],
    );
  }

  /// Облачко-реплика: слева от капюшона, между низом картин и спинкой
  /// кресла, правым краем к голове, хвостик — к уху.
  ///
  /// Меры — доли роста мишки от его макушки и середины, снятые с силуэта
  /// мишки в игровой: у макушки капюшон узкий (до 0,11 роста от середины
  /// на высоте облачка), у ушей — 0,19, у щёк — 0,22. Картины кончаются
  /// чуть выше макушки, спинка кресла начинается на четверти роста.
  /// Поэтому на любом экране облачко встаёт на то же место относительно
  /// головы и не залезает ни на картины, ни на кресло, ни на кольца и
  /// кнопки.
  Widget _bubble(BuildContext context, RoomFrame frame) {
    final h = frame.bearHeight;
    final left = MediaQuery.paddingOf(context).left + 8;
    final right = frame.bearCenterX - 0.14 * h;
    final top = frame.bearTop + 0.035 * h;
    final width = math.max(96.0, right - left);
    // Хвостик — от правого верхнего угла облачка к левому боку капюшона,
    // на уровне ушей.
    final tail = Offset(
      frame.bearCenterX - 0.195 * h - (left + width),
      frame.bearTop + 0.24 * h - top,
    );
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Align(
        alignment: Alignment.topRight,
        child: PetSpeechBubble(
          mood: mood,
          forgotten: forgotten,
          initiative: controller.initiative,
          language: language,
          onTap: onAcceptInitiative,
          tailTo: tail,
        ),
      ),
    );
  }

  /// Сколько места вдоль правого края держим свободным под лапу.
  static const double _pawSpace = 112;

  /// Низ проверочной ленты эмоций: над лапой в правом нижнем углу.
  static const double _stripBottom = 102;

  /// ⚠ Мишка на кухне спрятан (заказчик 30.09: «пока не показываем, пока
  /// не отработаем игровую комнату»). Кухня работает как прежде — блюда,
  /// готовка, «+35» к еде; вернуть мишку — поставить `true`.
  static const bool _kitchenBearShown = false;
}

/// Ряд кнопок комнаты вдоль нижнего края.
///
/// Кнопки стоят в строку, как на макете, и вместе уменьшаются, если в
/// отведённую полосу не помещаются: справа в углу лапа, и подходить к ней
/// вплотную нельзя — заказчик 20.09 прочитал это как наложение. Перенос на
/// вторую строку здесь хуже уменьшения: ряд тогда лезет вверх на мишку.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Кнопка спальни: уложить спать — или, если уже спит, разбудить.
class _BedroomMenu extends StatelessWidget {
  const _BedroomMenu({
    required this.asleep,
    required this.onPutToBed,
    required this.onWake,
  });

  final bool asleep;
  final VoidCallback onPutToBed;
  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ActionRow(
      children: [
        if (asleep)
          _Pill(
            label: l10n.bedroomActionWake,
            icon: Icons.wb_sunny_outlined,
            onTap: onWake,
          )
        else
          _Pill(
            label: l10n.bedroomActionSleep,
            icon: Icons.bedtime_outlined,
            onTap: onPutToBed,
          ),
      ],
    );
  }
}

/// Две кнопки ванной: искупаться и на горшок.
class _BathMenu extends StatelessWidget {
  const _BathMenu({
    required this.onWash,
    required this.onToilet,
    this.onDiaper,
  });

  final VoidCallback onWash;
  final VoidCallback onToilet;

  /// Новорождённому — подгузник вместо горшка (КП 5). `null` — горшок.
  final VoidCallback? onDiaper;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return _ActionRow(
      children: [
        _Pill(
          label: l10n.bathActionWash,
          icon: Icons.bathtub_outlined,
          onTap: onWash,
        ),
        const SizedBox(width: 8),
        if (onDiaper case final diaper?)
          _Pill(
            key: const ValueKey('bath-diaper'),
            label: l10n.bathActionDiaper,
            icon: Icons.baby_changing_station_outlined,
            onTap: diaper,
          )
        else
          _Pill(
            label: l10n.bathActionToilet,
            icon: Icons.wc_outlined,
            onTap: onToilet,
          ),
      ],
    );
  }
}

/// Кнопка уснувшей спальни: «Давай проснёмся вместе» — на какое время
/// поставить будильник. Две строки: приглашение и вопрос; когда время
/// выбрано, вместо вопроса — оно само, а тап меняет его.
class _WakeMenu extends StatelessWidget {
  const _WakeMenu({required this.alarm, required this.onPickAlarm});

  final TimeOfDay? alarm;
  final VoidCallback onPickAlarm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final alarm = this.alarm;
    final second = alarm == null
        ? l10n.bedroomAlarmQuestion
        : l10n.bedroomAlarmSet(
            MaterialLocalizations.of(context).formatTimeOfDay(alarm),
          );

    return _ActionRow(
      children: [
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          elevation: 3,
          shadowColor: AppColors.textPrimary.withValues(alpha: 0.3),
          child: InkWell(
            onTap: onPickAlarm,
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.statSleep,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      alarm == null
                          ? Icons.alarm_add_outlined
                          : Icons.alarm_on_outlined,
                      size: 19,
                      color: AppColors.surface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.bedroomWakeTogether,
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        second,
                        style: text.labelMedium?.copyWith(
                          color: alarm == null
                              ? AppColors.textSecondary
                              : AppColors.sageDark,
                          fontWeight: alarm == null
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Две кнопки выбора еды, стоящие прямо на кухне.
class _KitchenMenu extends StatelessWidget {
  const _KitchenMenu({
    this.onBottle,
    required this.dishesShown,
    required this.onToggleDishes,
    required this.cookShown,
    required this.onToggleCook,
  });

  /// Новорождённому — бутылочка, и только она (КП 5). `null` — не
  /// новорождённый: готовые блюда и готовка.
  final VoidCallback? onBottle;

  final bool dishesShown;
  final VoidCallback onToggleDishes;

  /// Рецепты на столе или идёт готовка — кнопка залита зелёным.
  final bool cookShown;
  final VoidCallback onToggleCook;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return _ActionRow(
      children: [
        if (onBottle case final bottle?) ...[
          _Pill(
            key: const ValueKey('kitchen-bottle'),
            label: l10n.kitchenBottle,
            icon: Icons.local_drink_outlined,
            onTap: bottle,
          ),
          const SizedBox(width: 8),
        ],
        // Новорождённого кормят только из бутылочки (ТЗ 5; заказчик 01.10:
        // «там точно никаких рыб, брокколи — просто бутылочка»). Меню
        // остальных стадий — ⚠ ждёт решения заказчика (docs/irina-wishes.md).
        if (onBottle == null) ...[
          // Готовые блюда — прямо на стол, не в отдельный лист: нажал — блюда
          // выехали, нажал ещё раз — убрались.
          _Pill(
            label: l10n.feedTabReady,
            icon: Icons.room_service_outlined,
            selected: dishesShown,
            onTap: onToggleDishes,
          ),
          const SizedBox(width: 8),
          // «Приготовить» — тоже прямо на стол (вариант A, заказчик 24.09):
          // рецепты выезжают дугой, готовка идёт в самой кухне, без шторки.
          _Pill(
            label: l10n.feedTabCook,
            icon: Icons.soup_kitchen_outlined,
            selected: cookShown,
            onTap: onToggleCook,
          ),
        ],
      ],
    );
  }
}

/// Подсказка от характера на кухне (КП 8.1): реплика мишки о еде в
/// плашке того же вида, что кнопки под ней.
class _KitchenHint extends StatelessWidget {
  const _KitchenHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        elevation: 3,
        shadowColor: AppColors.textPrimary.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧸', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Включена ли: блюда на столе — кнопка залита зелёным.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.sageDark : AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      elevation: 3,
      shadowColor: AppColors.textPrimary.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? Colors.white : AppColors.sageDark,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Что делать по ходу готовки на кухне: см. [KitchenCooking].
typedef CookCallbacks = ({
  VoidCallback onClose,
  VoidCallback onWrong,
  ValueChanged<Recipe> onCooked,
  ValueChanged<Recipe> onServe,
  ValueChanged<Recipe> onEaten,
  VoidCallback onFinished,
});

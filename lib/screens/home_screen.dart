import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../game/app_section.dart';
import '../game/game_calendar.dart';
import '../game/game_state.dart';
import '../game/pet_name.dart';
import '../game/room_kind.dart';
import '../game/room_slots.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/care_stats_panel.dart';
import '../widgets/pet_header.dart';
import '../widgets/pet_speech_bubble.dart';
import '../widgets/room_item_sheet.dart';
import '../widgets/room_ceiling.dart';
import '../widgets/room_slot_layer.dart';
import '../widgets/room_switcher.dart';
import '../widgets/room_scene_backdrop.dart';
import 'care_screen.dart';
import 'catalog_screen.dart';
import 'diary_screen.dart';
import 'feed_screen.dart';
import 'growth_screen.dart';
import 'learning_screen.dart';
import 'profile_screen.dart';
import 'room_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Высота нижнего меню, под которое уходит комната.
  ///
  /// Меню по решению заказчика 20.09 в итоге исчезнет — разделы переедут в
  /// кнопку-лапу. Пока оно на месте, показателям нужно знать, сколько под
  /// ними занято, иначе они лягут прямо на вкладки.
  static const double _bottomNavHeight = 80;

  AppSection _section = AppSection.home;

  /// Открытая комната. Живёт в памяти экрана: это не прогресс, а взгляд —
  /// куда человек сейчас смотрит. Уходить на сервер здесь нечему.
  RoomKind _room = RoomKind.nursery;

  void _runAction(BearAction action) {
    final controller = widget.controller;

    switch (action) {
      // По КП 8 кормление — это выбор блюда на отдельном экране, а не
      // мгновенное действие: там и списываются монеты.
      case BearAction.feed:
        _open(FeedScreen(controller: controller, game: widget.game));
      case BearAction.wash:
        controller.washBear();
      case BearAction.sleep:
        controller.putToSleep();
      case BearAction.play:
        controller.playWithBear();
      case BearAction.pet:
        controller.petBear();
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
    if (mounted) setState(() => _section = AppSection.home);
  }

  void _openSection(AppSection section) {
    if (section == AppSection.home) {
      setState(() => _section = AppSection.home);
      return;
    }

    setState(() => _section = section);

    switch (section) {
      case AppSection.room:
        _open(RoomScreen(game: widget.game));
      case AppSection.shop:
        _open(ShopScreen(game: widget.game));
      case AppSection.learning:
        _open(LearningScreen(game: widget.game));
      case AppSection.catalog:
        _open(CatalogScreen(controller: widget.controller));
      case AppSection.profile:
        _open(_profileScreen());
      case AppSection.home:
        break;
    }
  }

  /// Профиль — единственный экран с ветвлением: из него открываются рост,
  /// дневник и настройки (КП 14.1, 14.2).
  Widget _profileScreen() => ProfileScreen(
    controller: widget.controller,
    game: widget.game,
    calendar: widget.calendar,
    language: widget.language,
    onOpenGrowth: () => _open(GrowthScreen(controller: widget.controller)),
    onOpenDiary: () => _open(const DiaryScreen()),
    onSignOut: widget.onSignOut == null ? null : _signOut,
    onRename: widget.onRename,
    onOpenSettings: () => _open(
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

  void _notImplemented(BearAction action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.homeScreenNotReady(action.name)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

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
          body: Stack(
            children: [
              Positioned.fill(
                child: _RoomScene(
                  controller: widget.controller,
                  language: widget.language,
                  onAcceptInitiative: _runAction,
                  riveAssetPath: widget.riveAssetPath,
                  game: widget.game,
                  onSlotTap: _openSlotSheet,
                  room: _room,
                  onRoomChanged: (kind) => setState(() => _room = kind),
                  onOpenCare: () => _open(
                    CareScreen(
                      controller: widget.controller,
                      onOpenFeed: () => _open(
                        FeedScreen(
                          controller: widget.controller,
                          game: widget.game,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Слой управления. Пустоты в нём касания не ловят: между
              // шапкой и показателями стоит распорка, а она прозрачна для
              // пальца — погладить мишку можно через неё.
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pagePadding,
                    8,
                    AppDimens.pagePadding,
                    // Место под нижнее меню: оно ещё на своём месте, но
                    // комната уже уходит под него.
                    _bottomNavHeight + AppDimens.gap,
                  ),
                  child: Column(
                    children: [
                      PetHeader(profile: profile, age: age),
                      const Spacer(),
                      CareStatsPanel(
                        stats: state.stats,
                        stage: state.stage,
                        onAction: _runAction,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: widget.onOpenDevPanel == null
              ? null
              : FloatingActionButton.small(
                  onPressed: () => widget.onOpenDevPanel!(context),
                  tooltip: context.l10n.homeDevPanelTooltip,
                  child: const Icon(Icons.tune),
                ),
          bottomNavigationBar: AppBottomNav(
            current: _section,
            stage: state.stage,
            onSelected: _openSection,
          ),
        );
      },
    );
  }
}

/// Сцена комнаты: питомец и пузырь с репликой.
class _RoomScene extends StatelessWidget {
  const _RoomScene({
    required this.controller,
    required this.language,
    required this.onAcceptInitiative,
    required this.riveAssetPath,
    required this.onOpenCare,
    required this.game,
    required this.onSlotTap,
    required this.room,
    required this.onRoomChanged,
  });

  final BearController controller;
  final BearLanguage language;
  final ValueChanged<BearAction> onAcceptInitiative;
  final String riveAssetPath;

  /// Обстановка комнаты и кошелёк: сцена показывает, что где стоит.
  final GameState game;

  /// Тап по месту — занятому или свободному.
  final ValueChanged<RoomSlot> onSlotTap;

  /// Какая комната показана и что делать при переключении.
  final RoomKind room;
  final ValueChanged<RoomKind> onRoomChanged;

  /// Открыть список действий ухода (КП 6.4). На макете это отдельный экран
  /// «Что будем делать?», но кнопки, ведущей туда, в макете не видно —
  /// ДОПУЩЕНИЕ: ставим её в угол комнаты.
  final VoidCallback onOpenCare;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final frame = RoomFrame.of(Size(c.maxWidth, c.maxHeight));
        return ClipRect(child: _build(context, frame));
      },
    );
  }

  Widget _build(BuildContext context, RoomFrame frame) {
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
        // Погладить (КП 7.6) ловится самым нижним слоем, а не самим
        // мишкой. Мишка лежит между двумя слоями мест, и будь тап на нём —
        // он перехватывал бы касания по дальним вещам, которые рисуются
        // под ним. Внизу же он проигрывает всему, что выше: сначала вещи,
        // и только если тапнули мимо — поглаживание.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.petBear,
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
            onTapItem: (slot, _) => onSlotTap(slot),
            onTapEmpty: onSlotTap,
          ),
        ),
        // Герой стоит на линии пола комнаты и занимает свою долю её кадра.
        // Касания не ловит — их ловит слой под ним.
        Positioned(
          left: frame.bearCenterX - frame.rect.width / 2,
          top: frame.standY - frame.bearHeight,
          width: frame.rect.width,
          height: frame.bearHeight,
          child: IgnorePointer(
            child: BearView(controller: controller, assetPath: riveAssetPath),
          ),
        ),
        // Ближние места — поверх мишки. Слой занимает только площадь мест,
        // остальное прозрачно для касаний: погладить мишку по-прежнему
        // можно где угодно.
        Positioned.fromRect(
          rect: frame.rect,
          child: RoomSlotLayer(
            game: game,
            room: room,
            onTapItem: (slot, _) => onSlotTap(slot),
            onTapEmpty: onSlotTap,
          ),
        ),
        // Кнопка ухода и пузырь опущены под шапку: сцена больше не
        // начинается под ней, а лежит во весь экран, и прежние «12 от
        // верха» попали бы прямо на имя питомца.
        Positioned(
          top: _hudTop,
          right: 16,
          child: _CareButton(onTap: onOpenCare),
        ),
        Positioned(
          left: 16,
          bottom: 210,
          child: RoomSwitcher(current: room, onSelect: onRoomChanged),
        ),
        // Пузырь — слева, зеркально кнопке «Что будем делать?» справа
        // (решение заказчика). Внизу он закрывал мишке ноги, по центру
        // сверху — упирался в капюшон.
        Positioned(
          left: 16,
          right: 176,
          top: _hudTop,
          child: PetSpeechBubble(
            mood: controller.state.mood,
            initiative: controller.initiative,
            language: language,
            onTap: onAcceptInitiative,
          ),
        ),
      ],
    );
  }

  /// Верх свободной зоны: ниже шапки, но ещё на потолке.
  static const double _hudTop = 132;
}

/// Кнопка перехода к списку действий ухода.
class _CareButton extends StatelessWidget {
  const _CareButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            border: Border.all(color: AppColors.outline),
          ),
          child: Text(
            context.l10n.homeCareButton,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

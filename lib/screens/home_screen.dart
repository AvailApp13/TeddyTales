import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../game/app_section.dart';
import '../game/game_calendar.dart';
import '../game/game_state.dart';
import '../game/room_hints.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/care_stats_panel.dart';
import '../widgets/pet_header.dart';
import '../widgets/pet_speech_bubble.dart';
import '../widgets/room_hint_layer.dart';
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

  /// Какой `.riv` показывать. Пока настоящий риг не собран, сюда можно
  /// подставить [BearRigSpec.demoAssetPath] и убедиться, что пайплайн живой.
  final String riveAssetPath;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSection _section = AppSection.home;

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

  /// Тап по подсвеченному месту в комнате.
  ///
  /// Своё ставим молча и сразу — это бесплатно, обратимо и должно
  /// чувствоваться как один жест, а не как покупка. За остальным идём в
  /// магазин, открытый на нужной вкладке: человек уже показал, что ему
  /// нужно, искать это заново он не должен.
  void _useHint(RoomHint hint) {
    if (!hint.owned) {
      _open(ShopScreen(game: widget.game, focusItemId: hint.id));
      return;
    }

    widget.game.togglePlaced(hint.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.roomItemPlaced(shopItemName(context.l10n, hint.id)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  PetHeader(profile: profile, age: age),
                  const SizedBox(height: AppDimens.gap),
                  Expanded(
                    child: _RoomScene(
                      controller: widget.controller,
                      language: widget.language,
                      onAcceptInitiative: _runAction,
                      riveAssetPath: widget.riveAssetPath,
                      placed: widget.game.placed,
                      hints: roomHints(
                        placed: widget.game.placed,
                        owned: widget.game.owned,
                        stage: state.stage,
                      ),
                      onHintTap: _useHint,
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
                  const SizedBox(height: AppDimens.gap),
                  CareStatsPanel(
                    stats: state.stats,
                    stage: state.stage,
                    onAction: _runAction,
                  ),
                  const SizedBox(height: AppDimens.gap),
                ],
              ),
            ),
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
    required this.placed,
    required this.hints,
    required this.onHintTap,
  });

  final BearController controller;
  final BearLanguage language;
  final ValueChanged<BearAction> onAcceptInitiative;
  final String riveAssetPath;

  /// Размещённые в комнате предметы — их рисует фон-сцена.
  final Set<String> placed;

  /// Пустые места, которые стоит подсветить.
  final List<RoomHint> hints;
  final ValueChanged<RoomHint> onHintTap;

  /// Открыть список действий ухода (КП 6.4). На макете это отдельный экран
  /// «Что будем делать?», но кнопки, ведущей туда, в макете не видно —
  /// ДОПУЩЕНИЕ: ставим её в угол комнаты.
  final VoidCallback onOpenCare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Габаритная сборка комнаты: фон и мебель каталога в масштабе
          // размерной сетки (room_layout.dart) — мебель мельче героя, как
          // задний план с перспективой на макете.
          Positioned.fill(child: RoomSceneBackdrop(placed: placed)),
          // Герой — крупный, во всю сцену, как на макете. Его размер
          // ФИКСИРОВАН решением заказчика: не вписывать в размерную сетку
          // и не уменьшать. Размерный ряд для дизайнера показывает
          // docs/interior-size-guide.png, а не главный экран.
          Positioned.fill(
            // Тап по мишке — погладить: контроллер стреляет trg_pet, риг
            // проигрывает смех с подскоком (КП 7.6: смех по касанию).
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller.petBear,
              child: BearView(controller: controller, assetPath: riveAssetPath),
            ),
          ),
          // Подсказки лежат ПОВЕРХ мишки, иначе он перехватывал бы тапы по
          // ним: на главном экране он растянут во всю сцену. Сам слой
          // занимает только рамки, остальное пространство прозрачно для
          // касаний — погладить мишку по-прежнему можно где угодно.
          Positioned.fill(
            child: RoomHintLayer(hints: hints, onTap: onHintTap),
          ),
          Positioned(top: 12, right: 12, child: _CareButton(onTap: onOpenCare)),
          // Пузырь — в левом верхнем углу, зеркально кнопке «Что будем
          // делать?» справа (решение заказчика). Внизу он закрывал мишке
          // ноги, по центру сверху — упирался в капюшон. Правая граница
          // оставляет место кнопке ухода.
          Positioned(
            left: 12,
            right: 172,
            top: 12,
            child: PetSpeechBubble(
              mood: controller.state.mood,
              initiative: controller.initiative,
              language: language,
              onTap: onAcceptInitiative,
            ),
          ),
        ],
      ),
    );
  }
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

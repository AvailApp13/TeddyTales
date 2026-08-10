import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../game/app_section.dart';
import '../game/game_calendar.dart';
import '../game/pet_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/care_stats_panel.dart';
import '../widgets/pet_header.dart';
import '../widgets/pet_speech_bubble.dart';

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
    required this.profile,
    this.calendar = const GameCalendar(),
    this.language = BearLanguage.ru,
    this.onOpenDevPanel,
    this.riveAssetPath = BearRigSpec.assetPath,
  });

  final BearController controller;
  final PetProfile profile;
  final GameCalendar calendar;
  final BearLanguage language;

  /// Открыть дев-панель со всеми входами State Machine. `null` в релизе —
  /// кнопки просто нет.
  final void Function(BuildContext context)? onOpenDevPanel;

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
      case BearAction.feed:
        controller.feedBear();
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

  void _notImplemented(BearAction action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Экран для «${action.name}» ещё не собран'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final age = widget.calendar.ageAt(widget.profile.birthAt);

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
                  PetHeader(
                    profile: widget.profile,
                    age: age,
                    language: widget.language,
                  ),
                  const SizedBox(height: AppDimens.gap),
                  Expanded(
                    child: _RoomScene(
                      controller: widget.controller,
                      language: widget.language,
                      onAcceptInitiative: _runAction,
                      riveAssetPath: widget.riveAssetPath,
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
                  tooltip: 'Дев-панель рига',
                  child: const Icon(Icons.tune),
                ),
          bottomNavigationBar: AppBottomNav(
            current: _section,
            stage: state.stage,
            onSelected: (section) {
              if (section == AppSection.home) {
                setState(() => _section = section);
                return;
              }
              // Остальные разделы — следующая работа.
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Раздел «${section.title}» ещё не собран'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
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
  });

  final BearController controller;
  final BearLanguage language;
  final ValueChanged<BearAction> onAcceptInitiative;
  final String riveAssetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.cream, AppColors.surfaceMuted],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: BearView(controller: controller, assetPath: riveAssetPath),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
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

// `Factory` есть и во Flutter (`foundation`, для gestureRecognizers у platform
// views), и в Rive (выбор рендерера). Здесь нужен второй — прячем первый.
import 'package:flutter/foundation.dart' hide Factory;
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import 'bear_controller.dart';
import 'bear_rig_binding.dart';
import 'bear_rig_spec.dart';

/// Виджет с анимированным мишкой.
///
/// Загружает `.riv` (пункт 9.3 ТЗ), подключает риг к [controller] и снимает
/// подключение при уходе с экрана.
///
/// Пока `assets/rive/bear.riv` нет в репозитории, виджет рисует плейсхолдер —
/// приложение собирается и запускается без рига.
class BearView extends StatefulWidget {
  const BearView({
    super.key,
    required this.controller,
    this.fit = Fit.contain,
    this.alignment = Alignment.center,
    this.tapToReact = true,
  });

  /// Рендерер по умолчанию.
  ///
  /// [Factory.rive] — собственный рендерер Rive: одинаковая картинка на всех
  /// платформах и обход расхождений Impeller/Skia из раздела 6.5 ТЗ, потому что
  /// растеризация больше не идёт через Impeller.
  /// [Factory.flutter] — рендер средствами Flutter (Skia/Impeller).
  ///
  /// Геттер, а не константа: `Factory.rive` в рантайме — не const-выражение.
  static Factory get riveFactory => Factory.rive;

  /// Контроллер, состояние которого едет в риг.
  final BearController controller;

  final Fit fit;
  final Alignment alignment;

  /// Реагировать ли на тап по мишке ([BearController.petBear]).
  ///
  /// Раздел 8.1 ТЗ аниматора: `trg_pet` — «поглаживание (касание экрана)»;
  /// КП 3.1: питомец реагирует на касание.
  ///
  /// Выключить, если реакция на тап заведена внутри самой State Machine через
  /// Rive Listeners — иначе тап отработает дважды.
  final bool tapToReact;

  @override
  State<BearView> createState() => _BearViewState();
}

class _BearViewState extends State<BearView> {
  late final FileLoader _fileLoader = FileLoader.fromAsset(
    BearRigSpec.assetPath,
    riveFactory: BearView.riveFactory,
  );
  BearRigBinding? _binding;

  @override
  void didUpdateWidget(BearView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      final binding = _binding;
      oldWidget.controller.detachRig();
      if (binding != null) widget.controller.attachRig(binding);
    }
  }

  @override
  void dispose() {
    _detachRig();
    // Загрузчиком владеет этот State — освобождаем.
    _fileLoader.dispose();
    super.dispose();
  }

  /// Создаёт контроллер рантайма на артборде и State Machine из контракта
  /// (`bear_main`), откатываясь на объекты по умолчанию, если имена в файле
  /// разошлись.
  ///
  /// Откат нужен на время сборки рига: аниматор сдаёт файл шестью этапами
  /// (раздел 11 ТЗ), и на ранних этапах имена могут не совпасть. Без отката
  /// виджет просто уходил бы в `RiveFailed` вместо показа персонажа.
  RiveWidgetController _createRiveController(File file) {
    try {
      return RiveWidgetController(
        file,
        artboardSelector: const ArtboardNamed(BearRigSpec.artboard),
        stateMachineSelector: const StateMachineNamed(
          BearRigSpec.stateMachine,
        ),
      );
    } on RiveException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[TeddyTales] $error Берём артборд и State Machine по умолчанию. '
          'Сверьте имена с разделом 8 ТЗ аниматора — должно быть '
          '«${BearRigSpec.stateMachine}».',
        );
      }
      return RiveWidgetController(file);
    }
  }

  void _onLoaded(RiveLoaded state) {
    _detachRig();
    final binding = BearRigBinding.attach(state.controller);
    _binding = binding;
    widget.controller.attachRig(binding);
  }

  void _detachRig() {
    widget.controller.detachRig();
    _binding?.dispose();
    _binding = null;
  }

  @override
  Widget build(BuildContext context) {
    final rive = RiveWidgetBuilder(
      fileLoader: _fileLoader,
      // Data binding подключается внутри BearRigBinding.attach — см. коммент
      // там о том, почему не через параметр `dataBind`.
      controller: _createRiveController,
      onLoaded: _onLoaded,
      onFailed: (error, stackTrace) {
        // Штатная ситуация до того, как риг собран: файла ещё нет.
        if (kDebugMode) debugPrint('[TeddyTales] Rive не загрузился: $error');
      },
      builder: (context, state) => switch (state) {
        RiveLoading() => const Center(child: CircularProgressIndicator()),
        RiveFailed() => _BearPlaceholder(error: state.error),
        RiveLoaded() => RiveWidget(
          controller: state.controller,
          fit: widget.fit,
          alignment: widget.alignment,
        ),
      },
    );

    if (!widget.tapToReact) return rive;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.controller.petBear,
      child: rive,
    );
  }
}

/// Заглушка на месте мишки, пока `bear.riv` не собран.
class _BearPlaceholder extends StatelessWidget {
  const _BearPlaceholder({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pets,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('Риг ещё не подключён', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Положите ${BearRigSpec.assetPath}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              Text(
                '$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

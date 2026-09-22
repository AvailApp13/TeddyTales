import 'dart:async';

// Точечный импорт: полный foundation.dart принёс бы свой `Factory`, который
// конфликтует с риверовским.
import 'package:flutter/foundation.dart' show kDebugMode, debugPrintStack;
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import 'bear_controller.dart';
import 'bear_rig_contract.dart';
import 'bear_vitals.dart';

/// Мишка на главном экране комнаты (КП 3.1).
///
/// Сам грузит .riv и держит [BearController]. Экран получает готовый
/// контроллер через [onReady] и дальше зовёт `feedBear()`, `petBear()` и
/// остальное — виджет не знает про игровую логику.
///
/// Файл загружается явно, а не через `RiveWidgetBuilder`: билдер заводит
/// собственный [RiveWidgetController], и на один .riv пришлось бы два
/// контроллера с разными артбордами.
class BearView extends StatefulWidget {
  const BearView({
    super.key,
    this.artboard = BearRig.artboardDefault,
    this.initialVitals,
    this.initialStage = BearStage.initial,
    this.initialTrait = BearTrait.initial,
    this.fit = Fit.contain,
    this.onReady,
    this.onTap,
    this.placeholder,
    this.errorBuilder,
  });

  /// Артборд героя: [BearRig.artboardBoy] или [BearRig.artboardGirl].
  final String artboard;

  final BearVitals? initialVitals;
  final BearStage initialStage;
  final BearTrait initialTrait;
  final Fit fit;

  /// Вызывается один раз, когда контроллер готов. Контроллер принадлежит
  /// виджету — не сохраняйте его дольше, чем живёт [BearView].
  final ValueChanged<BearController>? onReady;

  /// Касание питомца (КП 3.1). Триггер `tap` контроллер отправляет сам.
  final VoidCallback? onTap;

  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<BearView> createState() => _BearViewState();
}

class _BearViewState extends State<BearView> {
  File? _file;
  BearController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final file = await File.asset(BearRig.asset, riveFactory: Factory.rive);
      if (file == null) {
        throw StateError('Не удалось разобрать ${BearRig.asset}');
      }
      // Виджет мог быть снят с дерева, пока грузился файл.
      if (!mounted) {
        file.dispose();
        return;
      }
      final controller = BearController(
        file: file,
        artboard: widget.artboard,
        vitals: widget.initialVitals,
        stage: widget.initialStage,
        trait: widget.initialTrait,
      );
      setState(() {
        _file = file;
        _controller = controller;
      });
      widget.onReady?.call(controller);
    } catch (error, stackTrace) {
      debugPrint('BearView: не удалось загрузить ${BearRig.asset}: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ?? _RigMissing(error: error);
    }
    final controller = _controller;
    if (controller == null) {
      return widget.placeholder ?? const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        controller.tapBear();
        widget.onTap?.call();
      },
      child: RiveWidget(controller: controller.riveController, fit: widget.fit),
    );
  }
}

/// Показывается, когда .riv отсутствует или не совпадает с контрактом.
///
/// На этапе сборки рига это норма, поэтому подсказка ведёт к лаборатории, а не
/// выглядит как отказ приложения.
class _RigMissing extends StatelessWidget {
  const _RigMissing({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pets, size: 48),
            const SizedBox(height: 12),
            Text('Мишка пока не собран', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Нет файла ${BearRig.asset} или он не совпадает со спецификацией.\n'
              'Проверка: cd tools && npm run lab',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 10),
              Text('$error', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

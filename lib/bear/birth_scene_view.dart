import 'package:flutter/foundation.dart' hide Factory;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rive/rive.dart';

import '../l10n/birth_l10n.dart';
import '../l10n/l10n.dart';
import 'bear_phrases.dart' show BearLanguage;
import 'bear_rig_spec.dart';
import 'birth_scene_script.dart';

/// Экран сцены рождения (КП 2.1).
///
/// Проигрывает `birth_scene.riv` — отдельный артборд с линейной анимацией, вне
/// основной State Machine (раздел 7.8 ТЗ аниматора). Поверх кладёт субтитры на
/// языке пользователя и кнопку «Пропустить», которая появляется через 5 секунд.
///
/// Сцена сдаётся ещё и видеорендером mp4. Чем показывать её в бою — Rive или
/// видео — не решено: Rive лучше держит любой размер экрана и не требует
/// плеера, видео гарантированно совпадает с тем, что утвердили. Здесь сделан
/// вариант на Rive; переезд на видео затронет только этот файл, `onFinished` и
/// субтитры останутся прежними.
class BirthSceneView extends StatefulWidget {
  const BirthSceneView({
    super.key,
    required this.onFinished,
    this.language = BearLanguage.ru,
    this.script = const BirthSceneScript(),
    this.fit = Fit.cover,
  });

  /// Вызывается, когда сцена доиграла или пользователь нажал «Пропустить».
  /// Дальше по КП 2.2 идёт карточка рождения.
  final VoidCallback onFinished;

  /// Язык сцены. Тексты субтитров и кнопки берутся из локализации по локали
  /// приложения (язык у приложения один на всё — см. `lib/l10n/l10n.dart`,
  /// [BearLanguage] отображается в неё один в один), поэтому параметр на
  /// отрисовку больше не влияет и оставлен ради совместимости вызовов.
  final BearLanguage language;
  final BirthSceneScript script;
  final Fit fit;

  @override
  State<BirthSceneView> createState() => _BirthSceneViewState();
}

class _BirthSceneViewState extends State<BirthSceneView>
    with SingleTickerProviderStateMixin {
  File? _file;
  Artboard? _artboard;
  SingleAnimationPainter? _painter;
  Ticker? _ticker;

  /// Позиция в сцене. Именно notifier, а не поле State: тикер идёт 60 раз в
  /// секунду, и перестраивать из-за него весь Stack вместе с виджетом Rive
  /// незачем — обновляются только субтитры и кнопка.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  Object? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Тикер идёт независимо от того, загрузился ли риг: субтитры и кнопка
    // «Пропустить» должны работать даже на плейсхолдере, иначе на этом экране
    // можно застрять.
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _load() async {
    try {
      final file = await File.asset(
        BearRigSpec.birthSceneAssetPath,
        // Рендерер тот же, что у персонажа, — см. BearView.riveFactory.
        riveFactory: Factory.rive,
      );
      if (file == null) throw StateError('Файл сцены рождения не загрузился');
      if (!mounted) {
        file.dispose();
        return;
      }

      final artboard = file.defaultArtboard();
      if (artboard == null) throw StateError('В файле нет артборда');

      setState(() {
        _file = file;
        _artboard = artboard;
        _painter = SingleAnimationPainter(
          _resolveAnimationName(artboard),
          fit: widget.fit,
        );
      });
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('[TeddyTales] Сцена рождения не загрузилась: $error');
      }
      if (mounted) setState(() => _error = error);
    }
  }

  /// Имя анимации в файле сцены в ТЗ не зафиксировано — берём первую, какая
  /// есть. Если аниматор назовёт её иначе, чем ожидается, сцена всё равно
  /// проиграется.
  String _resolveAnimationName(Artboard artboard) {
    try {
      return artboard.animationAt(0).name;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[TeddyTales] В артборде сцены рождения нет анимаций: $error',
        );
      }
      return '';
    }
  }

  void _onTick(Duration elapsed) {
    if (_finished) return;

    _position.value = elapsed;

    if (widget.script.isFinishedAt(elapsed)) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker?.stop();
    widget.onFinished();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _position.dispose();
    _painter?.dispose();
    _artboard?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final script = widget.script;

    return Scaffold(
      backgroundColor: const Color(0xFF1B1622),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_artboard != null && _painter != null)
            RiveArtboardWidget(artboard: _artboard!, painter: _painter!)
          else
            _BirthScenePlaceholder(error: _error),

          // Субтитры. Сцена сдаётся без текста — накладываем сами (7.8 ТЗ).
          Positioned(
            left: 24,
            right: 24,
            bottom: 72,
            child: ValueListenableBuilder<Duration>(
              valueListenable: _position,
              builder: (context, position, _) {
                final cue = script.cueAt(position);
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: cue == null
                      ? const SizedBox.shrink()
                      : Text(
                          birthCueText(context.l10n, cue.id),
                          key: ValueKey(cue.start),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            height: 1.4,
                            shadows: [
                              Shadow(blurRadius: 8, color: Colors.black54),
                            ],
                          ),
                        ),
                );
              },
            ),
          ),

          // «Пропустить» — только после 5 секунд (КП 2.1).
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 16,
            child: ValueListenableBuilder<Duration>(
              valueListenable: _position,
              builder: (context, position, child) {
                final canSkip = script.canSkipAt(position);
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: canSkip ? 1 : 0,
                  child: IgnorePointer(ignoring: !canSkip, child: child),
                );
              },
              child: TextButton(
                onPressed: _finish,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: Text(context.l10n.birthSkip),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthScenePlaceholder extends StatelessWidget {
  const _BirthScenePlaceholder({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.nights_stay, size: 64, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            context.l10n.birthSceneNotReady,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 4),
          Text(
            BearRigSpec.birthSceneAssetPath,
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),
          if (kDebugMode && error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

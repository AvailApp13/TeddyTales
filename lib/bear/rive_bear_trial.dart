import 'package:flutter/material.dart' hide Animation;
import 'package:rive/rive.dart';

/// ⚠ ПРОВЕРКА ФАЙЛА АНИМАТОРА — не финальный мишка (заказчик 26.09:
/// «ставь в игровую на проверку»).
///
/// Файл `bear_boy_v2.riv`, присланный заказчиком 26.09. Внутри три
/// анимации: `idle_life` (живой покой: дыхание, моргание, уши),
/// `face_demo` (показ выражений лица подряд) и `demo_moves` (пробные
/// движения). Действий ухода (еда, сон, мытьё, игра) в файле пока нет —
/// их делает аниматор в редакторе Rive.
///
/// Копия в `assets/rive/` отличается от присланной одним числом: фон
/// артборда (тёмный, 0xFF282828) сделан прозрачным, иначе в комнате мишка
/// стоял бы на тёмном квадрате. Попросить аниматора убрать фон в самом
/// файле.
///
/// Здесь: покой крутится всегда, а выражение лица накладывается поверх на
/// пару секунд — одним застывшим кадром из `face_demo` ([BearFace]).
/// Кадр, а не отрезок: в демо смех заложен с «трясучкой» (голова и тело
/// ходят ±3–4 % ширины 2,5 раза в секунду) — в комнате это читалось как
/// «бьёт током» (заказчик 26.09). Кадры подобраны там, где лицо полное, а
/// голова ближе всего к покою; вход и выход плавные.
const String kTrialBearAsset = 'assets/rive/bear_boy_v2.riv';

/// Выражения лица — кадр `face_demo` (секунда) и сколько его держать.
enum BearFace {
  love(5.85, 1.8),
  laugh(4.4, 1.6),
  surprised(7.7, 1.5),
  sad(10.15, 2.2),
  chew(12.9, 1.4),
  lick(14.45, 1.4),
  yawn(16.35, 1.8),
  sleepy(17.5, 2.0),
  upset(19.4, 1.4);

  const BearFace(this.frame, this.hold);

  /// Секунда `face_demo`, где выражение полное и голова стоит ровно.
  final double frame;

  /// Сколько держать, вместе с плавными входом и выходом.
  final double hold;

  /// Касания по очереди (заказчик 26.09).
  static const List<BearFace> taps = [love, laugh, surprised, upset, lick];
}

/// Кто просит выражение: экран дёргает [show], мишка откликается.
class BearFaceCue extends ChangeNotifier {
  BearFace? _face;
  int _serial = 0;

  BearFace? get face => _face;
  int get serial => _serial;

  void show(BearFace face) {
    _face = face;
    _serial++;
    notifyListeners();
  }
}

class RiveBearTrial extends StatefulWidget {
  const RiveBearTrial({
    super.key,
    required this.cue,
    this.onTap,
    this.greeting,
  });

  final BearFaceCue cue;

  /// Чем встретить при входе в игровую — по состоянию (заказчик 26.09):
  /// голоден — грусть, хочет спать — зевает, всё хорошо — улыбка.
  final BearFace? Function()? greeting;

  /// Касание мишки (КП 3.1).
  final VoidCallback? onTap;

  @override
  State<RiveBearTrial> createState() => _RiveBearTrialState();
}

class _RiveBearTrialState extends State<RiveBearTrial> {
  File? _file;
  late final _TrialPainter _painter = _TrialPainter();

  /// Какое по счёту касание — выражения идут по кругу.
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    widget.cue.addListener(_onCue);
    File.asset(kTrialBearAsset, riveFactory: Factory.rive)
        .then((file) {
          if (!mounted) {
            file?.dispose();
            return;
          }
          setState(() => _file = file);
          final greet = widget.greeting?.call();
          if (greet != null) {
            Future<void>.delayed(const Duration(milliseconds: 600), () {
              if (mounted) _painter.play(greet);
            });
          }
        })
        .catchError((Object error) {
          debugPrint('[TeddyTales] $kTrialBearAsset не загрузился: $error');
        });
  }

  void _onCue() {
    final face = widget.cue.face;
    if (face != null) _painter.play(face);
  }

  @override
  void didUpdateWidget(RiveBearTrial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cue != widget.cue) {
      oldWidget.cue.removeListener(_onCue);
      widget.cue.addListener(_onCue);
    }
  }

  @override
  void dispose() {
    widget.cue.removeListener(_onCue);
    _painter.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return const SizedBox.shrink();
    return GestureDetector(
      key: const ValueKey('rive-bear-trial'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _painter.play(BearFace.taps[_taps++ % BearFace.taps.length]);
        widget.onTap?.call();
      },
      child: RiveFileWidget(
        file: file,
        painter: _painter,
        artboardName: 'Bear_Boy',
      ),
    );
  }
}

/// Покой `idle_life` всё время, поверх — отрезок `face_demo` с плавным
/// входом и выходом.
final class _TrialPainter extends BasicArtboardPainter {
  _TrialPainter() : super(fit: Fit.contain, alignment: Alignment.bottomCenter);

  /// Вход и выход выражения, секунды: голова доходит до позы плавно.
  static const double _fade = 0.4;

  Animation? _idle;
  Animation? _faces;
  BearFace? _face;
  double _t = 0;

  void play(BearFace face) {
    _face = face;
    _t = 0;
    scheduleRepaint();
  }

  @override
  void artboardChanged(Artboard artboard) {
    super.artboardChanged(artboard);
    _idle?.dispose();
    _faces?.dispose();
    _idle = artboard.animationNamed('idle_life');
    _faces = artboard.animationNamed('face_demo');
    notifyListeners();
  }

  @override
  bool advance(double elapsedSeconds) {
    _idle?.advanceAndApply(elapsedSeconds);
    final face = _face;
    final faces = _faces;
    if (face != null && faces != null) {
      _t += elapsedSeconds;
      if (_t >= face.hold) {
        _face = null;
      } else {
        final edge = _t < _fade
            ? _t / _fade
            : _t > face.hold - _fade
            ? (face.hold - _t) / _fade
            : 1.0;
        faces.time = face.frame;
        faces.apply(mix: Curves.easeInOut.transform(edge.clamp(0.0, 1.0)));
      }
    }
    super.advance(0);
    return true;
  }

  @override
  void dispose() {
    _idle?.dispose();
    _faces?.dispose();
    super.dispose();
  }
}

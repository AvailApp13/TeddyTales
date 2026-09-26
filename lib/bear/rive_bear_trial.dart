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
/// пару секунд — отрезком из `face_demo` ([BearFace]).
const String kTrialBearAsset = 'assets/rive/bear_boy_v2.riv';

/// Выражения лица — отрезки `face_demo`, секунды размечены по кадрам.
enum BearFace {
  love(5.0, 6.6),
  laugh(3.4, 4.6),
  surprised(6.9, 8.1),
  sad(8.9, 11.6),
  chew(12.4, 13.4),
  lick(14.2, 15.0),
  yawn(15.8, 16.8),
  sleepy(16.9, 18.6),
  upset(19.1, 20.1);

  const BearFace(this.start, this.end);

  final double start;
  final double end;
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
  const RiveBearTrial({super.key, required this.cue, this.onTap});

  final BearFaceCue cue;

  /// Касание мишки (КП 3.1).
  final VoidCallback? onTap;

  @override
  State<RiveBearTrial> createState() => _RiveBearTrialState();
}

class _RiveBearTrialState extends State<RiveBearTrial> {
  File? _file;
  late final _TrialPainter _painter = _TrialPainter();

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
        _painter.play(BearFace.love);
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

  static const double _fade = 0.25;

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
      final length = face.end - face.start;
      if (_t >= length) {
        _face = null;
      } else {
        final mix =
            (_t < _fade
                    ? _t / _fade
                    : _t > length - _fade
                    ? (length - _t) / _fade
                    : 1.0)
                .clamp(0.0, 1.0);
        faces.time = face.start + _t;
        faces.apply(mix: mix);
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

import 'dart:math' as math;

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
/// Копия в `assets/rive/` собрана Rive CLI из исходника `.rev` заказчика
/// (26.09): фон артборда прозрачный (был тёмный 0xFF282828) и добавлена
/// анимация `emo_smile` — улыбка всем телом (моргнул → улыбка с румянцем,
/// наклон с пружинкой, подскок, лапки и уши, вдох; 1,8 с). Исходник и
/// шаги сборки — `docs/rive-bear.md`.
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

  /// Своя анимация в файле: её играют кости и лицо целиком, без
  /// застывшего кадра и без позы корпуса из приложения. `null` — пока нет.
  String? get clip => switch (this) {
    love => 'emo_smile',
    _ => null,
  };

  /// Касания по очереди (заказчик 26.09).
  static const List<BearFace> taps = [love, laugh, surprised, upset, lick];

  /// Поза тела на эмоцию (заказчик 26.09: «плавно, как в Томе»): лицо в
  /// файле только подменяется, поэтому эмоцию играет корпус — наклон,
  /// сжатие-растяжение, подъём.
  BodyPose get pose => switch (this) {
    love => const BodyPose(tilt: 3.5, stretch: 0.025, lift: 0.012),
    laugh => const BodyPose(tilt: -1.5, stretch: 0.04, lift: 0.022),
    surprised => const BodyPose(stretch: 0.055, lift: 0.028),
    sad => const BodyPose(tilt: -2.5, stretch: -0.03, lift: -0.008),
    chew => const BodyPose(stretch: -0.012),
    lick => const BodyPose(tilt: -3, stretch: 0.01),
    yawn => const BodyPose(tilt: 2, stretch: 0.045, lift: 0.01),
    sleepy => const BodyPose(tilt: 3, stretch: -0.025, lift: -0.006),
    upset => const BodyPose(stretch: -0.04, lift: -0.004),
  };
}

/// Поза корпуса: наклон в градусах (плюс — вправо), растяжение по высоте
/// (минус — сжался, ширина меняется обратно, объём сохраняется) и подъём —
/// доля высоты мишки.
class BodyPose {
  const BodyPose({this.tilt = 0, this.stretch = 0, this.lift = 0});

  final double tilt;
  final double stretch;
  final double lift;
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

class _RiveBearTrialState extends State<RiveBearTrial>
    with SingleTickerProviderStateMixin {
  File? _file;
  late final _TrialPainter _painter = _TrialPainter();

  /// Реакция корпуса на эмоцию — длиной с саму эмоцию.
  late final AnimationController _body = AnimationController(vsync: this);
  BearFace? _bodyFace;

  /// Эмоция целиком: лицо из файла и поза корпуса.
  void _react(BearFace face) {
    _painter.play(face);
    // Своя анимация сама двигает тело — поза из приложения не нужна.
    _bodyFace = face.clip == null ? face : null;
    _body
      ..duration = Duration(milliseconds: (face.hold * 1000).round())
      ..forward(from: 0);
  }

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
              if (mounted) _react(greet);
            });
          }
        })
        .catchError((Object error) {
          debugPrint('[TeddyTales] $kTrialBearAsset не загрузился: $error');
        });
  }

  void _onCue() {
    final face = widget.cue.face;
    if (face != null) _react(face);
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
    _body.dispose();
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
        _react(BearFace.taps[_taps++ % BearFace.taps.length]);
        widget.onTap?.call();
      },
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _body,
          builder: (context, child) => Transform(
            alignment: const Alignment(0, 0.92),
            transform: _bodyTransform(box.maxHeight),
            child: child,
          ),
          child: RiveFileWidget(
            file: file,
            painter: _painter,
            artboardName: 'Bear_Boy',
          ),
        ),
      ),
    );
  }

  /// Корпус на эмоцию, как у мультяшных питомцев: замах (присел), пружинка
  /// в позу с лёгким перелётом, держит, мягко возвращается. Опора — стопы.
  Matrix4 _bodyTransform(double height) {
    final face = _bodyFace;
    if (face == null || !_body.isAnimating) return Matrix4.identity();
    final total = face.hold;
    final t = _body.value * total;
    const windup = 0.14; // присел перед движением
    const rise = 0.42; // пружинка в позу
    const back = 0.5; // возврат
    double k; // доля позы, 0 — покой, 1 — поза
    var squat = 0.0;
    if (t < windup) {
      k = 0;
      squat = math.sin(math.pi * t / windup) * 0.028;
    } else if (t < windup + rise) {
      k = Curves.easeOutBack.transform((t - windup) / rise);
    } else if (t > total - back) {
      k =
          1 -
          Curves.easeInOutCubic.transform(
            ((t - (total - back)) / back).clamp(0.0, 1.0),
          );
    } else {
      k = 1;
    }
    final pose = face.pose;
    final stretch = pose.stretch * k - squat;
    final sy = 1 + stretch;
    final sx = 1 - stretch * 0.6;
    return Matrix4.identity()
      ..translateByDouble(0, -pose.lift * k * height, 0, 1)
      ..rotateZ(pose.tilt * k * math.pi / 180)
      ..scaleByDouble(sx, sy, 1, 1);
  }
}

/// Покой `idle_life` всё время, поверх — отрезок `face_demo` с плавным
/// входом и выходом.
final class _TrialPainter extends BasicArtboardPainter {
  _TrialPainter() : super(fit: Fit.contain, alignment: Alignment.bottomCenter);

  /// Вход и выход выражения, секунды: голова доходит до позы плавно.
  static const double _fade = 0.5;

  Animation? _idle;
  Animation? _faces;
  final Map<String, Animation> _clips = {};
  Animation? _clip;
  BearFace? _face;
  double _t = 0;

  void play(BearFace face) {
    final name = face.clip;
    final clip = name == null ? null : _clips[name];
    if (clip != null) {
      clip.time = 0;
      _clip = clip;
      _face = null;
      _t = 0;
      scheduleRepaint();
      return;
    }
    _clip = null;
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
    for (final clip in _clips.values) {
      clip.dispose();
    }
    _clips.clear();
    for (final face in BearFace.values) {
      final name = face.clip;
      if (name == null || _clips.containsKey(name)) continue;
      final animation = artboard.animationNamed(name);
      if (animation != null) _clips[name] = animation;
    }
    notifyListeners();
  }

  @override
  bool advance(double elapsedSeconds) {
    _idle?.advanceAndApply(elapsedSeconds);
    final clip = _clip;
    if (clip != null) {
      // Своя анимация поверх покоя; края смешиваются за 0,15 с, чтобы
      // покой и первая поза анимации не расходились рывком.
      clip.advance(elapsedSeconds);
      final t = clip.time;
      final left = clip.duration - t;
      if (left <= 0) {
        _clip = null;
      } else {
        const edge = 0.15;
        final mix = t < edge ? t / edge : (left < edge ? left / edge : 1.0);
        clip.apply(mix: mix.clamp(0.0, 1.0));
      }
    }
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
        faces.apply(mix: Curves.easeInOutCubic.transform(edge.clamp(0.0, 1.0)));
      }
    }
    super.advance(0);
    return true;
  }

  @override
  void dispose() {
    _idle?.dispose();
    _faces?.dispose();
    for (final clip in _clips.values) {
      clip.dispose();
    }
    super.dispose();
  }
}

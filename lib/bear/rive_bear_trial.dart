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
/// (26.09): фон прозрачный, скелет пересобран заново (26 костей), покой
/// `idle_life` — дыхание всем телом и мягкое моргание, у каждого
/// выражения своя анимация всем телом (`emo_smile`, `emo_laugh`,
/// `emo_surprised`, `emo_sad`, `emo_chew`, `emo_lick`, `emo_yawn`,
/// `emo_sleepy`, `emo_upset`, `emo_love`). Исходник и сборка — `docs/rive-bear.md`.
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
  upset(19.4, 1.4),

  /// Любовь, нежность (ТЗ `emo_love_s45`, 27.09) — десятая кнопка.
  tenderness(5.85, 2.0),

  /// Поглаживание головы (ТЗ `act_pet`, 27.09): живой отклик на палец —
  /// кнопка играет «руку» по заданному пути ([_TrialPainter.scriptedPet]).
  pet(5.85, 3.4),

  /// Щекотка животика (ТЗ `act_pet_s45_b`, 27.09).
  tickle(4.4, 2.5),

  /// Резкий мазок — вздрогнул (27.09).
  startle(7.7, 0.7),

  /// Покой с настроением (ТЗ idle_happy…idle_dirty, 27.09): кнопка
  /// включает настроение, оно держится до другой кнопки настроения.
  /// ⚠ Пока только кнопками — по показателям включить позже (заказчик
  /// 27.09, вариант «Б»).
  moodHappy(0, 0),
  moodSad(0, 0),
  moodHungry(0, 0),
  moodSleepy(0, 0),
  moodDirty(0, 0),
  moodNormal(0, 0),

  /// Разнообразие покоя (ТЗ `idle_bonus_1…6`, 27.09): мишка сам раз в
  /// 15–30 с, пока его не трогают, делает что-то одно
  /// ([_TrialPainter._advanceBonus]); кнопки 20–25 — для проверки.
  bonusStretch(0, 0),
  bonusEar(0, 0),
  bonusListen(0, 0),
  bonusStep(0, 0),
  bonusShake(0, 0),
  bonusSigh(0, 0);

  const BearFace(this.frame, this.hold);

  /// Секунда `face_demo`, где выражение полное и голова стоит ровно.
  final double frame;

  /// Сколько держать, вместе с плавными входом и выходом.
  final double hold;

  /// Своя анимация в файле: её играют кости и лицо целиком, без
  /// застывшего кадра и без позы корпуса из приложения. `null` — пока нет.
  String? get clip => switch (this) {
    love => 'emo_smile',
    laugh => 'emo_laugh',
    surprised => 'emo_surprised',
    sad => 'emo_sad',
    chew => 'emo_chew',
    lick => 'emo_lick',
    yawn => 'emo_yawn',
    sleepy => 'emo_sleepy',
    upset => 'emo_upset',
    tenderness => 'emo_love',
    pet => null,
    tickle => 'act_pet_b',
    startle => 'pet_startle',
    moodHappy ||
    moodSad ||
    moodHungry ||
    moodSleepy ||
    moodDirty ||
    moodNormal => null,
    bonusStretch => 'idle_bonus_1',
    bonusEar => 'idle_bonus_2',
    bonusListen => 'idle_bonus_3',
    bonusStep => 'idle_bonus_4',
    bonusShake => 'idle_bonus_5',
    bonusSigh => 'idle_bonus_6',
  };

  /// Разбивка покоя — её мишка сам запускает в тишине.
  bool get bonus => name.startsWith('bonus');

  /// Какие разбивки подходят настроению (грустный не потягивается, сонный
  /// не прислушивается). Нет в таблице — подходят все.
  static const Map<String, List<BearFace>> bonusByMood = {
    'mood_sad': [bonusEar, bonusListen, bonusStep],
    'mood_hungry': [bonusListen, bonusStep, bonusShake],
    'mood_sleepy': [bonusStretch, bonusShake],
    'mood_dirty': [bonusEar, bonusShake],
  };

  /// Петля настроения в файле, если это кнопка настроения.
  String? get mood => switch (this) {
    moodHappy => 'mood_happy',
    moodSad => 'mood_sad',
    moodHungry => 'mood_hungry',
    moodSleepy => 'mood_sleepy',
    moodDirty => 'mood_dirty',
    moodNormal => 'mood_normal',
    _ => null,
  };

  /// Касания по очереди — все эмоции, для проверки (заказчик 26.09).
  static final List<BearFace> taps = [
    for (final face in values)
      if (face.mood == null && !face.bonus) face,
  ];

  /// Подпись на проверочной панели ([EmotionTestPanel]).
  String get label => switch (this) {
    love => 'Улыбка',
    laugh => 'Смех',
    surprised => 'Удивление',
    sad => 'Грусть',
    chew => 'Жуёт',
    lick => 'Смакует',
    yawn => 'Зевок',
    sleepy => 'Сонный',
    upset => 'Обида',
    tenderness => 'Любовь',
    pet => 'Гладим',
    tickle => 'Щекотка',
    startle => 'Вздрогнул',
    moodHappy => 'Покой: радость',
    moodSad => 'Покой: грусть',
    moodHungry => 'Покой: голод',
    moodSleepy => 'Покой: сон',
    moodDirty => 'Покой: грязнуля',
    moodNormal => 'Покой: обычный',
    bonusStretch => 'Потянулся',
    bonusEar => 'Ушко о плечо',
    bonusListen => 'Прислушался',
    bonusStep => 'Переступил',
    bonusShake => 'Встряхнулся',
    bonusSigh => 'Вздохнул',
  };

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
    tenderness => const BodyPose(tilt: 3.5, stretch: 0.02, lift: 0.01),
    _ => const BodyPose(),
  };
}

/// Где гладят: голова — ласка, животик — щекотно.
enum _PetZone { head, belly }

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
  const RiveBearTrial({super.key, required this.cue, this.onTap});

  final BearFaceCue cue;

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
    final mood = face.mood;
    if (mood != null) {
      _painter.setMood(mood);
      _bodyFace = null;
      return;
    }
    if (face == BearFace.pet) {
      _painter.scriptedPet();
      _bodyFace = null;
      return;
    }
    _painter.play(face);
    // Своя анимация (`emo_smile`) играет лицо и тело сама — поза корпуса
    // из приложения только у выражений без своей анимации.
    _bodyFace = face.clip == null ? face : null;
    _body
      ..duration = Duration(milliseconds: (face.hold * 1000).round())
      ..forward(from: 0);
  }

  /// Какое по счёту касание — выражения идут по кругу.
  int _taps = 0;

  // --- Поглаживание пальцем (ТЗ act_pet, заказчик 27.09) ---------------
  // Провели пальцем по голове — мишку гладят: лицо блаженное, голова
  // тянется к пальцу, на каждый проход проседает под ладонью. По животику —
  // щекотно. Резкий быстрый мазок — вздрогнул. Тап — как раньше.
  Size _size = Size.zero;
  final Stopwatch _panClock = Stopwatch();
  bool _panActive = false;
  _PetZone? _zone;

  /// Точка касания в координатах артборда 1024 × 1024 (мишка вписан по
  /// меньшей стороне и прижат к низу) и масштаб экран → артборд.
  (Offset, double) _toArtboard(Offset p) {
    final s = math.min(_size.width, _size.height) / 1024;
    if (s <= 0) return (Offset.zero, 1);
    final ox = (_size.width - 1024 * s) / 2;
    final oy = _size.height - 1024 * s;
    return (Offset((p.dx - ox) / s, (p.dy - oy) / s), s);
  }

  _PetZone? _zoneAt(Offset p) {
    final (a, _) = _toArtboard(p);
    if (a.dy < 545) return _PetZone.head;
    if (a.dy < 800) return _PetZone.belly;
    return null;
  }

  void _panStart(DragStartDetails d) {
    _panClock
      ..reset()
      ..start();
    _panActive = false;
    _zone = _zoneAt(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) {
    final zone = _zone;
    if (zone == null) return;
    // Ласка начинается, когда палец ведут дольше 0,12 с: быстрый мазок до
    // этого — не поглаживание, а «вздрогнул» (в [_panEnd]).
    if (!_panActive && _panClock.elapsedMilliseconds >= 120) {
      _panActive = true;
      if (zone == _PetZone.head) {
        _painter.petStart();
        _bodyFace = null;
      } else {
        _react(BearFace.tickle);
      }
      widget.onTap?.call();
    }
    if (_panActive && zone == _PetZone.head) {
      final (a, s) = _toArtboard(d.localPosition);
      _painter.petMove((a.dx - 512) / 180, d.delta.distance / s);
    }
  }

  void _panEnd(DragEndDetails d) {
    final speed = d.velocity.pixelsPerSecond.distance;
    final ms = _panClock.elapsedMilliseconds;
    _panClock.stop();
    if (_zone == null) return;
    if (!_panActive) {
      if (speed > 900) _react(BearFace.startle);
    } else if (_zone == _PetZone.head) {
      if (ms < 250 && speed > 1500) {
        _painter.petCancel();
        _react(BearFace.startle);
      } else {
        _painter.petEnd();
      }
    }
    _panActive = false;
  }

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
      onPanStart: _panStart,
      onPanUpdate: _panUpdate,
      onPanEnd: _panEnd,
      child: LayoutBuilder(
        builder: (context, box) {
          _size = box.biggest;
          return AnimatedBuilder(
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
          );
        },
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

  // --- Поглаживание (ТЗ act_pet, заказчик 27.09) ---------------------------
  // `pet_face` — лицо «гладят», нарастает 0,3 с и держится, пока гладят.
  // `pet_pass` — цикл «ладонь прошла по голове» (голова проседает и
  // тянется обратно, уши пружинят). Заказчик 27.09: «при каждом движении
  // пальцем голова дёргается» — раньше цикл запускался заново каждые
  // ~60 px пути пальца, и голова перескакивала из середины движения в
  // начало. Теперь цикл не перезапускается: он крутится непрерывно со
  // скоростью пальца (фаза), а сила плавно нарастает и затухает — палец
  // остановился, голова мягко возвращается. Наклон к пальцу — пружиной
  // (≈ 0,6 с на успокоение) по усреднённому положению пальца, а не за
  // каждым его движением. Отпустили — сила затухает, потом `pet_out`
  // (досмаковал, открыл глаза, посмотрел вверх, подпрыгнул). Клипы
  // собирает `tool/rive/rebuild_rig.py`.

  /// Наибольший наклон головы к пальцу, радианы (≈ 3°).
  static const double _maxLean = 0.05;

  /// Скорость пальца (px артборда в секунду), при которой цикл «ладонь»
  /// идёт в свою полную скорость и в полную силу.
  static const double _fullSpeed = 320;

  Animation? _petFace;
  Animation? _petPass;
  Animation? _petOut;
  Component? _eHead;
  bool _petting = false;
  bool _releasing = false;
  bool _outOn = false;
  double _faceT = 0;
  double _outT = 0;

  /// Фаза цикла «ладонь» (в циклах), его скорость (циклов в секунду) и сила 0…1.
  double _phase = 0;
  double _rate = 0;
  double _power = 0;

  /// Путь пальца за кадр и сглаженная скорость, px артборда.
  double _moved = 0;
  double _speed = 0;

  /// Куда тянется голова (−1…1, сглажено), наклон и его скорость (пружина).
  double _leanTarget = 0;
  double _leanAim = 0;
  double _lean = 0;
  double _leanV = 0;
  double? _script;

  /// Палец коснулся головы и повёл.
  void petStart() {
    _rest(_clip);
    _clip = null;
    _face = null;
    if (_outOn) _finishOut();
    _petting = true;
    _releasing = false;
    _faceT = 0;
    scheduleRepaint();
  }

  /// Палец идёт: [x] — где он по голове, −1 слева … 1 справа;
  /// [distance] — сколько прошёл, px артборда.
  void petMove(double x, double distance) {
    if (!_petting) return;
    _leanTarget = x.clamp(-1.0, 1.0);
    _moved += distance;
  }

  /// Палец отпустили — сила ласки затухает, потом выход.
  void petEnd() {
    if (_petting) _releasing = true;
  }

  /// Сразу в покой (резкий мазок, другая эмоция).
  void petCancel() {
    _script = null;
    _petting = false;
    _releasing = false;
    _power = 0;
    _rate = 0;
    _speed = 0;
    _petFace
      ?..time = 0
      ..apply(mix: 1);
    _petPass
      ?..time = 0
      ..apply(mix: 1);
    if (_outOn) _finishOut();
  }

  void _finishOut() {
    _outOn = false;
    final out = _petOut;
    if (out != null) {
      out
        ..time = out.duration
        ..apply(mix: 1);
    }
  }

  /// Кнопка «Гладим»: «рука» спокойно ходит по голове влево-вправо 3 с,
  /// потом отпускает.
  void scriptedPet() {
    petStart();
    _script = 0;
  }

  /// Сглаживание: [v] к [to] за время [tau] секунд.
  static double _ease(double v, double to, double dt, double tau) =>
      v + (to - v) * math.min(1.0, dt / tau);

  void _advancePet(double dt) {
    if (dt <= 0) return;
    final script = _script;
    if (script != null) {
      final t = script + dt;
      _script = t;
      // ладонь ходит по голове: туда-обратно за 1,6 с, ~260 px/с
      final x = math.sin(2 * math.pi * t / 1.6);
      petMove(x, 260 * dt);
      if (t >= 3.0) {
        _script = null;
        petEnd();
      }
    }
    // скорость пальца — сглаженная, без рывков от неровных касаний
    _speed = _ease(_speed, _moved / dt, dt, 0.2);
    _moved = 0;
    final pass = _petPass;
    if (_petting) {
      _faceT += dt;
      final face = _petFace;
      if (face != null) {
        face
          ..time = math.min(_faceT, face.duration)
          ..apply(mix: 1);
      }
      final k = (_speed / _fullSpeed).clamp(0.0, 1.0);
      final going = !_releasing;
      final passLen = pass?.duration ?? 0.8;
      // цикл идёт со скоростью пальца (не быстрее своей), сила — мягко
      _rate = _ease(_rate, going ? k / passLen : 0.6 / passLen, dt, 0.3);
      _power = _ease(_power, going ? math.min(1.0, k * 1.4) : 0.0, dt, 0.35);
      _phase += _rate * dt;
      if (pass != null) {
        // сначала покой, потом цикл с силой _power: у костей эмоции нет
        // другого источника значений, иначе mix копится от кадра к кадру
        pass
          ..time = 0
          ..apply(mix: 1)
          ..time = (_phase % 1) * pass.duration
          ..apply(mix: _power);
      }
      if (_releasing && _power < 0.03) {
        pass
          ?..time = 0
          ..apply(mix: 1);
        _petting = false;
        _releasing = false;
        _power = 0;
        _outOn = true;
        _outT = 0;
      }
    }
    if (_outOn) {
      _outT += dt;
      final out = _petOut;
      if (out == null || _outT >= out.duration) {
        _finishOut();
      } else {
        out
          ..time = _outT
          ..apply(mix: 1);
      }
    }
    // наклон к пальцу: цель — усреднённое положение пальца (0,35 с),
    // голова идёт к ней пружиной без перелёта (≈ 0,6 с)
    _leanAim = _ease(_leanAim, _petting ? _leanTarget : 0.0, dt, 0.35);
    const w = 7.0;
    final acc = w * w * (_leanAim * _maxLean - _lean) - 2 * w * _leanV;
    _leanV += acc * dt;
    _lean += _leanV * dt;
    final head = _eHead;
    if (head != null &&
        (_petting || _lean.abs() > 1e-4 || _leanV.abs() > 1e-4)) {
      if (!_petting && _lean.abs() <= 2e-4 && _leanV.abs() <= 2e-4) {
        _lean = 0;
        _leanV = 0;
      }
      // поверх того, что поставили петля настроения и клипы в этом кадре
      // (петля каждый кадр задаёт поворот заново — прибавка не копится)
      head.rotation = head.rotation + _lean;
    }
  }

  // --- Покой с настроением (ТЗ idle_*; заказчик 27.09) ----------------------
  // Петля настроения `mood_*` (12 с) ложится на `idle_life` и крутится всё
  // время; смена настроения — плавное перетекание за 1,5 с. Все петли
  // ключуют один набор каналов, поэтому «старая с силой 1, новая с силой
  // w» даёт ровную смесь. Темп дыхания — скорость `idle_life` (ТЗ §5.10).
  static const Map<String, double> _moodSpeed = {
    'mood_happy': 1.15,
    'mood_sad': 0.8,
    'mood_sleepy': 0.75,
  };
  final Map<String, Animation> _moods = {};
  String _mood = 'mood_normal';
  String _moodPrev = 'mood_normal';
  double _moodW = 1;
  double _moodT = 0;

  void setMood(String name) {
    if (name == _mood) return;
    // перетекание из текущей смеси: прежним считаем то, что сейчас сильнее
    _moodPrev = _moodW >= 0.5 ? _mood : _moodPrev;
    _mood = name;
    _moodW = 0;
    scheduleRepaint();
  }

  double _idleSpeed() {
    final a = _moodSpeed[_moodPrev] ?? 1.0;
    final b = _moodSpeed[_mood] ?? 1.0;
    return a + (b - a) * _moodW;
  }

  void _advanceMood(double dt) {
    final cur = _moods[_mood];
    if (cur == null) return;
    _moodW = math.min(1.0, _moodW + dt / 1.5);
    _moodT += dt;
    final w = Curves.easeInOut.transform(_moodW);
    final prev = _moods[_moodPrev];
    if (prev != null && _moodW < 1) {
      prev
        ..time = _moodT % prev.duration
        ..apply(mix: 1);
      cur
        ..time = _moodT % cur.duration
        ..apply(mix: w);
    } else {
      cur
        ..time = _moodT % cur.duration
        ..apply(mix: 1);
    }
  }

  // --- Разнообразие покоя (ТЗ idle_bonus_1…6; заказчик 27.09) --------------
  // Пока мишку не трогают и эмоция не идёт, отсчитывается случайная пауза
  // 15–30 с, потом — одна разбивка, подходящая настроению, не та же, что в
  // прошлый раз. Любое касание или эмоция начинают отсчёт заново.
  final math.Random _random = math.Random();
  double? _bonusWait;
  BearFace? _lastBonus;

  void _advanceBonus(double dt) {
    final busy =
        _clip != null || _face != null || _petting || _outOn || _script != null;
    if (busy) {
      _bonusWait = null;
      return;
    }
    final wait = (_bonusWait ??= 15 + _random.nextDouble() * 15) - dt;
    _bonusWait = wait;
    if (wait > 0) return;
    _bonusWait = null;
    final pool = [
      for (final face
          in BearFace.bonusByMood[_mood] ??
              BearFace.values.where((f) => f.bonus))
        if (face != _lastBonus && _clips.containsKey(face.clip)) face,
    ];
    if (pool.isEmpty) return;
    final face = pool[_random.nextInt(pool.length)];
    _lastBonus = face;
    play(face);
  }

  void play(BearFace face) {
    petCancel();
    // Прежняя эмоция ещё идёт — вернуть её в покой, иначе её лицо и поза
    // остаются поверх новой (заказчик 26.09: после каждой кнопки мишка
    // должен возвращаться в обычное состояние).
    _rest(_clip);
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

  /// Первый кадр каждой эмоции — покой: лицо-накладки скрыты, кости
  /// эмоции на месте.
  void _rest(Animation? clip) {
    if (clip == null) return;
    clip.time = 0;
    clip.apply(mix: 1);
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
    _petFace?.dispose();
    _petPass?.dispose();
    _petOut?.dispose();
    _petFace = artboard.animationNamed('pet_face');
    _petPass = artboard.animationNamed('pet_pass');
    _petOut = artboard.animationNamed('pet_out');
    for (final clip in _moods.values) {
      clip.dispose();
    }
    _moods.clear();
    for (final name in const [
      'mood_normal',
      'mood_happy',
      'mood_sad',
      'mood_hungry',
      'mood_sleepy',
      'mood_dirty',
    ]) {
      final animation = artboard.animationNamed(name);
      if (animation != null) _moods[name] = animation;
    }
    _eHead = artboard.component('e_head');
    notifyListeners();
  }

  @override
  bool advance(double elapsedSeconds) {
    _idle?.advanceAndApply(elapsedSeconds * _idleSpeed());
    _advanceMood(elapsedSeconds);
    final clip = _clip;
    if (clip != null) {
      // Своя анимация поверх покоя; края смешиваются за 0,15 с, чтобы
      // покой и первая поза анимации не расходились рывком.
      clip.advance(elapsedSeconds);
      final t = clip.time;
      final left = clip.duration - t;
      if (left <= 0) {
        _rest(clip);
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
    _advancePet(elapsedSeconds);
    _advanceBonus(elapsedSeconds);
    super.advance(0);
    return true;
  }

  @override
  void dispose() {
    _idle?.dispose();
    _faces?.dispose();
    _petFace?.dispose();
    _petPass?.dispose();
    _petOut?.dispose();
    for (final clip in _moods.values) {
      clip.dispose();
    }
    for (final clip in _clips.values) {
      clip.dispose();
    }
    super.dispose();
  }
}

/// ⚠ ПРОВЕРОЧНАЯ ПАНЕЛЬ — снять перед публикацией (заказчик 26.09: «кнопки
/// 1, 2, 3… с правой стороны, подпиши каждую эмоцию — так проще вносить
/// корректировки»). Номер и название: нажали — мишка играет эту эмоцию.
/// Кнопок стало 25 — две колонки: эмоции 1–13 справа от мишки
/// ([emotions]), покой и разбивки 14–25 слева ([idle]).
class EmotionTestPanel extends StatefulWidget {
  const EmotionTestPanel.emotions({super.key, required this.cue})
    : idle = false;

  const EmotionTestPanel.idle({super.key, required this.cue}) : idle = true;

  final BearFaceCue cue;

  /// Колонка покоя (настроения и разбивки) — иначе эмоций.
  final bool idle;

  @override
  State<EmotionTestPanel> createState() => _EmotionTestPanelState();
}

class _EmotionTestPanelState extends State<EmotionTestPanel> {
  @override
  void initState() {
    super.initState();
    widget.cue.addListener(_changed);
  }

  @override
  void didUpdateWidget(EmotionTestPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cue != widget.cue) {
      oldWidget.cue.removeListener(_changed);
      widget.cue.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.cue.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final current = widget.cue.face;
    final idle = widget.idle;
    return Column(
      key: ValueKey(idle ? 'emotion-test-panel-idle' : 'emotion-test-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: idle
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        for (final (i, face) in BearFace.values.indexed)
          if ((face.mood != null || face.bonus) == idle)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _EmotionButton(
                number: i + 1,
                face: face,
                selected: face == current,
                onTap: () => widget.cue.show(face),
              ),
            ),
      ],
    );
  }
}

class _EmotionButton extends StatelessWidget {
  const _EmotionButton({
    required this.number,
    required this.face,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final BearFace face;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF3B2A1E);
    return GestureDetector(
      key: ValueKey('emotion-test-${face.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.only(left: 3, right: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFE3A3)
              : Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? const Color(0xFFE0A33A) : const Color(0x33000000),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE0A33A) : ink,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              face.label,
              style: const TextStyle(
                color: ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

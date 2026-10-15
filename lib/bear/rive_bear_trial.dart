import 'dart:math' as math;

import 'package:flutter/material.dart' hide Animation;
import 'package:rive/rive.dart';

import 'bear_rig_spec.dart';

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

/// Девочка JOY (КП 2.4, заказчик 14.10: «второго героя тоже так же
/// анимировать»): тот же риг и те же клипы, её слои, бант и юбка
/// (`tool/rive/build_girl.py`, `docs/rive-girl.md`).
const String kGirlBearAsset = 'assets/rive/bear_girl.riv';

/// Файл мишка нужного героя.
String bearAsset(BearSkin skin) =>
    skin == BearSkin.girl ? kGirlBearAsset : kTrialBearAsset;

/// Артборд в файле героя.
String bearArtboard(BearSkin skin) =>
    skin == BearSkin.girl ? 'Bear_Girl' : 'Bear_Boy';

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
  bonusSigh(0, 0),

  /// Характер (ТЗ `idle_trait_*`, 27.09): кнопка включает характер для
  /// проверки вместо настоящего (сервер, `BearTraitTracker`); держится до
  /// другой кнопки характера.
  traitActive(0, 0),
  traitCurious(0, 0),
  traitAffectionate(0, 0),
  traitCalm(0, 0),
  traitIndependent(0, 0),
  traitReserved(0, 0),

  /// Реакции характера (ТЗ `reaction_trait_*_touch` / `*_treat`): на
  /// касание — это и тап по мишке (заказчик 27.09); на угощение.
  touch(0, 0),
  treat(0, 0);

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
    traitActive ||
    traitCurious ||
    traitAffectionate ||
    traitCalm ||
    traitIndependent ||
    traitReserved ||
    touch ||
    treat => null,
  };

  /// Заказчик утвердил — кнопка на проверочной панели больше не нужна
  /// (заказчик 27.09: «которые утвердил — прятать, показывать только новые»).
  /// Утверждены 1–33 (27.09); клипы и поведение остаются в работе.
  bool get approved => index <= treat.index;

  /// Характер, если это кнопка характера.
  BearTrait? get trait => switch (this) {
    traitActive => BearTrait.active,
    traitCurious => BearTrait.curious,
    traitAffectionate => BearTrait.affectionate,
    traitCalm => BearTrait.calm,
    traitIndependent => BearTrait.independent,
    traitReserved => BearTrait.reserved,
    _ => null,
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

  /// Подпись на проверочной ленте эмоций (`EmotionTestStrip`).
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
    traitActive => 'Активный',
    traitCurious => 'Любознательный',
    traitAffectionate => 'Ласковый',
    traitCalm => 'Спокойный',
    traitIndependent => 'Самостоятельный',
    traitReserved => 'Замкнутый',
    touch => 'Касание',
    treat => 'Угощение',
  };

  /// Подпись для героя: у девочки — в женском роде (заказчик 14.10:
  /// «подписи сделай в женском роде»).
  String labelFor(BearSkin hero) {
    if (hero != BearSkin.girl) return label;
    return switch (this) {
      sleepy => 'Сонная',
      startle => 'Вздрогнула',
      bonusStretch => 'Потянулась',
      bonusListen => 'Прислушалась',
      bonusStep => 'Переступила',
      bonusShake => 'Встряхнулась',
      bonusSigh => 'Вздохнула',
      traitActive => 'Активная',
      traitCurious => 'Любознательная',
      traitAffectionate => 'Ласковая',
      traitCalm => 'Спокойная',
      traitIndependent => 'Самостоятельная',
      traitReserved => 'Замкнутая',
      _ => label,
    };
  }

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

  /// ⚠ Проверка второго героя (заказчик 14.10): какого героя показать
  /// вместо настоящего (пол выдаёт сервер при рождении, КП 2.4) — плитка
  /// «Мальчик / Девочка» в проверочной ленте эмоций; null — настоящий.
  /// Держится до перезапуска, как кнопки характера, на сервер не уходит.
  /// Снять вместе с лентой перед публикацией.
  final ValueNotifier<BearSkin?> hero = ValueNotifier<BearSkin?>(null);

  void show(BearFace face) {
    _face = face;
    _serial++;
    notifyListeners();
  }

  /// Герой на экране: проверочный, если выбран, иначе настоящий [skin].
  BearSkin heroOr(BearSkin skin) => hero.value ?? skin;

  @override
  void dispose() {
    hero.dispose();
    super.dispose();
  }
}

class RiveBearTrial extends StatefulWidget {
  const RiveBearTrial({
    super.key,
    required this.cue,
    this.trait = BearTrait.active,
    this.mood = BearMood.normal,
    this.seated = false,
    this.asleep = false,
    this.headOnly = false,
    this.breath,
    this.reachBottom,
    this.onTap,
    this.skin = BearSkin.boy,
  });

  /// Герой (КП 2.4): мальчик или девочка — свой файл рига. Проверочная
  /// плитка ленты ([BearFaceCue.hero]) подменяет его до перезапуска.
  final BearSkin skin;

  /// Уложили спать («Сон», заказчик 10.10): сначала сонное настроение —
  /// тяжёлые веки, медленное моргание, — потом засыпает: петля сна
  /// `idle_asleep`, глаза закрыты. Сняли — глаза открываются быстро, покой
  /// возвращается. Пока спит, эмоции и разбивки покоя не идут.
  final bool asleep;

  /// Только голова в капюшоне (кухня, заказчик 11.10: «возьми предыдущего
  /// мишку, его одежду… наложи»): тело рига гаснет (поза `pose_body_off`),
  /// под голову кладётся кофта с рукавами и лапами прежнего мишка.
  final bool headOnly;

  /// Дыхание мишка для слоёв вокруг него (одеяло спальни, кофта за
  /// кухонным столом): каждый кадр — насколько он сейчас вдохнул, от −1
  /// (конец выдоха) до +1 (вершина вдоха в игровой; за столом размах 0,6,
  /// во сне свой), вздохи и зевки эмоций прибавляются. Из кости вдоха
  /// рига — слои дышат ровно с ним.
  final ValueNotifier<double>? breath;

  /// Ниже этой линии (в координатах артборда 1024) мишку не видно — на
  /// кухне там скатерть: ласка и щекотка оттуда не начинаются.
  final double? reachBottom;

  /// Сидит за столом (кухня) или лежит в кровати («Сон»): вертикальные
  /// подскоки корпуса гасятся — пружинка «активного», прыжок «радости»,
  /// подскоки реакций. Дышит спокойно — петля `idle_calm`: вдох-выдох 6 с
  /// вместо 3 с игровой и мельче (заказчик 11.10: «на кухне и в спальне
  /// дыхание намного медленнее, в основной комнате оставь»). Голова, уши,
  /// лицо, моргание и покачивания в стороны — как в игровой.
  final bool seated;

  final BearFaceCue cue;

  /// Состояние покоя по показателям (`BearLife`, с гистерезисом): петля
  /// `mood_*`; обычное — покой характера.
  final BearMood mood;

  /// Характер мишки (КП 7.1–7.4): покой, реакции, разбивки. ⚠ ждёт
  /// согласования: по ТЗ характер виден только на стадиях 4–5; пока
  /// Rive-мишка один на все стадии — показываем всегда (заказчик 27.09).
  final BearTrait trait;

  /// Касание мишки (КП 3.1).
  final VoidCallback? onTap;

  @override
  State<RiveBearTrial> createState() => _RiveBearTrialState();
}

class _RiveBearTrialState extends State<RiveBearTrial>
    with SingleTickerProviderStateMixin {
  File? _file;

  /// Чей файл загружен ([_file]) и чей грузится.
  BearSkin? _fileSkin;
  BearSkin? _loading;
  late final _TrialPainter _painter = _TrialPainter()
    ..seated = widget.seated
    ..headOnly = widget.headOnly
    ..breath = widget.breath
    ..setAsleep(widget.asleep, instant: true);

  /// Реакция корпуса на эмоцию — длиной с саму эмоцию.
  late final AnimationController _body = AnimationController(vsync: this);
  BearFace? _bodyFace;

  /// Эмоция целиком: лицо из файла и поза корпуса.
  void _react(BearFace face) {
    // спящий не смеётся и не машет ушами по кнопкам
    if (widget.asleep) return;
    final trait = face.trait;
    if (trait != null) {
      _painter.setTrait(trait);
      _bodyFace = null;
      return;
    }
    if (face == BearFace.touch || face == BearFace.treat) {
      _painter.playReaction(treat: face == BearFace.treat);
      _bodyFace = null;
      return;
    }
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
    final reach = widget.reachBottom;
    if (reach != null && a.dy > reach) return null;
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
    _painter.setTrait(widget.trait, real: true);
    _painter.setMood('mood_${widget.mood.name}', real: true);
    widget.cue.hero.addListener(_load);
    _load();
  }

  /// Файл героя на экране; сменился герой — грузится его файл, прежний
  /// показывается, пока новый не готов.
  void _load() {
    final skin = widget.cue.heroOr(widget.skin);
    if (skin == _loading || (skin == _fileSkin && _loading == null)) return;
    _loading = skin;
    final asset = bearAsset(skin);
    File.asset(asset, riveFactory: Factory.rive)
        .then((file) {
          if (!mounted || _loading != skin) {
            file?.dispose();
            return;
          }
          final old = _file;
          setState(() {
            _file = file;
            _fileSkin = skin;
            _loading = null;
          });
          if (old != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          }
        })
        .catchError((Object error) {
          if (_loading == skin) _loading = null;
          debugPrint('[TeddyTales] $asset не загрузился: $error');
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
      oldWidget.cue.hero.removeListener(_load);
      widget.cue.hero.addListener(_load);
    }
    if (oldWidget.skin != widget.skin || oldWidget.cue != widget.cue) _load();
    if (oldWidget.trait != widget.trait) {
      _painter.setTrait(widget.trait, real: true);
    }
    if (oldWidget.mood != widget.mood) {
      _painter.setMood('mood_${widget.mood.name}', real: true);
    }
    if (oldWidget.asleep != widget.asleep) {
      _painter.setAsleep(widget.asleep);
    }
  }

  @override
  void dispose() {
    widget.cue.removeListener(_onCue);
    widget.cue.hero.removeListener(_load);
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
      // Тап — реакция характера на касание (ТЗ `reaction_trait_*_touch`;
      // заказчик 27.09: «тап переключи на реакцию»).
      onTap: () {
        _react(BearFace.touch);
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
            builder: (context, child) {
              final body = _bodyTransform(box.maxHeight);
              return Transform(
                alignment: const Alignment(0, 0.92),
                transform: body,
                child: child,
              );
            },
            child: RiveFileWidget(
              key: ValueKey(_fileSkin),
              file: file,
              painter: _painter,
              artboardName: bearArtboard(_fileSkin ?? BearSkin.boy),
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
    // за столом не подпрыгивает: лапы лежат на столе (заказчик 27.09)
    final lift = widget.seated ? 0.0 : pose.lift;
    return Matrix4.identity()
      ..translateByDouble(0, -lift * k * height, 0, 1)
      ..rotateZ(pose.tilt * k * math.pi / 180)
      ..scaleByDouble(sx, sy, 1, 1);
  }
}

/// Покой `idle_life` всё время, поверх — отрезок `face_demo` с плавным
/// входом и выходом.
/// Пружина с затуханием: [kick] — толчок скорости, [step] — шаг времени.
/// Частота — сколько раз в секунду качается, затухание — доля от
/// критического (меньше — дольше качается).
class _Spring {
  _Spring({required double freq, required double damping, required this.limit})
    : _k = math.pow(2 * math.pi * freq, 2).toDouble(),
      _c = 2 * damping * 2 * math.pi * freq;

  final double _k;
  final double _c;

  /// Дальше этого кончик не уходит.
  final double limit;

  double x = 0;
  double v = 0;

  void kick(double dv) => v += dv;

  void step(double dt) {
    var left = math.min(dt, 0.1);
    while (left > 0) {
      final h = math.min(left, 1 / 120);
      v += (-_k * x - _c * v) * h;
      x = (x + v * h).clamp(-limit, limit);
      left -= h;
    }
  }
}

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
  Component? _eHips;
  double _hipsRestY = 0;

  /// Сидит за столом или лежит в кровати — корпус не подпрыгивает, дышит
  /// спокойно ([_calm]).
  bool seated = false;

  /// Только голова: тело рига гаснет ([_bodyOff]).
  bool headOnly = false;

  /// Куда писать вдох для слоёв вокруг мишка ([RiveBearTrial.breath]).
  ValueNotifier<double>? breath;

  /// Спокойный покой (`idle_calm`): тот же `idle_life`, но вдох-выдох 6 с
  /// и мельче — за столом и в кровати.
  Animation? _calm;

  /// Поза «тело спрятано» (`pose_body_off`) — ставится поверх всего.
  Animation? _bodyOff;

  /// Кость вдоха: покой и сон двигают `b_breath`, эмоции — `e_breath`.
  /// Масштаб по высоте в покое 1 … 1,065 (`breathing` в rebuild_rig.py):
  /// середина [_breathMid], полразмаха [_breathHalf].
  Component? _bBreath;
  Component? _eBreath;
  static const double _breathMid = 1.0325;
  static const double _breathHalf = 0.0325;

  // Руки сидящего укорочены и почти не повёрнуты — так они уходят под
  // край одеяла в кровати («Сон», 11.10). История: 27.09–11.10 так же
  // клались руки на кухонный стол (рука к зрителю, лапа на кромке), но
  // сплющенный рукав рига давал «крылышки» и заломы (заказчик 11.10:
  // «лапки короткие… складки, когда он дышит»). С 11.10 на кухне тело
  // рига спрятано ([headOnly]), кофта и лапы — прежнего мишка.
  // Смещения прибавляются к тому, что поставили клипы, и снимаются до
  // следующего кадра: покачивания рук из клипов остаются.
  static const double _seatTurn = 0.06;
  static const double _seatUpper = 0.6;
  static const double _seatShorten = 0.56;
  Component? _eArmL1;
  Component? _eArmR1;
  Component? _eArmL2;
  Component? _eArmR2;
  bool _seatOn = false;

  // Докачка (заказчик 10.10: «чтобы мишка был живым»). Кончики ушей и
  // капюшона — свои звенья рига (`ear_l3`, `ear_r3`, `hood3`), щёки — кости
  // лица; их раскачивают пружины от настоящего движения головы, а не
  // нарисованные кривые: резко повернулся — уши качнулись сильнее, плавно —
  // едва, подпрыгнул — щёки вздрогнули. Затухают сами.
  Component? _bHead;
  Component? _eEarL3;
  Component? _eEarR3;
  Component? _eHood3;
  Component? _eCheekL;
  Component? _eCheekR;
  double _earL3Rest = 0;
  double _earR3Rest = 0;
  double _hood3Rest = 0;
  final _Spring _earL = _Spring(freq: 4.2, damping: 0.22, limit: 0.3);
  final _Spring _earR = _Spring(freq: 3.9, damping: 0.22, limit: 0.3);
  final _Spring _hoodTip = _Spring(freq: 2.6, damping: 0.18, limit: 0.3);
  final _Spring _cheeks = _Spring(freq: 6.0, damping: 0.3, limit: 3);

  // Бант девочки (14.10) — петли от узла на макушке (`bow_lo` вниз-вправо
  // с хвостом, `bow_up` вверх-влево), качаются так же, как кончики ушей.
  // Петли длиннее ушей втрое — толчок меньше, кончик отходит столько же.
  // У мальчика этих костей нет — пружины стоят.
  Component? _eBowLo;
  Component? _eBowUp;
  double _bowLoRest = 0;
  double _bowUpRest = 0;
  final _Spring _bowLo = _Spring(freq: 2.4, damping: 0.16, limit: 0.14);
  final _Spring _bowUp = _Spring(freq: 3.0, damping: 0.2, limit: 0.14);

  /// Голова в прошлом кадре: положение (px артборда), угол и их скорости.
  double? _headX;
  double? _headY;
  double? _headA;
  double _headVx = 0;
  double _headVy = 0;
  double _headVa = 0;

  /// Сколько прибавлено к щекам в прошлом кадре — снимается до клипов.
  double _cheekOn = 0;

  // Чувствительность: на сколько толкает пружину перемена скорости головы
  // (px/с — вбок и вверх-вниз, рад/с — поворот).
  static const double _earSide = 0.088;
  static const double _earUp = 0.05;
  static const double _earTurn = 5.3;
  static const double _hoodSide = 0.072;
  static const double _hoodTurn = 4.9;
  static const double _cheekUp = 1.26;
  // бант: толчок поперёк петли (доли — направление петли от узла)
  static const double _bowSide = 0.03;
  static const double _bowTurn = 4.0;

  void _jiggleOff() {
    if (_cheekOn == 0) return;
    _eCheekL?.x -= _cheekOn;
    _eCheekR?.x -= _cheekOn;
    _cheekOn = 0;
  }

  /// Пружины — на кадр вперёд, кончики — на место.
  void _jiggleApply(double dt) {
    for (final s in [_earL, _earR, _hoodTip, _cheeks, _bowLo, _bowUp]) {
      s.step(dt);
    }
    _eEarL3?.rotation = _earL3Rest + _earL.x;
    _eEarR3?.rotation = _earR3Rest + _earR.x;
    _eHood3?.rotation = _hood3Rest + _hoodTip.x;
    _eBowLo?.rotation = _bowLoRest + _bowLo.x;
    _eBowUp?.rotation = _bowUpRest + _bowUp.x;
    // у костей лица ось x смотрит вверх
    _cheekOn = _cheeks.x;
    _eCheekL?.x += _cheekOn;
    _eCheekR?.x += _cheekOn;
  }

  /// Как двинулась голова за кадр — толчок пружинам. Голова разогналась
  /// вправо — кончики отстают влево; пошла вверх — уши и щёки опускаются.
  void _jiggleMeasure(double dt) {
    final m = _bHead?.worldTransform;
    if (m == null || dt <= 0) return;
    final x = m[4];
    final y = m[5];
    final a = math.atan2(m[1], m[0]);
    final px = _headX;
    final py = _headY;
    final pa = _headA;
    _headX = x;
    _headY = y;
    _headA = a;
    if (px == null || py == null || pa == null) return;
    var da = a - pa;
    while (da > math.pi) {
      da -= 2 * math.pi;
    }
    while (da < -math.pi) {
      da += 2 * math.pi;
    }
    final vx = (x - px) / dt;
    final vy = (y - py) / dt;
    final va = da / dt;
    // Скачок (переход комнаты, первый кадр после паузы) — не толчок.
    final dvx = (vx - _headVx).clamp(-400.0, 400.0);
    final dvy = (vy - _headVy).clamp(-400.0, 400.0);
    final dva = (va - _headVa).clamp(-8.0, 8.0);
    _headVx = vx;
    _headVy = vy;
    _headVa = va;
    _earL.kick(-_earSide * dvx + _earUp * dvy - _earTurn * dva);
    _earR.kick(-_earSide * dvx - _earUp * dvy - _earTurn * dva);
    _hoodTip.kick(-_hoodSide * dvx - _hoodTurn * dva);
    _cheeks.kick(_cheekUp * dvy);
    // кончик отстаёт против разгона; поворот кости на +угол уводит его
    // поперёк петли: нижняя (105, 101) от узла, верхняя (−63, −96)
    _bowLo.kick(_bowSide * (0.69 * dvx - 0.72 * dvy) - _bowTurn * dva);
    _bowUp.kick(_bowSide * (-0.84 * dvx + 0.55 * dvy) - _bowTurn * dva);
  }

  // --- Сон («Сон», заказчик 10.10; ТЗ idle_asleep) -------------------------
  // Уложили: 2,6 с сонного настроения (тяжёлые веки, медленное моргание),
  // потом петля сна `idle_asleep` подмешивается к покою за 1,2 с: голова
  // склоняется, дыхание медленное и глубокое, оглядывания гаснут. Глаза
  // закрываются как в моргании покоя: бусины сплющиваются в черту
  // (`pose_eyes_squash`), и когда они черта — разом закрытые глаза с
  // ресничками (`pose_eyes_shut`). Плавно проявлять закрытые глаза поверх
  // открытых бусин нельзя — видно оба. Разбудили — за 0,3 с обратно.
  // Засыпание целиком 3,8 с: облако мыслей спальни ждёт 4 с.
  static const double _dozeHold = 2.6;
  static const double _dozeIn = 1.2;
  static const double _wakeOut = 0.3;

  bool _asleep = false;
  double _dozeT = 0;
  double _sleepW = 0;
  double _sleepT = 0;
  Animation? _sleepIdle;
  Animation? _eyesSquash;
  Animation? _eyesShut;

  bool get _deepSleep => _asleep && _dozeT >= _dozeHold;

  /// [instant] — сразу спит (открыли «Сон», а мишку уже уложили).
  void setAsleep(bool value, {bool instant = false}) {
    if (value == _asleep) return;
    _asleep = value;
    _dozeT = value && instant ? _dozeHold : 0;
    if (instant) _sleepW = value ? 1 : 0;
    if (value) {
      petCancel();
      _rest(_clip);
      _clip = null;
      _face = null;
    }
    _loopTo(_loopName());
    scheduleRepaint();
  }

  void _advanceSleep(double dt) {
    if (_asleep) {
      final was = _dozeT;
      _dozeT += dt;
      // заснул — сонное настроение сменяется покоем без настроения
      if (was < _dozeHold && _dozeT >= _dozeHold) _loopTo(_loopName());
    }
    final target = _deepSleep ? 1.0 : 0.0;
    if (_sleepW < target) {
      _sleepW = math.min(target, _sleepW + dt / _dozeIn);
    } else if (_sleepW > target) {
      _sleepW = math.max(target, _sleepW - dt / _wakeOut);
    }
  }

  /// Петля сна поверх покоя — по тем же каналам костей.
  void _applySleepIdle(double dt) {
    final loop = _sleepIdle;
    if (loop == null || _sleepW <= 0) return;
    _sleepT += dt;
    loop
      ..time = _sleepT % loop.duration
      ..apply(mix: Curves.easeInOut.transform(_sleepW));
  }

  /// Глаза сплющиваются, пока петля сна набирает силу, и закрываются разом,
  /// когда бусины — черта. Проснулся — покой сам вернёт бусины и снимет
  /// закрытые глаза: он ставит их в каждом кадре.
  void _applySleepEyes() {
    final squash = ((_sleepW - 0.4) / 0.5).clamp(0.0, 1.0);
    if (squash <= 0) return;
    if (squash >= 1) {
      _eyesShut
        ?..time = 0
        ..apply(mix: 1);
    } else {
      _eyesSquash
        ?..time = 0
        ..apply(mix: Curves.easeIn.transform(squash));
    }
  }

  void _seatOff() {
    if (!_seatOn) return;
    _seatOn = false;
    _eArmL1?.rotation += _seatTurn;
    _eArmR1?.rotation -= _seatTurn;
    for (final e in [_eArmL1, _eArmR1]) {
      if (e != null) e.scaleX /= _seatUpper;
    }
    for (final e in [_eArmL2, _eArmR2]) {
      if (e != null) e.scaleX /= _seatShorten;
    }
  }

  void _seatApply() {
    if (!seated || _seatOn) return;
    _seatOn = true;
    _eArmL1?.rotation -= _seatTurn;
    _eArmR1?.rotation += _seatTurn;
    for (final e in [_eArmL1, _eArmR1]) {
      if (e != null) e.scaleX *= _seatUpper;
    }
    for (final e in [_eArmL2, _eArmR2]) {
      if (e != null) e.scaleX *= _seatShorten;
    }
  }

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

  // --- Характер (ТЗ idle_trait_*, reaction_trait_*; заказчик 27.09) ---------
  // Настроение важнее характера: при обычном настроении вместо
  // `mood_normal` играет петля характера `idle_trait_*` (тот же набор
  // каналов — перетекает как настроения); при особом настроении играет
  // настроение, а характер остаётся в темпе дыхания ([_traitSpeed]) и в
  // разбивках покоя ([_bonusRange], [_bonusLike]).
  static const Map<BearTrait, double> _traitSpeed = {
    BearTrait.active: 1.2,
    BearTrait.curious: 1.05,
    BearTrait.calm: 0.85,
    BearTrait.reserved: 0.95,
  };

  /// Пауза между разбивками покоя, секунды: от и до.
  static const Map<BearTrait, (double, double)> _bonusRange = {
    BearTrait.active: (10, 20),
    BearTrait.curious: (12, 25),
    BearTrait.affectionate: (15, 30),
    BearTrait.calm: (25, 40),
    BearTrait.independent: (20, 35),
    BearTrait.reserved: (25, 45),
  };

  /// Любимые разбивки характера — выпадают втрое чаще.
  static const Map<BearTrait, List<BearFace>> _bonusLike = {
    BearTrait.active: [BearFace.bonusStretch, BearFace.bonusStep],
    BearTrait.curious: [BearFace.bonusListen],
    BearTrait.affectionate: [BearFace.bonusSigh],
    BearTrait.calm: [BearFace.bonusSigh],
    BearTrait.independent: [BearFace.bonusShake],
    BearTrait.reserved: [BearFace.bonusEar],
  };

  BearTrait _trait = BearTrait.active;
  bool _traitForced = false;
  bool _moodForced = false;

  /// Выбранное настроение (`mood_*`); играет [_mood] — оно же или петля
  /// характера.
  String _moodPick = 'mood_normal';

  /// [real] — характер мишки из состояния; кнопка проверки его подменяет.
  void setTrait(BearTrait trait, {bool real = false}) {
    if (real && _traitForced) return;
    if (!real) _traitForced = true;
    _trait = trait;
    _loopTo(_loopName());
  }

  String _loopName() {
    // засыпает — сонное настроение; спит — петля спящего лица (полуулыбка)
    if (_asleep) {
      if (!_deepSleep) return 'mood_sleepy';
      return _moods.containsKey('mood_asleep') ? 'mood_asleep' : 'mood_normal';
    }
    if (_moodPick != 'mood_normal') return _moodPick;
    final name = 'idle_trait_${_trait.name}';
    return _moods.containsKey(name) ? name : 'mood_normal';
  }

  /// Реакция характера на касание или угощение.
  void playReaction({required bool treat}) {
    final name = 'reaction_trait_${_trait.name}_${treat ? 'treat' : 'touch'}';
    final clip = _clips[name];
    if (clip == null) return;
    petCancel();
    _rest(_clip);
    clip.time = 0;
    _clip = clip;
    _face = null;
    _t = 0;
    scheduleRepaint();
  }

  /// [real] — состояние по показателям (`BearLife`); кнопка проверки
  /// подменяет его до перезапуска.
  void setMood(String name, {bool real = false}) {
    if (real && _moodForced) return;
    if (!real) _moodForced = true;
    _moodPick = name;
    _loopTo(_loopName());
  }

  void _loopTo(String name) {
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
    return (a + (b - a) * _moodW) * (_traitSpeed[_trait] ?? 1.0);
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
        _clip != null ||
        _face != null ||
        _petting ||
        _outOn ||
        _script != null ||
        _asleep ||
        _sleepW > 0;
    if (busy) {
      _bonusWait = null;
      return;
    }
    final (lo, hi) = _bonusRange[_trait] ?? (15.0, 30.0);
    final wait = (_bonusWait ??= lo + _random.nextDouble() * (hi - lo)) - dt;
    _bonusWait = wait;
    if (wait > 0) return;
    _bonusWait = null;
    final like = _bonusLike[_trait] ?? const <BearFace>[];
    final pool = [
      for (final face
          in BearFace.bonusByMood[_moodPick] ??
              BearFace.values.where((f) => f.bonus))
        if (face != _lastBonus && _clips.containsKey(face.clip))
          for (var i = 0; i < (like.contains(face) ? 3 : 1); i++) face,
    ];
    if (pool.isEmpty) return;
    final face = pool[_random.nextInt(pool.length)];
    _lastBonus = face;
    play(face);
  }

  // --- Два рта — никогда, и в смесях тоже (заказчик 27.09) -----------------
  // Внутри каждого клипа прозрачности ртов уже по правилу (`check_mouths` в
  // сборке). Но петли настроения и характера перетекают друг в друга, а
  // эмоция ложится на петлю с плавными краями — и прозрачности тогда
  // смешиваются линейно: на 0,2 с видны полупрозрачная улыбка и
  // полупрозрачный ротик покоя. Поэтому после всех смешиваний прозрачности
  // ставятся заново по тому же правилу, что в сборке, от того, насколько
  // раскрыт каждый рот (датчики `mh_<вид>` в файле): рот виден, пока он
  // больше щёлочки, ротик покоя — ровно настолько, насколько его нет.
  static const List<String> _mouthKinds = [
    'open',
    'yawn',
    'chew',
    'sad',
    'pout',
    'sleepy',
    'content',
  ];

  /// Порог щёлочки — `MOUTH_SWAP` в `tool/rive/rebuild_rig.py`.
  static const double _mouthSwap = 0.06;

  final Map<String, Component> _mouthSignal = {};
  final Map<String, Animation> _mouthOp = {};
  Animation? _mouthZero;

  /// Какие рты сейчас включены — с гистерезисом: рот включается, когда
  /// раскрылся больше [_mouthSwap], выключается — когда закрылся до
  /// [_mouthOff]. В файле рот проходит зону смены за кадр, а в смеси
  /// (реакция поверх покоя, покой в покой) — медленно, и линейная
  /// перекрёстная прозрачность держала оба рта наполовину видимыми
  /// (заказчик 27.09: «при касании два рта»). Половинных состояний нет:
  /// либо один рот целиком, либо другой.
  /// Какой рот сейчас включён — один, самый раскрытый (заказчик 27.09,
  /// щекотка: смеющийся рот поверх ещё не ушедшей улыбки покоя — два рта).
  String? _mouthOn;
  static const double _mouthOff = 0.02;

  /// Когда у клипа закрывается рот — последний момент, где он раскрыт
  /// больше порога. Выход клипа в покой начинается с этого места: пока
  /// рот клипа закрывается, петля уже подмешивает свой, и улыбка перетекает
  /// в улыбку, а не захлопывается в ротик покоя (заказчик 27.09: «нет
  /// ровного перехода»). Меряется один раз при загрузке файла.
  final Map<Animation, double> _mouthCloseAt = {};

  void _measureMouths() {
    _mouthCloseAt.clear();
    if (_mouthSignal.length != _mouthKinds.length) return;
    for (final clip in _clips.values) {
      double? last;
      for (var t = clip.duration; t >= 0; t -= 1 / 15) {
        clip
          ..time = t
          ..apply(mix: 1);
        var h = 0.0;
        for (final signal in _mouthSignal.values) {
          h = math.max(h, signal.y);
        }
        if (h >= _mouthSwap) {
          last = t;
          break;
        }
      }
      clip
        ..time = 0
        ..apply(mix: 1);
      if (last != null && last < clip.duration - 0.1) {
        _mouthCloseAt[clip] = last;
      }
    }
  }

  void _resolveMouths() {
    final zero = _mouthZero;
    if (zero == null || _mouthSignal.length != _mouthKinds.length) return;
    // «Удивление» — фото-лицо со своим ртом, у него свои прозрачности.
    final clip = _clip;
    if (clip != null && clip == _clips['emo_surprised']) return;
    zero
      ..time = 0
      ..apply(mix: 1);
    String? best;
    var bestH = 0.0;
    for (final kind in _mouthKinds) {
      final h = math.max(0.0, _mouthSignal[kind]!.y);
      if (h > bestH) {
        bestH = h;
        best = kind;
      }
    }
    final on = _mouthOn;
    if (bestH >= _mouthSwap) {
      _mouthOn = best;
    } else if (on != null && math.max(0.0, _mouthSignal[on]!.y) <= _mouthOff) {
      _mouthOn = null;
    }
    _mouthOp[_mouthOn ?? 'rest']
      ?..time = 0
      ..apply(mix: 1);
  }

  // --- Эмоции сам по себе (заказчик 27.09: «если нет никаких действий, он
  // должен что-то показывать») ------------------------------------------
  // Раз в 40–90 с в тишине — эмоция по состоянию: голодный облизывается,
  // скучающе зевает, надувается; сонный зевает и клюёт носом; грустный
  // грустит, обижается; грязнуля встряхивается, трёт ушко; радостный
  // улыбается, смеётся, любит; обычный — улыбка и разбивки. Характер
  // сдвигает выбор: ласковый чаще показывает любовь, активный — смех,
  // спокойный реже всех, замкнутый чаще молчит. Подряд одно и то же — нет.
  static const Map<String, List<BearFace>> _spontByMood = {
    'mood_hungry': [
      BearFace.lick,
      BearFace.lick,
      BearFace.yawn,
      BearFace.upset,
    ],
    'mood_sleepy': [BearFace.yawn, BearFace.yawn, BearFace.sleepy],
    'mood_sad': [BearFace.sad, BearFace.upset, BearFace.bonusSigh],
    'mood_dirty': [BearFace.bonusShake, BearFace.bonusEar, BearFace.upset],
    'mood_happy': [BearFace.love, BearFace.laugh, BearFace.tenderness],
    'mood_normal': [BearFace.love, BearFace.bonusListen, BearFace.bonusStretch],
  };
  static const Map<BearTrait, BearFace> _spontLike = {
    BearTrait.affectionate: BearFace.tenderness,
    BearTrait.active: BearFace.laugh,
  };
  double? _spontWait;
  BearFace? _lastSpont;

  void _advanceSpont(double dt) {
    final busy =
        _clip != null ||
        _face != null ||
        _petting ||
        _outOn ||
        _script != null ||
        _moodW < 1 ||
        _asleep ||
        _sleepW > 0;
    if (busy) {
      _spontWait = null;
      return;
    }
    final slow = _trait == BearTrait.calm ? 1.6 : 1.0;
    final wait = (_spontWait ??= (40 + _random.nextDouble() * 50) * slow) - dt;
    _spontWait = wait;
    if (wait > 0) return;
    _spontWait = null;
    // замкнутый в семи случаях из десяти оставляет всё при себе
    if (_trait == BearTrait.reserved && _random.nextDouble() < 0.7) return;
    final like = _spontLike[_trait];
    final pool = [
      for (final face in _spontByMood[_moodPick] ?? const <BearFace>[])
        if (face != _lastSpont && _clips.containsKey(face.clip))
          for (var i = 0; i < (face == like ? 3 : 1); i++) face,
    ];
    if (pool.isEmpty) return;
    final face = pool[_random.nextInt(pool.length)];
    _lastSpont = face;
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
    _calm?.dispose();
    _calm = artboard.animationNamed('idle_calm');
    _bodyOff?.dispose();
    _bodyOff = artboard.animationNamed('pose_body_off');
    _bBreath = artboard.component('b_breath');
    _eBreath = artboard.component('e_breath');
    _faces = artboard.animationNamed('face_demo');
    for (final clip in _clips.values) {
      clip.dispose();
    }
    _clips.clear();
    for (final name in [
      for (final face in BearFace.values) ?face.clip,
      for (final trait in BearTrait.values)
        for (final kind in const ['touch', 'treat'])
          'reaction_trait_${trait.name}_$kind',
    ]) {
      if (_clips.containsKey(name)) continue;
      final animation = artboard.animationNamed(name);
      if (animation != null) _clips[name] = animation;
    }
    _petFace?.dispose();
    _petPass?.dispose();
    _petOut?.dispose();
    _petFace = artboard.animationNamed('pet_face');
    _petPass = artboard.animationNamed('pet_pass');
    _petOut = artboard.animationNamed('pet_out');
    _sleepIdle?.dispose();
    _eyesSquash?.dispose();
    _eyesShut?.dispose();
    _sleepIdle = artboard.animationNamed('idle_asleep');
    _eyesSquash = artboard.animationNamed('pose_eyes_squash');
    _eyesShut = artboard.animationNamed('pose_eyes_shut');
    for (final clip in _moods.values) {
      clip.dispose();
    }
    _moods.clear();
    for (final name in [
      'mood_normal',
      'mood_happy',
      'mood_sad',
      'mood_hungry',
      'mood_sleepy',
      'mood_dirty',
      'mood_asleep',
      for (final trait in BearTrait.values) 'idle_trait_${trait.name}',
    ]) {
      final animation = artboard.animationNamed(name);
      if (animation != null) _moods[name] = animation;
    }
    // петли характера загрузились только сейчас — выбрать заново
    _mood = 'mood_normal';
    _moodPrev = 'mood_normal';
    _moodW = 1;
    _loopTo(_loopName());
    _moodW = 1;
    _eHead = artboard.component('e_head');
    _eHips = artboard.component('e_hips');
    _hipsRestY = _eHips?.y ?? 0;
    _seatOn = false;
    _eArmL1 = artboard.component('e_arm_l1');
    _eArmR1 = artboard.component('e_arm_r1');
    _eArmL2 = artboard.component('e_arm_l2');
    _eArmR2 = artboard.component('e_arm_r2');
    _bHead = artboard.component('b_head');
    _eEarL3 = artboard.component('e_ear_l3');
    _eEarR3 = artboard.component('e_ear_r3');
    _eHood3 = artboard.component('e_hood3');
    _eCheekL = artboard.component('e_cheek_l');
    _eCheekR = artboard.component('e_cheek_r');
    _earL3Rest = _eEarL3?.rotation ?? 0;
    _earR3Rest = _eEarR3?.rotation ?? 0;
    _hood3Rest = _eHood3?.rotation ?? 0;
    _eBowLo = artboard.component('e_bow_lo');
    _eBowUp = artboard.component('e_bow_up');
    _bowLoRest = _eBowLo?.rotation ?? 0;
    _bowUpRest = _eBowUp?.rotation ?? 0;
    _cheekOn = 0;
    _headX = null;
    _mouthSignal.clear();
    for (final op in _mouthOp.values) {
      op.dispose();
    }
    _mouthOp.clear();
    _mouthZero?.dispose();
    _mouthZero = artboard.animationNamed('mop_zero');
    for (final kind in [..._mouthKinds, 'rest']) {
      final op = artboard.animationNamed('mop_$kind');
      if (op != null) _mouthOp[kind] = op;
      if (kind == 'rest') continue;
      final signal = artboard.component('mh_$kind');
      if (signal != null) _mouthSignal[kind] = signal;
    }
    _measureMouths();
    notifyListeners();
  }

  @override
  bool advance(double elapsedSeconds) {
    // Руки на столе: снять прошлые смещения, пока клипы не записали новые.
    _seatOff();
    _jiggleOff();
    _advanceSleep(elapsedSeconds);
    // Разбивку покоя запускаем до петли: сброс в покой при запуске
    // (`play` → `petCancel`) петля в этом же кадре перекроет.
    _advanceBonus(elapsedSeconds);
    _advanceSpont(elapsedSeconds);
    final idle = seated ? (_calm ?? _idle) : _idle;
    idle?.advanceAndApply(elapsedSeconds * _idleSpeed());
    _applySleepIdle(elapsedSeconds);
    // Кончилась анимация — вернуть её кости в покой до петли настроения,
    // а не после: иначе на один кадр мишка вставал в «чистый» покой поверх
    // позы характера и дёргался (заказчик 27.09, кнопки 32, 33).
    final clip = _clip;
    if (clip != null) {
      clip.advance(elapsedSeconds);
      if (clip.duration - clip.time <= 0) {
        _rest(clip);
        _clip = null;
      }
    }
    _advanceMood(elapsedSeconds);
    final live = _clip;
    if (live != null) {
      // Своя анимация поверх покоя. Края смешиваются за 0,35 с плавной
      // кривой: поза характера или настроения (голова ниже, взгляд в
      // сторону) перетекает в анимацию, а не перескакивает за 0,15 с.
      final t = live.time;
      final left = live.duration - t;
      const edge = 0.35;
      final closeAt = _mouthCloseAt[live];
      final outLen = closeAt == null
          ? edge
          : math.min(0.9, live.duration - closeAt + 0.25);
      final w = t < edge ? t / edge : (left < outLen ? left / outLen : 1.0);
      live.apply(mix: Curves.easeInOut.transform(w.clamp(0.0, 1.0)));
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
    _resolveMouths();
    _applySleepEyes();
    final hips = _eHips;
    if (seated && hips != null) hips.y = _hipsRestY;
    _seatApply();
    _jiggleApply(elapsedSeconds);
    // Тело гаснет поверх всего: эмоции ключуют прозрачность расправленной
    // кофты у подмышек, и она проявлялась бы над кофтой прежнего мишка.
    if (headOnly) {
      _bodyOff
        ?..time = 0
        ..apply(mix: 1);
    }
    super.advance(0);
    _jiggleMeasure(elapsedSeconds);
    final breath = this.breath;
    final b = _bBreath;
    if (breath != null && b != null) {
      final e = _eBreath;
      breath.value =
          (b.scaleY - _breathMid) / _breathHalf +
          (e == null ? 0 : (e.scaleY - 1) / _breathHalf);
    }
    return true;
  }

  @override
  void dispose() {
    _idle?.dispose();
    _calm?.dispose();
    _bodyOff?.dispose();
    _faces?.dispose();
    _petFace?.dispose();
    _petPass?.dispose();
    _petOut?.dispose();
    _sleepIdle?.dispose();
    _eyesSquash?.dispose();
    _eyesShut?.dispose();
    _mouthZero?.dispose();
    for (final clip in [
      ..._moods.values,
      ..._clips.values,
      ..._mouthOp.values,
    ]) {
      clip.dispose();
    }
    super.dispose();
  }
}

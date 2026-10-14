import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/sounds.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/rive_bear_trial.dart';
import '../game/room_kind.dart';
import 'kitchen_scene.dart' show KitchenMeal, KitchenMood, KitchenScene;

/// Мишка на кухне — тот же анимированный Rive-мишка, что в игровой
/// (заказчик 27.09: «переноси мишку на кухню»), за столом — с телом
/// прежнего нарисованного мишка (заказчик 11.10: «возьми предыдущего
/// мишку, его одежду, сопоставь цвет и наложи на него… идеально ровный
/// вид, как был ранее. Расположение рук. Плечи поджаты»).
///
/// Голова в капюшоне — Rive-мишка, поставлен по замерам старого:
/// расстояние между глазами 70 px кадра кухни 941 × 1672 против 112 px
/// артборда → масштаб 0,625; артборд 1024 → 640 px, левый верхний угол —
/// (146, 611). Верх капюшона — y 636 (у старого 639), глаза — точно на
/// месте старых. Тело рига за столом спрятано
/// ([RiveBearTrial.headOnly]): его рукава, сплющенные до стола, давали
/// «крылышки» и заломы на кофте.
///
/// Тело — части прежнего мишка на их прежних местах
/// (`tool/cut_kitchen_seat.py`): кофта с рукавами и лапы на кромке стола,
/// цвет ткани и меха подогнан под нашего мишка. Капюшон лежит поверх
/// кофты. Кофта дышит вместе с мишкой — от кромки стола, по вдоху самой
/// кости рига ([RiveBearTrial.breath]); лапы лежат на столе.
///
/// События кухни — в клипы мишки:
/// - поел → «Жуёт», потом по настроению: любимое — «Любовь», приготовил
///   сам — «Удивление» и реакция характера на угощение, остальное —
///   реакция характера на угощение;
/// - «не то положили» → «Встряхнулся» (мотает головой);
/// - касание мимо мишки — как тап по нему (реакция на касание);
/// - сам мишка ловит палец, как в игровой: тап — реакция на касание,
///   ведут по голове — ласка, по животу над столом — щекотка (заказчик
///   27.09: «включи поглаживание на кухне»).
///
/// Пока жуёт — лапы по очереди похлопывают по столу: приподнимаются в
/// рукавах, под ними изнанка рукава (`seat_cuffs.png`), не стул.
/// За столом мишка сидит: вертикальные подскоки корпуса гасятся
/// ([RiveBearTrial.seated]). Цвет головы чуть теплее и темнее — под свет
/// иллюстрации кухни (замер по шерсти и капюшону старого мишки).
class KitchenBear extends StatefulWidget {
  const KitchenBear({
    super.key,
    required this.cue,
    required this.mood,
    required this.trait,
    this.meal,
    this.pet = 0,
    this.refuse = 0,
    this.onTap,
    this.skin = BearSkin.boy,
  });

  /// Герой (КП 2.4). У девочки за столом — её кофточка с рукавами из её
  /// слоёв (`girl_seat.png`, `tool/rive/girl_kitchen.py`), лапы уходят под
  /// стол. ⚠ Лапы на столе, как у мальчика, — нужен рисунок (ждёт
  /// согласования, `docs/rive-girl.md`).
  final BearSkin skin;

  final BearFaceCue cue;
  final BearMood mood;
  final BearTrait trait;
  final KitchenMeal? meal;

  /// Счётчик касаний мимо мишки: вырос — реакция на касание.
  final int pet;

  /// Счётчик «не то положили»: вырос — мотает головой.
  final int refuse;

  /// Тап по самому мишке.
  final VoidCallback? onTap;

  /// Замеры в долях кадра кухни.
  static const double left = 146 / 941;
  static const double top = 611 / 1672;
  static const double side = 640 / 941;

  /// Поправка цвета под кухню: чуть теплее и темнее.
  static const ColorFilter warm = ColorFilter.matrix(<double>[
    0.98, 0, 0, 0, 0, //
    0, 0.955, 0, 0, 0, //
    0, 0, 0.935, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Тело прежнего мишка — доли кадра (печатает `tool/cut_kitchen_seat.py`):
  /// кофта с рукавами и лапы на их прежних местах.
  static const Rect body = Rect.fromLTWH(
    0.340064,
    0.540670,
    0.306057,
    0.067584,
  );
  static const Rect pawLeft = Rect.fromLTWH(
    0.335648,
    0.579427,
    0.092593,
    0.037760,
  );
  static const Rect pawRight = Rect.fromLTWH(
    0.562500,
    0.579427,
    0.086806,
    0.037760,
  );

  static const String _dir = 'assets/rooms/kitchen';
  static const List<String> assets = [
    '$_dir/seat_body.png',
    '$_dir/seat_cuffs.png',
    '$_dir/seat_paw_left.png',
    '$_dir/seat_paw_right.png',
    '$_dir/girl_seat.png',
  ];

  /// Тело девочки за столом — полоса артборда рига (1024 × 225) от y 420
  /// до кромки стола: стоит в том же квадрате, что голова рига.
  static const double girlSeatTop = 420 / 1024;
  static const double girlSeatHeight = 225 / 1024;

  /// Заранее раскодировать тело — иначе за столом на долю секунды
  /// показалась бы одна голова.
  static Future<void> warmUp(BuildContext context) => Future.wait([
    for (final asset in assets) precacheImage(AssetImage(asset), context),
  ]);

  /// Вдох кофты на единицу дыхания мишка (вдох рига за столом ±0,6):
  /// подъём — доля высоты кадра, растяжение от кромки стола — как у
  /// прежнего мишка (`KitchenScene.chestSwell`).
  static const double breathLift = 1.5 / 1672;
  static const double breathSwell = 0.012;

  /// Похлопывание: лапа приподнимается в рукаве на 4 px кадра и
  /// опускается на стол. Заказчик 11.10: «когда лапками двигает —
  /// проблески, как будто рукава обрезаны». Замер по кадрам: прежний кивок
  /// (поворот до 14° у середины верха лапы и подъём на 6 px) открывал проём
  /// рукава до 135 px² кадра — сквозь рукав был виден стул, — и край лапы
  /// вылезал за рукав на 620 px². Теперь проём под лапой закрыт изнанкой
  /// рукава (`seat_cuffs.png`), а лапа только поднимается: просвета нет,
  /// нового меха над рукавом — 40–60 px² (верх лапы поднимается вдоль
  /// рукава).
  static const double patLift = 4 / 1672;

  /// Когда каждая лапа хлопает (доли [_KitchenBearState._patTime]) — по
  /// очереди, как «вкусно!» на каждое жевание.
  static const List<double> patsLeft = [0.04, 0.30, 0.56];
  static const List<double> patsRight = [0.17, 0.43, 0.69];
  static const double patLen = 0.12;

  @override
  State<KitchenBear> createState() => _KitchenBearState();
}

class _KitchenBearState extends State<KitchenBear>
    with SingleTickerProviderStateMixin {
  final List<Timer> _later = [];

  /// Вдох мишка — пишет сам риг каждый кадр, кофта дышит с ним.
  final ValueNotifier<double> _breath = ValueNotifier(0);

  /// Похлопывание лапами, пока жуёт: 0…1 за [_patTime].
  late final AnimationController _pat = AnimationController(
    vsync: this,
    duration: _patTime,
  );
  static const Duration _patTime = Duration(milliseconds: 3800);

  /// Идёт еда — касания и «не то» её не перебивают.
  bool _eating = false;

  @override
  void didUpdateWidget(KitchenBear old) {
    super.didUpdateWidget(old);
    final meal = widget.meal;
    if (meal != null && meal.id != old.meal?.id) {
      _eat(meal.mood);
      return;
    }
    if (_eating) return;
    if (widget.refuse != old.refuse) {
      widget.cue.show(BearFace.bonusShake);
    } else if (widget.pet != old.pet) {
      widget.cue.show(BearFace.touch);
    }
  }

  void _after(int ms, VoidCallback run) {
    _later.add(
      Timer(Duration(milliseconds: ms), () {
        if (mounted) run();
      }),
    );
  }

  void _eat(KitchenMood mood) {
    for (final t in _later) {
      t.cancel();
    }
    _later.clear();
    _eating = true;
    widget.cue.show(BearFace.chew);
    _pat.forward(from: 0);
    Sounds.play(Sfx.chew);
    // «Жуёт» — 4,1 с
    _after(4000, () => Sounds.stop(Sfx.chew));
    switch (mood) {
      case KitchenMood.love:
        _after(4200, () => widget.cue.show(BearFace.tenderness));
        _after(8000, () => _eating = false);
      case KitchenMood.surprise:
        _after(4200, () => widget.cue.show(BearFace.surprised));
        _after(6400, () => widget.cue.show(BearFace.treat));
        _after(9800, () => _eating = false);
      case KitchenMood.happy:
        _after(4200, () => widget.cue.show(BearFace.treat));
        _after(7600, () => _eating = false);
    }
  }

  @override
  void dispose() {
    _pat.dispose();
    _breath.dispose();
    for (final t in _later) {
      t.cancel();
    }
    if (_eating) Sounds.stop(Sfx.chew);
    super.dispose();
  }

  /// Кивок лапы сейчас: 0 — лежит, 1 — на вершине хлопка.
  double _bump(List<double> at) {
    final t = _pat.value;
    if (!_pat.isAnimating && t >= 1) return 0;
    for (final a in at) {
      final u = (t - a) / KitchenBear.patLen;
      if (u > 0 && u < 1) return math.sin(math.pi * u);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final table = KitchenScene.tableFront;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Скатерть и край стола — кусок самого фона: лапы лежат на ней.
            Positioned(
              left: 0,
              top: table.top * h,
              width: w,
              height: table.height * h,
              child: IgnorePointer(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: w,
                    maxWidth: w,
                    minHeight: h,
                    maxHeight: h,
                    child: Transform.translate(
                      offset: Offset(0, -table.top * h),
                      child: Image.asset(
                        RoomKind.kitchen.asset,
                        width: w,
                        height: h,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Тело прежнего мишка: лапы под рукавами, кофта поверх.
            // У девочки — её кофточка из её слоёв.
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<BearSkin?>(
                  valueListenable: widget.cue.hero,
                  builder: (context, _, _) =>
                      widget.cue.heroOr(widget.skin) == BearSkin.girl
                      ? AnimatedBuilder(
                          animation: _breath,
                          builder: (context, _) =>
                              Stack(children: [_girlSeat(w, h)]),
                        )
                      : AnimatedBuilder(
                          animation: Listenable.merge([_breath, _pat]),
                          builder: (context, _) => Stack(
                            children: [
                              // изнанка рукавов — под лапами, дышит с кофтой
                              _body(w, h, table.top, 'seat_cuffs'),
                              _paw(w, h, KitchenBear.pawLeft, 'left'),
                              _paw(w, h, KitchenBear.pawRight, 'right'),
                              _body(w, h, table.top, 'seat_body'),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            // Голова в капюшоне — над кофтой.
            Positioned(
              left: KitchenBear.left * w,
              top: KitchenBear.top * h,
              width: KitchenBear.side * w,
              height: KitchenBear.side * w,
              child: ColorFiltered(
                colorFilter: KitchenBear.warm,
                child: RiveBearTrial(
                  cue: widget.cue,
                  trait: widget.trait,
                  mood: widget.mood,
                  skin: widget.skin,
                  seated: true,
                  headOnly: true,
                  breath: _breath,
                  // кромка стола в координатах артборда: ниже — скатерть
                  reachBottom:
                      (table.top * h - KitchenBear.top * h) /
                      (KitchenBear.side * w) *
                      1024,
                  onTap: widget.onTap,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Кофта с рукавами ([asset] `seat_body`) и изнанка рукавов под лапами
  /// (`seat_cuffs`): на вдохе чуть растут от кромки стола и поднимаются —
  /// вместе с головой, которая дышит в риге.
  Widget _body(double w, double h, double tableTop, String asset) {
    final b = _breath.value.clamp(-1.6, 1.6);
    final box = KitchenBear.body;
    return Positioned(
      left: box.left * w,
      top: box.top * h - KitchenBear.breathLift * b * h,
      width: box.width * w,
      height: box.height * h,
      child: Transform.scale(
        scaleY: 1 + KitchenBear.breathSwell * b,
        scaleX: 1 + KitchenBear.breathSwell * 0.3 * b,
        // опора — кромка стола
        alignment: Alignment(0, (tableTop - box.top) / box.height * 2 - 1),
        child: Image.asset('${KitchenBear._dir}/$asset.png', fit: BoxFit.fill),
      ),
    );
  }

  /// Кофточка девочки до кромки стола — в квадрате головы рига; дышит,
  /// как кофта мальчика: растёт от кромки и чуть поднимается.
  Widget _girlSeat(double w, double h) {
    final b = _breath.value.clamp(-1.6, 1.6);
    final side = KitchenBear.side * w;
    return Positioned(
      left: KitchenBear.left * w,
      top:
          KitchenBear.top * h +
          KitchenBear.girlSeatTop * side -
          KitchenBear.breathLift * b * h,
      width: side,
      height: KitchenBear.girlSeatHeight * side,
      child: Transform.scale(
        scaleY: 1 + KitchenBear.breathSwell * b,
        scaleX: 1 + KitchenBear.breathSwell * 0.3 * b,
        alignment: Alignment.bottomCenter,
        child: ColorFiltered(
          colorFilter: KitchenBear.warm,
          child: Image.asset(
            '${KitchenBear._dir}/girl_seat.png',
            fit: BoxFit.fill,
          ),
        ),
      ),
    );
  }

  /// Лапа на кромке стола с мягкой тенью на скатерти; пока жуёт —
  /// приподнимается в рукаве и опускается ([KitchenBear.patLift]).
  Widget _paw(double w, double h, Rect box, String side) {
    final bump = _bump(
      side == 'left' ? KitchenBear.patsLeft : KitchenBear.patsRight,
    );
    final rect = Rect.fromLTWH(
      box.left * w,
      box.top * h,
      box.width * w,
      box.height * h,
    );
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // тень лежит на столе ровно; при хлопке бледнее и шире
          Positioned(
            left: rect.width * (0.12 - 0.04 * bump),
            right: rect.width * (0.12 - 0.04 * bump),
            top: rect.height * 0.78,
            height: rect.height * 0.32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(
                  Radius.elliptical(rect.width, rect.height),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(70, 60, 40, 0.30 * (1 - 0.45 * bump)),
                    blurRadius: rect.height * 0.18,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, -KitchenBear.patLift * h * bump),
              child: Image.asset(
                '${KitchenBear._dir}/seat_paw_$side.png',
                fit: BoxFit.fill,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

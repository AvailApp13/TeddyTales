import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../audio/sounds.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/rive_bear_trial.dart';
import '../game/room_kind.dart';
import 'kitchen_scene.dart' show KitchenMeal, KitchenMood, KitchenScene;

/// Мишка на кухне — тот же анимированный Rive-мишка, что в игровой
/// (заказчик 27.09: «переноси мишку на кухню»). Плоский мишка из частей
/// (`KitchenScene`) и его ножки под столом больше не рисуются — наши ноги
/// целиком под скатертью.
///
/// Поставлен по замерам старого: расстояние между глазами 70 px кадра
/// кухни 941 × 1672 против 112 px артборда → масштаб 0,625; артборд
/// 1024 → 640 px, левый верхний угол — (146, 611). Верх капюшона — y 636
/// (у старого 639), глаза — точно на месте старых. Поверх — полоса
/// скатерти из самого фона кухни ([KitchenScene.tableFront]): она прячет
/// всё ниже края стола.
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
/// Лапы на столе (заказчик 27.09, как у прежнего мишки): руки рига
/// чуть внутрь и укорочены — идут вперёд, к зрителю; манжета и лапа —
/// отдельной картинкой из текстур самого рига поверх скатерти
/// (`tool/cut_table_paws.py`), ровно там, где кончается рукав: картинка
/// едет за костью кисти ([TablePaws]). Под лапами мягкая тень на скатерти.
/// Пока жуёт — лапы по очереди похлопывают по столу (кивок кисти, рука не
/// поднимается).
///
/// За столом мишка сидит: вертикальные подскоки корпуса гасятся
/// ([RiveBearTrial.seated]). Цвет чуть теплее и темнее — под свет
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
  });

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

  @override
  State<KitchenBear> createState() => _KitchenBearState();
}

class _KitchenBearState extends State<KitchenBear>
    with SingleTickerProviderStateMixin {
  final List<Timer> _later = [];
  final TablePaws _paws = TablePaws();

  /// Похлопывание лапами, пока жуёт: 0…1 за [_patTime].
  late final AnimationController _pat = AnimationController(
    vsync: this,
    duration: _patTime,
  );
  static const Duration _patTime = Duration(milliseconds: 3800);
  ui.Image? _pawLeft;
  ui.Image? _pawRight;
  final List<(ImageStream, ImageStreamListener)> _streams = [];

  @override
  void initState() {
    super.initState();
    _load('left', (i) => _pawLeft = i);
    _load('right', (i) => _pawRight = i);
  }

  void _load(String side, void Function(ui.Image) done) {
    final stream = AssetImage(
      'assets/rooms/kitchen/table_paw_$side.png',
    ).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => done(info.image));
    });
    stream.addListener(listener);
    _streams.add((stream, listener));
  }

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
    for (final (stream, listener) in _streams) {
      stream.removeListener(listener);
    }
    _pat.dispose();
    _paws.dispose();
    for (final t in _later) {
      t.cancel();
    }
    if (_eating) Sounds.stop(Sfx.chew);
    super.dispose();
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
                  seated: true,
                  paws: _paws,
                  // кромка стола в координатах артборда: ниже — скатерть
                  reachBottom:
                      (table.top * h - KitchenBear.top * h) /
                      (KitchenBear.side * w) *
                      1024,
                  onTap: widget.onTap,
                ),
              ),
            ),
            // Скатерть и край стола — кусок самого фона поверх мишки.
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
            // Лапы на столе — над скатертью, в той же коробке, что мишка.
            if (_pawLeft != null && _pawRight != null)
              Positioned(
                left: KitchenBear.left * w,
                top: KitchenBear.top * h,
                width: KitchenBear.side * w,
                height: KitchenBear.side * w,
                child: IgnorePointer(
                  child: ColorFiltered(
                    colorFilter: KitchenBear.warm,
                    child: CustomPaint(
                      painter: _TablePawsPainter(
                        paws: _paws,
                        pat: _pat,
                        left: _pawLeft!,
                        right: _pawRight!,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Манжета и лапа на столе поверх скатерти. Координаты — px артборда
/// мишки (1024), картинки лежат в мире покоя там, где их вырезал
/// `tool/cut_table_paws.py`, и едут за кистью рига.
class _TablePawsPainter extends CustomPainter {
  _TablePawsPainter({
    required this.paws,
    required this.pat,
    required this.left,
    required this.right,
  }) : super(repaint: Listenable.merge([paws, pat]));

  final TablePaws paws;
  final Animation<double> pat;
  final ui.Image left;
  final ui.Image right;

  /// Где лежат картинки в мире покоя (печатает `tool/cut_table_paws.py`).
  static const Rect boxLeft = Rect.fromLTWH(220.1, 589.5, 138.6, 146.1);
  static const Rect boxRight = Rect.fromLTWH(667.3, 588.8, 140.4, 143.0);

  /// Тень: под низом лапы, на скатерти (центр и размер в мире покоя).
  static const Offset shadowLeft = Offset(276, 728);
  static const Offset shadowRight = Offset(750, 726);
  static const Size shadowSize = Size(118, 30);

  /// Похлопывание: кивок кисти до 14° и лапа чуть над столом.
  static const double patTurn = 0.24;
  static const double patLift = 9;

  /// Когда каждая лапа хлопает (доли [_KitchenBearState._patTime]) — по
  /// очереди, как «вкусно!» на каждое жевание.
  static const List<double> patsLeft = [0.04, 0.30, 0.56];
  static const List<double> patsRight = [0.17, 0.43, 0.69];
  static const double patLen = 0.12;

  double _bump(List<double> at) {
    final t = pat.value;
    if (!pat.isAnimating && t >= 1) return 0;
    for (final a in at) {
      final u = (t - a) / patLen;
      if (u > 0 && u < 1) return math.sin(math.pi * u);
    }
    return 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!paws.ready) return;
    canvas.save();
    canvas.transform(paws.body.storage);
    canvas.scale(size.width / 1024);
    _paw(
      canvas,
      left,
      boxLeft,
      paws.left,
      TablePaws.restLeft,
      shadowLeft,
      _bump(patsLeft),
      1,
    );
    _paw(
      canvas,
      right,
      boxRight,
      paws.right,
      TablePaws.restRight,
      shadowRight,
      _bump(patsRight),
      -1,
    );
    canvas.restore();
  }

  void _paw(
    Canvas canvas,
    ui.Image image,
    Rect box,
    Matrix4 at,
    Offset wrist,
    Offset shadow,
    double bump,
    double sign,
  ) {
    canvas.save();
    canvas.transform(at.storage);
    // тень лежит на столе: при хлопке лапа отрывается — тень бледнее и шире
    final shadowRect = Rect.fromCenter(
      center: shadow,
      width: shadowSize.width * (1 + 0.12 * bump),
      height: shadowSize.height * (1 + 0.12 * bump),
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..color = Color.fromRGBO(70, 60, 40, 0.28 * (1 - 0.45 * bump))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    // кивок кисти: поворот вокруг запястья, кончик лапы вверх
    canvas.translate(wrist.dx, wrist.dy - patLift * bump);
    canvas.rotate(sign * patTurn * bump);
    canvas.translate(-wrist.dx, -wrist.dy);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      box,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TablePawsPainter old) =>
      old.left != left || old.right != right || old.paws != paws;
}

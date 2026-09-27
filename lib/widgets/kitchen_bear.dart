import 'dart:async';

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

class _KitchenBearState extends State<KitchenBear> {
  final List<Timer> _later = [];

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
          ],
        );
      },
    );
  }
}

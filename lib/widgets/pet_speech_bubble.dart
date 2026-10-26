import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart' show glassText;

/// Облачко с репликой питомца и его инициативой (КП 3.4, 13.3).
///
/// Заказчик 27.09: реплика всплывает и печатается по буквам, как будто
/// мишка говорит. Заказчик 10.10: над головой облачко закрывало картины на
/// стене — теперь оно слева от мишки, у окна, на уровне головы, на
/// свободном куске стены. Форма — облачко, хвостик из маленьких кружков
/// тянется к голове.
///
/// Ход: облачко всплывает (0,8 → 1 за 250 мс, с лёгким перелётом), текст
/// печатается по 35 мс на букву, через 3,5 с после последней буквы
/// облачко тает, чуть поднимаясь. Новая реплика — при смене контекста:
/// состояния покоя или инициативы.
///
/// Где стоять, решает сцена ([PetSpeechBubble.tailTo] — куда тянется
/// хвостик, от правого верхнего угла облачка).
class PetSpeechBubble extends StatefulWidget {
  const PetSpeechBubble({
    super.key,
    required this.mood,
    required this.initiative,
    this.forgotten = false,
    this.language = BearLanguage.ru,
    this.onTap,
    this.tailTo,
  });

  final BearMood mood;
  final BearInitiative? initiative;

  /// Нужда ниже 15 — реплика «Ты про меня забыл?» (`BearLife.forgotten`).
  final bool forgotten;
  final BearLanguage language;

  /// Тап по облачку — согласиться на предложение питомца.
  final ValueChanged<BearAction>? onTap;

  /// Куда тянется хвостик из кружков — к голове мишки. Точка от правого
  /// верхнего угла облачка: сцена ставит облачко правым краем к голове, а
  /// ширина его зависит от реплики. `null` — вниз направо.
  final Offset? tailTo;

  /// Сколько мс печатается одна буква.
  static const int msPerChar = 35;

  /// Сколько облачко держится после последней буквы.
  static const Duration hold = Duration(milliseconds: 3500);

  @override
  State<PetSpeechBubble> createState() => _PetSpeechBubbleState();
}

class _PetSpeechBubbleState extends State<PetSpeechBubble>
    with TickerProviderStateMixin {
  BearPhraseContext? _context;
  BearPhrase? _phrase;

  /// Всплытие: 0,8 → 1 и из прозрачного.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  /// Печать по буквам: 0 — ни одной, 1 — реплика целиком.
  late final AnimationController _type = AnimationController(vsync: this);

  /// Пауза после печати. Контроллером, а не таймером: уходит вместе с
  /// облачком, ничего не срабатывает после него.
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: PetSpeechBubble.hold,
  );

  /// Уход: тает и поднимается.
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    _in.addStatusListener((s) {
      if (s == AnimationStatus.completed) _type.forward(from: 0);
    });
    _type.addStatusListener((s) {
      if (s == AnimationStatus.completed) _hold.forward(from: 0);
    });
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _out.forward(from: 0);
    });
    _refresh();
  }

  @override
  void didUpdateWidget(PetSpeechBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void dispose() {
    _in.dispose();
    _type.dispose();
    _hold.dispose();
    _out.dispose();
    super.dispose();
  }

  void _refresh() {
    final next = _resolveContext();
    if (next == _context && _phrase != null) return;
    _context = next;
    _phrase = BearPhrases.random(next);
    final chars = _phrase!.text(widget.language).length;
    _type.duration = Duration(milliseconds: PetSpeechBubble.msPerChar * chars);
    _hold.reset();
    _out.reset();
    _type.reset();
    _in.forward(from: 0);
  }

  BearPhraseContext _resolveContext() {
    if (widget.forgotten) return BearPhraseContext.forgotten;
    final initiative = widget.initiative;
    if (initiative != null) {
      return switch (initiative.action) {
        BearAction.play => BearPhraseContext.invitePlay,
        BearAction.learn => BearPhraseContext.inviteLearn,
        BearAction.feed => BearPhraseContext.hungry,
        BearAction.sleep => BearPhraseContext.sleepy,
        BearAction.wash => BearPhraseContext.dirty,
        BearAction.pet => BearPhraseContext.sad,
        _ => BearPhrases.contextForMood(widget.mood),
      };
    }
    return BearPhrases.contextForMood(widget.mood);
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _phrase;
    if (phrase == null) return const SizedBox.shrink();

    final initiative = widget.initiative;
    final text = phrase.text(widget.language);
    final style = glassText(12.5, 700, color: AppColors.textPrimary);

    return AnimatedBuilder(
      animation: Listenable.merge([_in, _type, _out]),
      builder: (context, _) {
        // Растаяло — облачка нет, и касаний оно не ловит.
        if (_out.isCompleted) return const SizedBox.shrink();
        final appear = Curves.easeOutBack.transform(_in.value);
        final leave = Curves.easeIn.transform(_out.value);
        final shown = (text.length * _type.value).round();
        final typing = shown < text.length;

        return Opacity(
          opacity: (_in.value * (1 - leave)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -14 * leave),
            child: Transform.scale(
              scale: 0.8 + 0.2 * appear,
              // Растёт из хвостика — от головы мишки.
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: initiative == null || widget.onTap == null
                    ? null
                    : () => widget.onTap!(initiative.action),
                child: CustomPaint(
                  painter: _CloudPainter(tailTo: widget.tailTo),
                  child: Padding(
                    // Бугорки облака по краям — текст держится внутри.
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    // Размер — по полной реплике, чтобы облачко не росло
                    // вместе с буквами; напечатанное — поверх.
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: 0,
                          child: Text(
                            text,
                            style: style,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Positioned.fill(
                          child: Text(
                            text.substring(0, shown) + (typing ? '▏' : ''),
                            style: style,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Облачко: округлая середина в бугорках, мягкая тень, тонкая кромка и
/// хвостик из трёх кружков, тающих к голове мишки.
class _CloudPainter extends CustomPainter {
  _CloudPainter({this.tailTo});

  final Offset? tailTo;

  static const double _bump = 9;

  /// Контуры по размеру: облако перерисовывается каждый кадр печати, а
  /// собирать его из двух десятков кругов каждый раз незачем.
  static final Map<Size, Path> _cache = {};

  static Path _cloud(Size size) {
    final hit = _cache[size];
    if (hit != null) return hit;
    if (_cache.length > 16) _cache.clear();
    return _cache[size] = _build(size);
  }

  /// Контур облака под размер: объединение середины и бугорков по краю.
  static Path _build(Size size) {
    final r = math.min(_bump, size.shortestSide / 4);
    final core = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(r * 0.9),
      Radius.circular(size.height / 2.6),
    );
    var path = Path()..addRRect(core);
    // Бугорки — по контуру середины, через равные промежутки.
    final metric = (Path()..addRRect(core)).computeMetrics().first;
    final count = math.max(8, (metric.length / (r * 1.55)).round());
    for (var i = 0; i < count; i++) {
      final at = metric.getTangentForOffset(metric.length * i / count);
      if (at == null) continue;
      // Чуть разные размеры — облако живое, а не гофрированное.
      final k = 1 + 0.18 * math.sin(i * 2.3);
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addOval(Rect.fromCircle(center: at.position, radius: r * k)),
      );
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = AppColors.surface;
    final edge = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final shadow = Paint()
      ..color = const Color(0x26000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final cloud = _cloud(size);

    // Хвостик: три кружка от низа облака к голове, всё мельче.
    final from = Offset(size.width * 0.84, size.height * 0.84);
    final to = tailTo == null
        ? from + const Offset(22, 26)
        : Offset(size.width, 0) + tailTo!;
    final dots = <(Offset, double)>[
      for (final (t, r) in const [(0.30, 6.0), (0.62, 4.2), (0.92, 2.8)])
        (Offset.lerp(from, to, t)!, r),
    ];

    canvas.drawPath(cloud.shift(const Offset(0, 3)), shadow);
    for (final (c, r) in dots) {
      canvas.drawCircle(c + const Offset(0, 2), r, shadow);
    }
    canvas.drawPath(cloud, fill);
    canvas.drawPath(cloud, edge);
    for (final (c, r) in dots) {
      canvas.drawCircle(c, r, fill);
      canvas.drawCircle(c, r, edge);
    }
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.tailTo != tailTo;
}

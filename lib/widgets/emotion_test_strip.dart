import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../bear/rive_bear_trial.dart';
import '../theme/app_colors.dart';

/// ⚠ ПРОВЕРОЧНАЯ ЛЕНТА ЭМОЦИЙ — снять перед публикацией.
///
/// Заказчик 30.09: внизу под мишкой все 33 эмоции по порядку, с номерами и
/// подписями, лента листается влево-вправо — для заказчицы, чтобы
/// отработать и поправить каждую. Плитка: номер крупно сверху, подпись
/// снизу. Нажали — мишка играет эту эмоцию, плитка подсвечена. Над лентой —
/// какая группа сейчас на экране. Номера прежние (как в прежней
/// проверочной панели), по ним удобно писать правки.
class EmotionTestStrip extends StatefulWidget {
  const EmotionTestStrip({super.key, required this.cue});

  final BearFaceCue cue;

  /// Размер плитки и зазор между плитками, пт.
  static const double tileWidth = 84;
  static const double tileHeight = 64;
  static const double gap = 8;

  /// Полная высота ленты с подписью группы.
  static const double height = tileHeight + 22;

  @override
  State<EmotionTestStrip> createState() => _EmotionTestStripState();
}

/// Группы ленты: с какого номера начинается, название, цвет номера.
const List<(int, String, Color)> _groups = [
  (1, 'Эмоции 1–13', Color(0xFF6FA173)),
  (14, 'Покой с настроением 14–19', Color(0xFF6E8FC2)),
  (20, 'Разнообразие покоя 20–25', Color(0xFFC08A3E)),
  (26, 'Характер 26–31', Color(0xFFB0698B)),
  (32, 'Реакции характера 32–33', Color(0xFF8A6FB8)),
];

(int, String, Color) _groupOf(int number) =>
    _groups.lastWhere((g) => number >= g.$1);

class _EmotionTestStripState extends State<EmotionTestStrip> {
  final ScrollController _scroll = ScrollController();
  int _first = 1;

  @override
  void initState() {
    super.initState();
    widget.cue.addListener(_changed);
    _scroll.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(EmotionTestStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cue != widget.cue) {
      oldWidget.cue.removeListener(_changed);
      widget.cue.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.cue.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Подпись группы — по первой плитке, которая видна слева больше чем
  /// наполовину; долистали до конца — последняя группа (иначе «Реакции
  /// 32–33» не показались бы никогда).
  void _scrolled() {
    const step = EmotionTestStrip.tileWidth + EmotionTestStrip.gap;
    final atEnd =
        _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset >= _scroll.position.maxScrollExtent - step * 0.5;
    final first = atEnd
        ? BearFace.values.length
        : ((_scroll.offset + step * 0.5) / step).floor() + 1;
    final clamped = first.clamp(1, BearFace.values.length);
    if (clamped != _first) setState(() => _first = clamped);
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF4A3528);
    final current = widget.cue.face;
    final group = _groupOf(_first);
    return SizedBox(
      key: const ValueKey('emotion-test-strip'),
      height: EmotionTestStrip.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      group.$2,
                      key: ValueKey(group.$1),
                      style: TextStyle(
                        color: group.$3,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(color: Color(0x99FFFFFF), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
                Text(
                  'листайте влево-вправо',
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    shadows: const [
                      Shadow(color: Color(0x99FFFFFF), blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            // Края ленты тают — видно, что она продолжается.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, 0.035, 0.9, 1],
              ).createShader(rect),
              // листается и пальцем, и мышью (песочница в браузере)
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  // справа запас: последняя плитка выходит из-под затухания
                  padding: const EdgeInsets.only(left: 16, right: 56),
                  itemCount: BearFace.values.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: EmotionTestStrip.gap),
                  itemBuilder: (context, i) {
                    final face = BearFace.values[i];
                    return _EmotionTile(
                      number: i + 1,
                      face: face,
                      color: _groupOf(i + 1).$3,
                      selected: face == current,
                      onTap: () => widget.cue.show(face),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmotionTile extends StatelessWidget {
  const _EmotionTile({
    required this.number,
    required this.face,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final BearFace face;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF4A3528);
    // «Покой: радость» — «Покой:» на первой строке, настроение на второй;
    // длинные слова — с переносом, иначе в плитке они слишком мелкие
    final label = face.label
        .replaceFirst(': ', ':\n')
        .replaceFirst('Любознательный', 'Любо-\nзнательный')
        .replaceFirst('Самостоятельный', 'Само-\nстоятельный');
    return GestureDetector(
      key: ValueKey('emotion-test-${face.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: EmotionTestStrip.tileWidth,
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              '$number',
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 21,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      color: selected ? Colors.white : ink,
                      fontSize: 11.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/room_kind.dart';
import '../game/room_slots.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'room_scene_backdrop.dart';

/// По какую сторону от мишки лежит место.
enum SlotDepth {
  /// Дальше мишки: задняя стена, стены, дальняя половина пола.
  behind,

  /// Ближе мишки: коврик и игрушки переднего плана.
  front,
}

/// Считается по линии пола места, а не по полю `depth`.
///
/// `depth` — порядок отрисовки внутри захода (ковёр рисуется первым, потому
/// что на нём стоят), а глубину в комнате задаёт то, на какой линии пола
/// вещь стоит. Настенное всегда позади: стена дальше всего.
SlotDepth slotDepth(RoomSlot slot) =>
    slot.onWall || slot.y <= RoomSceneBackdrop.standLine
    ? SlotDepth.behind
    : SlotDepth.front;

/// Комната по местам: что где стоит и куда можно поставить.
///
/// Слой один на обе задачи — занятые места и свободные, — потому что это
/// одно и то же множество мест, показанное по-разному. Держать их двумя
/// слоями значило бы дважды считать одну и ту же геометрию и однажды
/// разойтись в пикселе.
///
/// Свободные места подсвечиваются не все: пунктир по всей комнате прячет
/// мишку за собой. Сколько показывать — решает [hintLimit].
///
/// Слой рисуется в два захода — [SlotDepth.behind] под мишкой и
/// [SlotDepth.front] над ним. Один заход не годится: мишка стоит на трети
/// глубины комнаты, и вещи у задней стены должны быть за ним, а коврик и
/// корзина переднего плана — перед. Подсветка при этом считается по всем
/// местам сразу, иначе каждый заход подсветил бы свои три.
class RoomSlotLayer extends StatelessWidget {
  const RoomSlotLayer({
    super.key,
    required this.game,
    required this.room,
    required this.onTapItem,
    required this.onTapEmpty,
    this.depth = SlotDepth.front,
    this.hintLimit = 3,
  });

  final GameState game;
  final RoomKind room;

  /// Какой заход рисуем: дальние места или ближние.
  final SlotDepth depth;

  /// Тап по стоящей вещи: открыть «убрать или заменить».
  final void Function(RoomSlot slot, ShopItem item) onTapItem;

  /// Тап по свободному месту: предложить, что сюда поставить.
  final ValueChanged<RoomSlot> onTapEmpty;

  final int hintLimit;

  @override
  Widget build(BuildContext context) {
    final slots = slotsOf(room);

    // Подсвечиваются не все свободные места, а несколько — и не первые
    // попавшиеся.
    //
    // Порядок такой: сначала места, куда человеку есть что поставить прямо
    // сейчас, из уже купленного. Двенадцать бесплатных вещей (КП 10.8) не
    // должны лежать в инвентаре мёртвым грузом, и первое действие в комнате
    // должно быть бесплатным и мгновенным.
    //
    // Дальше крупное вперёд мелкого: комнату делает кроватка, а не картинка
    // на стене. Три подсвеченные рамки под картины в пустой комнате
    // показывают, что обставлять нечем, — ровно обратное тому, что нужно.
    final empty =
        [
          for (final slot in slots)
            if (game.itemInSlot(slot.id) == null) slot,
        ]..sort((a, b) {
          final hasA = _hasItemFor(game, a);
          final hasB = _hasItemFor(game, b);
          if (hasA != hasB) return hasA ? -1 : 1;
          return (b.maxW * b.maxH).compareTo(a.maxW * a.maxH);
        });
    final hinted = empty.take(hintLimit).toSet();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            for (final slot in slots)
              if (slotDepth(slot) == depth)
                _positioned(
                  slot: slot,
                  width: width,
                  height: height,
                  game: game,
                  hinted: hinted.contains(slot),
                  onTapItem: onTapItem,
                  onTapEmpty: onTapEmpty,
                ),
          ],
        );
      },
    );
  }

  /// Есть ли у игрока купленная вещь, которую можно поставить в это место.
  static bool _hasItemFor(GameState game, RoomSlot slot) {
    for (final id in game.owned) {
      final item = ItemCatalog.byId(id);
      if (slot.takes(item) && game.slotOf(id) == null) return true;
    }
    return false;
  }

  static Widget _positioned({
    required RoomSlot slot,
    required double width,
    required double height,
    required GameState game,
    required bool hinted,
    required void Function(RoomSlot, ShopItem) onTapItem,
    required ValueChanged<RoomSlot> onTapEmpty,
  }) {
    final itemId = game.itemInSlot(slot.id);
    final item = itemId == null ? null : ItemCatalog.byId(itemId);

    // Размер занятого места — по вещи, вписанной в габарит; пустого — по
    // самому габариту. Иначе рамка пустого места прыгала бы в зависимости
    // от того, что в неё поставят.
    final size = item == null
        ? (w: slot.maxW, h: slot.maxH)
        : fitIntoSlot(slot, item);

    final w = size.w * width;
    final h = size.h * height;

    return Positioned(
      left: (slot.x * width - w / 2).clamp(0.0, (width - w).clamp(0.0, width)),
      top: slot.onWall ? slot.y * height - h / 2 : slot.y * height - h,
      width: w,
      height: h,
      child: item != null
          ? _FilledSlot(item: item, onTap: () => onTapItem(slot, item))
          : hinted
          ? _EmptySlot(slot: slot, onTap: () => onTapEmpty(slot))
          // Неподсвеченное свободное место всё равно нажимается: человек,
          // который уже понял правило, не должен ждать, пока игра
          // соблаговолит подсветить именно это место.
          : _QuietSlot(onTap: () => onTapEmpty(slot)),
    );
  }
}

/// Стоящая вещь: заглушка-эмодзи, растянутая по габариту места.
class _FilledSlot extends StatelessWidget {
  const _FilledSlot({required this.item, required this.onTap});

  final ShopItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: shopItemName(context.l10n, item.id),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: item.id == 'rug'
            // Ковёр — не эмодзи, а мягкое пятно под ногами: так он и
            // читается в макете.
            ? const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xCCEFC9BC),
                  borderRadius: BorderRadius.all(Radius.elliptical(200, 40)),
                ),
              )
            : FittedBox(
                fit: BoxFit.contain,
                child: Text(item.emoji, style: const TextStyle(fontSize: 100)),
              ),
      ),
    );
  }
}

/// Подсвеченное свободное место: пунктир и плюс.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.slot, required this.onTap});

  final RoomSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedFrame(),
        child: const Center(
          child: Icon(
            Icons.add_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Свободное место без подсветки: только площадь для касания.
class _QuietSlot extends StatelessWidget {
  const _QuietSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}

/// Пунктирная рамка со скруглением.
///
/// Пунктир, а не сплошная линия и не заливка: сплошная читается как готовый
/// предмет, заливка — как пятно на полу. Прерывистая рамка во всех
/// интерфейсах означает одно — «здесь пусто, можно положить».
class _DashedFrame extends CustomPainter {
  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(1),
      const Radius.circular(10),
    );

    canvas.drawRRect(
      rrect,
      Paint()..color = AppColors.surface.withValues(alpha: 0.35),
    );

    final paint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Идём по контуру и выкладываем штрихи: рисовать пунктир по сторонам
    // прямоугольника нельзя — он сломается на скруглениях.
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => false;
}

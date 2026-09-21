import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/item_metrics.dart';
import '../game/room_kind.dart';
import '../game/room_slots.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../game/room_camera.dart';
import '../theme/app_colors.dart';
import 'item_picture.dart';

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
/// вещь стоит. Линия, на которой стоит мишка, у каждой комнаты своя: она
/// зависит от того, чем эта комната снята. Настенное всегда позади: стена
/// дальше всего.
SlotDepth slotDepth(RoomSlot slot) =>
    slot.fit == ItemFit.wall || slot.y <= cameraOf(slot.room).standLine
    ? SlotDepth.behind
    : SlotDepth.front;

/// Показывать ли пунктирные рамки пустых мест.
///
/// Выключено по просьбе заказчика 20.09: «убери эти квадраты подсказки, куда
/// можно добавить мебель, пока спрячь — не удаляй». Спрятана только
/// подсветка: места остаются на своих координатах и по-прежнему нажимаются,
/// поэтому обставить комнату можно и сейчас, просто без пунктира на виду.
/// Вернуть — поменять на `true`.
const bool showSlotHints = false;

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
    this.hint = false,
    this.picked,
  });

  final GameState game;
  final RoomKind room;

  /// Показывать ли свободные места. Постоянной подсветки в комнате нет —
  /// заказчик 20.09: «убери эти квадраты подсказки»; она включается только
  /// на время обустройства.
  final bool hint;

  /// Если вещь уже выбрана, подсвечиваются только места, которые её примут:
  /// кроватку некуда вешать на стену, и предлагать это место незачем.
  final ShopItem? picked;

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
          return b.metres.compareTo(a.metres);
        });
    // В обустройстве лимит не нужен: человек пришёл ставить вещи и должен
    // видеть все места сразу. Лимит был про подсказку «попробуй сюда» на
    // обычном экране, а это другой разговор.
    final hinted = hint ? empty.toSet() : empty.take(hintLimit).toSet();

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
                  hinted:
                      hint &&
                      (picked == null
                          ? hinted.contains(slot)
                          : slot.takes(picked!)),
                  // Места перекрываются: ковёр лежит под ногами почти во всю
                  // ширину, а поверх него — места игрушек, ближе к зрителю.
                  // Пока вещь в руках, чужое место не должно ловить тап:
                  // заказчик 21.09 жал в подсвеченную рамку ковра и получал
                  // «для этой вещи здесь нет места» — тап забирала игрушка.
                  deaf: picked != null && !slot.takes(picked!),
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
    required bool deaf,
    required void Function(RoomSlot, ShopItem) onTapItem,
    required ValueChanged<RoomSlot> onTapEmpty,
  }) {
    final itemId = game.itemInSlot(slot.id);
    // Вещь без картинки нарисовать нечем: в комнате она не стоит, хотя в
    // сохранении может остаться — каталог держит такие позиции до отрисовки.
    final item = itemId == null || metricsOf(itemId) == null
        ? null
        : ItemCatalog.byId(itemId);

    // Размер занятой вещи — её собственный, с поправкой на глубину; пустого
    // места — по тому, что здесь ожидается. Иначе рамка пустого места
    // прыгала бы в зависимости от того, что в неё поставят.
    final box = item == null ? boxOfHint(slot) : boxOf(slot, item);

    return Positioned(
      left: box.left * width,
      top: box.top * height,
      width: box.width * width,
      height: box.height * height,
      child: IgnorePointer(
        ignoring: deaf,
        child: item != null
            ? _FilledSlot(
                item: item,
                // Занятое место, куда выбранная вещь тоже встанет, обводится
                // пунктиром: иначе человек с кроваткой в руках не видит на
                // экране ни одной подсказки — единственное место, где она
                // помещается, уже занято комодом, — и упирается в тупик.
                replaceable: hinted,
                onTap: () => onTapItem(slot, item),
              )
            : hinted
            ? _EmptySlot(slot: slot, onTap: () => onTapEmpty(slot))
            // Неподсвеченное свободное место всё равно нажимается: человек,
            // который уже понял правило, не должен ждать, пока игра
            // соблаговолит подсветить именно это место.
            : _QuietSlot(onTap: () => onTapEmpty(slot)),
      ),
    );
  }
}

/// Стоящая вещь: картинка ровно того размера, каким вещь видна с этой
/// глубины.
class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.item,
    required this.onTap,
    this.replaceable = false,
  });

  final ShopItem item;

  /// Сюда встанет и то, что сейчас в руках: тап заменит одно другим.
  final bool replaceable;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: shopItemName(context.l10n, item.id),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Ни FittedBox, ни отступов: прямоугольник уже посчитан по
        // пропорциям самой картинки, и вещь занимает его целиком.
        child: replaceable
            ? CustomPaint(
                foregroundPainter: _DashedFrame(fill: false),
                child: ItemPicture(item: item),
              )
            : ItemPicture(item: item),
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
      // Нажимается вся рамка, а не «плюс» в её середине. Без этого палец
      // попадал в подсвеченное место и не попадал никуда: у рамки ковра
      // отзывались полтора сантиметра посередине.
      behavior: HitTestBehavior.opaque,
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
  _DashedFrame({this.fill = true});

  /// Подложка внутри рамки. У пустого места она нужна — рамка читается как
  /// свободное пятно; поверх стоящей вещи её нет, иначе вещь выцветает.
  final bool fill;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(1),
      const Radius.circular(10),
    );

    if (fill) {
      canvas.drawRRect(
        rrect,
        Paint()..color = AppColors.surface.withValues(alpha: 0.35),
      );
    }

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
  bool shouldRepaint(_DashedFrame old) => old.fill != fill;
}

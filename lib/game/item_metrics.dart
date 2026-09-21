/// Настоящие размеры вещей: сколько метров в ширину и как вещь стоит.
///
/// ## Зачем
///
/// До 21.09 размер вещи в комнате задавала рамка места: вещь вписывалась в
/// `maxW × maxH` и занимала столько, сколько разрешит рамка. Из этого выходило
/// то, что заказчик увидел на экране 20.09: мятное кресло у стены мельче
/// подвесного, кресло-цветок вылезало за край, а всё вместе не складывалось в
/// комнату — «как это сделать так, чтобы смотрелось ровно так, как смотрелось,
/// когда фон уже был готовый с мебелью».
///
/// Разгадка простая: на готовом фоне вещи нарисованы по своей настоящей
/// величине и с поправкой на глубину. Кресло там 0.85 м в ширину, ковёр —
/// метр, картина — полметра; что ближе к зрителю, то крупнее. Значит и здесь
/// у каждой вещи должен быть свой размер в метрах, а перспективу считает
/// камера комнаты ([RoomCamera.widthPerMetre]).
///
/// ## Откуда числа
///
/// Ширина — по присланной картинке, с оглядкой на настоящие детские вещи:
/// кресло-мешок 0.95 м, прикроватный столик 0.50 м, плюшевый заяц 0.36 м.
/// Проверка — тот самый обставленный фон: кресло на нём выходит 0.85 × 0.80 м,
/// ковёр-мордочка — метр в поперечнике, рамка картины — 0.55 м. Эти же числа
/// стоят здесь.
///
/// Высота отдельно не задаётся: её даёт сама картинка. Поэтому картинки
/// обрезаны впритык к вещи (`tool/pack_shop.py`) — край файла и есть край
/// вещи, и пропорция [ItemMetrics.aspect] честно её описывает. Сходимость
/// таблицы с картинками проверяет `test/item_metrics_test.dart`.
library;

/// Как вещь держится в комнате.
enum ItemFit {
  /// Стоит на полу: нижний край картинки — там, где вещь касается пола.
  floor,

  /// Лежит на полу. Ширина меряется по середине вещи, а не по ближнему
  /// краю: ковёр уходит вглубь, и его дальняя половина мельче ближней.
  rug,

  /// Висит на стене. Глубина одна на все настенные вещи — сама стена.
  wall,
}

/// Размер и повадка одной вещи.
class ItemMetrics {
  const ItemMetrics(this.metres, this.aspect, this.fit);

  /// Ширина вещи в метрах — её настоящий габарит.
  final double metres;

  /// Отношение высоты картинки к ширине. Высота вещи = [metres] × aspect.
  final double aspect;

  final ItemFit fit;

  /// Высота вещи в метрах — следствие картинки, а не отдельное число.
  double get heightMetres => metres * aspect;
}

/// Размеры всех вещей, у которых есть картинка.
///
/// Вещи без картинки сюда не попадают и в комнату не ставятся: рисовать
/// нечем. Каталог их держит — ждут отрисовки.
const Map<String, ItemMetrics> itemMetrics = {
  // --- Мебель --------------------------------------------------------------
  'bed': ItemMetrics(1.30, 0.895, ItemFit.floor),
  'dresser': ItemMetrics(1.20, 1.034, ItemFit.floor),
  'table': ItemMetrics(0.50, 1.438, ItemFit.floor),
  'basket': ItemMetrics(0.48, 0.895, ItemFit.floor),
  'basket_star': ItemMetrics(0.40, 1.376, ItemFit.floor),
  // Кресла. Ширина — по посадочному месту: детское кресло 0.75–0.85 м,
  // мешок шире, с ушами — уже и выше.
  'armchair': ItemMetrics(0.85, 0.750, ItemFit.floor),
  'armchair_sage': ItemMetrics(0.85, 1.030, ItemFit.floor),
  'armchair_flower': ItemMetrics(0.90, 0.725, ItemFit.floor),
  'armchair_bean': ItemMetrics(0.95, 0.954, ItemFit.floor),
  'armchair_wing': ItemMetrics(0.75, 1.384, ItemFit.floor),
  // Подвесное кресло нарисовано вместе со стойкой, поэтому стоит на полу,
  // а не висит: на экране 20.09 оно парило именно потому, что про стойку
  // никто не знал.
  'swing': ItemMetrics(0.95, 1.180, ItemFit.floor),

  // --- Ковры ---------------------------------------------------------------
  'rug': ItemMetrics(1.05, 0.604, ItemFit.rug),
  'rug_cloud': ItemMetrics(1.10, 0.564, ItemFit.rug),
  'rug_heart': ItemMetrics(1.00, 0.639, ItemFit.rug),

  // --- На стену ------------------------------------------------------------
  'shelf': ItemMetrics(0.90, 0.723, ItemFit.wall),
  'shelf_house': ItemMetrics(0.72, 1.064, ItemFit.wall),
  'shelf_moon': ItemMetrics(0.85, 0.617, ItemFit.wall),
  'pic_bear': ItemMetrics(0.55, 1.237, ItemFit.wall),
  'pic_heart': ItemMetrics(0.50, 1.320, ItemFit.wall),

  // --- Декор на полу -------------------------------------------------------
  'plant': ItemMetrics(0.42, 1.570, ItemFit.floor),
  'plant_ivy': ItemMetrics(0.50, 1.236, ItemFit.floor),
  'plant_bear': ItemMetrics(0.38, 0.931, ItemFit.floor),
  'flowers_daisy': ItemMetrics(0.28, 1.284, ItemFit.floor),
  'flowers_orchid': ItemMetrics(0.30, 1.189, ItemFit.floor),
  'flowers_euc': ItemMetrics(0.28, 1.098, ItemFit.floor),
  'pillow_star': ItemMetrics(0.45, 0.936, ItemFit.floor),

  // --- Игрушки -------------------------------------------------------------
  'teddy': ItemMetrics(0.36, 1.172, ItemFit.floor),
  'teddy_cream': ItemMetrics(0.34, 1.225, ItemFit.floor),
  'bunny': ItemMetrics(0.36, 1.036, ItemFit.floor),
  'bunny_pink': ItemMetrics(0.34, 0.938, ItemFit.floor),
  'cubes': ItemMetrics(0.34, 1.092, ItemFit.floor),
  'pyramid': ItemMetrics(0.26, 1.510, ItemFit.floor),
  'dollhouse': ItemMetrics(0.70, 0.975, ItemFit.floor),
  'house_felt': ItemMetrics(0.62, 1.004, ItemFit.floor),
};

/// Размер вещи или `null`, если картинки у неё нет.
ItemMetrics? metricsOf(String itemId) => itemMetrics[itemId];

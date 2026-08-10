import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Товар каталога физических мишек (КП 12.2).
///
/// Тип публичный, хотя сам список ниже приватный: его принимает [OrderScreen],
/// а приватный тип в публичном конструкторе — это `library_private_types_in
/// _public_api`. Экземпляры всё равно приходят только из [_catalog], то есть
/// собрать «свой» товар мимо каталога неоткуда.
///
/// Поля повторяют то, что КП 12.2 требует показывать в карточке: размер, вид
/// меха, редкость. Одежда в карточку не вынесена — в магазине она продаётся
/// отдельной позицией, см. `docs/heroes-and-catalog.md`.
class CatalogBear {
  const CatalogBear({
    required this.id,
    required this.title,
    required this.size,
    required this.usd,
    required this.heroes,
    required this.colors,
    required this.rarity,
  });

  final String id;
  final String title;

  /// Размер мишки: он же определяет совместимость с гардеробом магазина.
  final String size;

  /// Цена в долларах — валюта магазина, не игровые монеты.
  final double usd;

  /// Кто из двух героев доступен в этой позиции: SLOW, JOY или оба.
  final List<String> heroes;

  /// Виды меха из карточки товара — названия оставлены как в магазине.
  final List<String> colors;

  /// Метка коллекции: Classic, Collector's Edition и т. д.
  final String rarity;

  /// Цена строкой — два знака после точки, как в витрине магазина.
  String get priceLabel => '\$${usd.toStringAsFixed(2)}';
}

/// Каталог физических мишек — данные из официального магазина TeddyTales®.
///
/// КП 12.1 требует показывать «те же товары, фотографии, цены и данные, что в
/// официальном магазине», поэтому список зашит константами и живёт рядом с
/// экраном: это не игровой контент вроде `ItemCatalog`, а витрина чужой
/// системы продаж.
///
/// **ЗАГЛУШКА:** по-настоящему эти четыре позиции должны приезжать с сервера
/// Заказчика вместе с наличием и актуальной ценой (КП 12.5). Пока сервера нет,
/// строки сняты с сохранённых карточек магазина — сверка в
/// `docs/heroes-and-catalog.md`.
const List<CatalogBear> _catalog = <CatalogBear>[
  CatalogBear(
    id: 'fortune15',
    title: 'Карманный мишка Фортуна',
    size: '15 см',
    usd: 119.90,
    heroes: <String>['SLOW', 'JOY'],
    colors: <String>['Milk Tea', 'White'],
    rarity: 'Classic',
  ),
  CatalogBear(
    id: 'hug38',
    title: 'Персиковый Обнимишка',
    size: '38 см',
    usd: 169.90,
    heroes: <String>['SLOW'],
    colors: <String>['Pink', 'Milk Tea', 'White', 'Gray'],
    rarity: 'Classic',
  ),
  CatalogBear(
    id: 'short20',
    title: 'Мишка с короткой шерсткой',
    size: '20 см',
    usd: 99.90,
    heroes: <String>['SLOW'],
    colors: <String>['White', 'Purple', 'Blue', 'Latte'],
    rarity: 'Classic',
  ),
  CatalogBear(
    id: 'set30',
    title: 'Набор Космонавт и Невеста',
    size: '30 см',
    usd: 189.90,
    heroes: <String>['SLOW', 'JOY'],
    colors: <String>['White'],
    rarity: "Collector's Edition",
  ),
];

/// Обувь из магазина: она продаётся отдельной позицией, а не в комплекте.
///
/// В каталоге экрана её нет — там только мишки, — но факт важен и вынесен в
/// подпись внизу: это то же наблюдение, из которого вырос запрос на раздельные
/// слоты рига (`docs/rig-change-request.md`).
const String _shoesTitle = 'Leather Shoes-White-XS';
const double _shoesUsd = 9.90;

/// Страны доставки в выпадающем списке (КП 12.3).
///
/// **ЗАГЛУШКА:** настоящий список стран и правила проверки адреса по стране
/// приходят из системы продаж Заказчика (КП 12.5). Здесь пять стран из
/// принятого прототипа — их достаточно, чтобы показать поведение поля.
const List<String> _countries = <String>[
  'Россия',
  'Казахстан',
  'США',
  'Германия',
  'Китай',
];

/// Каталог физических мишек (КП 12).
///
/// Экран продаёт реальную игрушку, а не игровой предмет, поэтому цены здесь в
/// долларах и кошелька в шапке нет: монеты (КП 11.1) на этот заказ не тратятся.
///
/// На взрослой стадии сверху появляется блок «Твой малыш вырос» — это связка
/// игры с покупкой из КП 12: выращенный за две недели питомец и есть повод
/// заказать его физическую копию. До взрослой стадии блока нет, но каталог
/// открыт всегда — КП 12.1 требует каталог «с первого дня», и по КП 3.5 закрытое
/// показывают, а не прячут.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, required this.controller});

  /// Тот же контроллер, что и на главной: экран читает из него только стадию,
  /// чтобы понять, показывать ли блок «малыш вырос».
  final BearController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final isAdult = controller.state.stage == BearStage.adult;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHeader(title: 'Заказать мишку'),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pagePadding,
                      0,
                      AppDimens.pagePadding,
                      AppDimens.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isAdult) const _GrownUpBanner(),
                        for (final bear in _catalog) ...[
                          _BearCard(
                            bear: bear,
                            onOrder: () => _openOrder(context, bear),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          'Товары, цены и размеры — из официального магазина '
                          'TeddyTales®, как требует КП 12.1. Фотографии '
                          'подставлены одинаковые: настоящие снимки берутся из '
                          'каталога Заказчика. Обувь там продаётся отдельно — '
                          '$_shoesTitle, \$${_shoesUsd.toStringAsFixed(2)}.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openOrder(BuildContext context, CatalogBear bear) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => OrderScreen(item: bear)),
    );
  }
}

/// Блок над каталогом на взрослой стадии.
///
/// Текст дословно из прототипа: он про питомца, а не про товар, и поэтому стоит
/// выше карточек — сначала повод, потом витрина.
class _GrownUpBanner extends StatelessWidget {
  const _GrownUpBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.cream,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.sageSoft, width: 2),
            ),
            // ЗАГЛУШКА: эмодзи вместо портрета питомца. Здесь должен стоять
            // кадр из рига во взрослой стадии — с той же шкурой и одеждой, что
            // на главной. Ассетов нет, эмодзи стоит из прототипа.
            child: const Center(
              child: Text('🧸', style: TextStyle(fontSize: 44)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Твой малыш вырос',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'и готов отправиться к тебе домой',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка товара: фотография, название, цена и конфигурация (КП 12.2).
class _BearCard extends StatelessWidget {
  const _BearCard({required this.bear, required this.onOrder});

  final CatalogBear bear;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ЗАГЛУШКА: фотографии у всех четырёх позиций одинаковые. Настоящие
          // снимки лежат в каталоге Заказчика (КП 12.1) и приедут вместе с
          // данными о товарах; про это сказано подписью внизу экрана.
          Container(
            height: 150,
            color: AppColors.cream,
            child: const Center(
              child: Text('🧸', style: TextStyle(fontSize: 60)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bear.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      bear.priceLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${bear.size} · ${bear.rarity}',
                      style: _metaStyle(theme),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  // Герои через дробь, цвета меха через запятую — как в
                  // прототипе: дробь читается как «или», перечисление через
                  // запятую — как набор вариантов одной позиции.
                  '${bear.heroes.join(' / ')} · ${bear.colors.join(', ')}',
                  style: _metaStyle(theme),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: onOrder,
              child: const Text(
                'Оформить заказ',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _metaStyle(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
    fontSize: 10.5,
    color: AppColors.textSecondary,
  );
}

/// Оформление заказа и оплата (КП 12.3, 12.4).
///
/// Форма ничего не отправляет: по КП 12.5 заказ уходит в действующую систему
/// продаж Заказчика, а её у нас нет. Поэтому экран показывает состав заказа,
/// собирает данные получателя и на кнопках оплаты честно говорит, что
/// интеграция будет позже — так же, как в принятом прототипе.
///
/// **ЗАГЛУШКА:** проверки адреса по стране (КП 12.3) нет — правила у каждой
/// страны свои и приходят вместе с системой продаж. Поля не валидируются
/// вообще, чтобы не изображать проверку, которой не существует.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.item});

  /// Заказываемый товар — из каталога на предыдущем экране.
  final CatalogBear item;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _postcode = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  /// Страна по умолчанию — первая в списке: пустой селект заставил бы
  /// открывать его ради очевидного значения.
  String _country = _countries.first;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _postcode.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _pay() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Оплата подключается на этапе интеграции'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(title: 'Оформление'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pagePadding,
                  0,
                  AppDimens.pagePadding,
                  AppDimens.pagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Состав заказа перед формой: человек должен видеть, за что
                    // платит, до того как начнёт вводить адрес.
                    _SummaryCard(
                      rows: <(String, String)>[
                        ('Товар', item.title),
                        ('Размер', item.size),
                        ('Цена', item.priceLabel),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      label: 'Имя и фамилия',
                      hint: 'Как в документах',
                      controller: _name,
                      keyboardType: TextInputType.name,
                    ),
                    _CountryField(
                      value: _country,
                      onChanged: (value) => setState(() => _country = value),
                    ),
                    _Field(
                      label: 'Адрес',
                      hint: 'Улица, дом, квартира',
                      controller: _address,
                      keyboardType: TextInputType.streetAddress,
                    ),
                    _Field(
                      label: 'Индекс',
                      hint: '123456',
                      controller: _postcode,
                      keyboardType: TextInputType.number,
                    ),
                    _Field(
                      label: 'Телефон',
                      hint: '+7 900 000-00-00',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const _SectionTitle('Оплата · КП 12.4'),
                    // Три способа ровно по КП 12.4. Порядок как в прототипе:
                    // китайские кошельки первыми — магазин работает на Азию, а
                    // PayPal замыкает список как способ «для всех остальных».
                    _PayButton(emoji: '💚', title: 'WeChat Pay', onTap: _pay),
                    const SizedBox(height: 8),
                    _PayButton(emoji: '🔵', title: 'Alipay', onTap: _pay),
                    const SizedBox(height: 8),
                    _PayButton(
                      emoji: '🅿️',
                      title: 'PayPal',
                      // КП 12.4 отдельно оговаривает оплату картой без
                      // аккаунта — это свойство PayPal, и его нужно назвать,
                      // иначе человек без аккаунта решит, что способ не для
                      // него.
                      note: ' — и картой без аккаунта',
                      onTap: _pay,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Доставка по данным магазина: США 7–9 рабочих дней, '
                      'Канада 8–10, Европа 9–11, Азия 5–7. Заказ уходит в '
                      'действующую систему продаж Заказчика (КП 12.5) — здесь '
                      'форма без отправки.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Состав заказа: подпись слева, значение справа.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    row.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (index != rows.length - 1)
              const Divider(height: 1, color: AppColors.outline),
          ],
        ],
      ),
    );
  }
}

/// Заголовок раздела формы — мелкий, капсом, с номером пункта КП.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 7),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          letterSpacing: 0.77,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Поле формы: подпись сверху, ввод снизу.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 13),
            decoration: _fieldDecoration(hint: hint),
          ),
        ],
      ),
    );
  }
}

/// Страна — выпадающий список, как требует КП 12.3.
///
/// Именно список, а не свободный ввод: от страны зависят и правила проверки
/// адреса, и сроки доставки из подписи внизу, а по опечатке в названии страны
/// ни того, ни другого не выбрать.
class _CountryField extends StatelessWidget {
  const _CountryField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Страна'),
          DropdownButtonFormField<String>(
            initialValue: value,
            isDense: true,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            dropdownColor: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusChip),
            icon: const Icon(
              Icons.expand_more,
              size: 18,
              color: AppColors.textSecondary,
            ),
            decoration: _fieldDecoration(),
            items: <DropdownMenuItem<String>>[
              for (final country in _countries)
                DropdownMenuItem<String>(value: country, child: Text(country)),
            ],
            onChanged: (selected) {
              if (selected == null) return;
              onChanged(selected);
            },
          ),
        ],
      ),
    );
  }
}

/// Подпись над полем ввода.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Оформление поля ввода: одно на текст и на выпадающий список, чтобы они
/// стояли в колонке одинаковыми.
InputDecoration _fieldDecoration({String? hint}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppDimens.radiusChip),
    borderSide: const BorderSide(color: AppColors.outline),
  );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    filled: true,
    fillColor: AppColors.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.sage),
    ),
  );
}

/// Кнопка способа оплаты (КП 12.4).
class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.emoji,
    required this.title,
    required this.onTap,
    this.note,
  });

  /// ЗАГЛУШКА: эмодзи вместо логотипа платёжной системы. Настоящие логотипы —
  /// это брендовые материалы WeChat Pay, Alipay и PayPal, их берут из
  /// гайдлайнов каждой системы на этапе интеграции.
  final String emoji;
  final String title;

  /// Приписка мелким серым — сейчас только у PayPal.
  final String? note;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppDimens.radiusCard);
    final note = this.note;

    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 19)),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: note == null
                        ? null
                        : <InlineSpan>[
                            TextSpan(
                              text: note,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, справа пусто.
///
/// Кошелька здесь нет намеренно — как и в прототипе: физического мишку берут за
/// доллары через систему продаж Заказчика (КП 12.5), игровые монеты (КП 11.1)
/// к этой покупке отношения не имеют, и показывать их рядом с ценой в долларах
/// значило бы предлагать расплатиться ими.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        8,
        AppDimens.pagePadding,
        10,
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.outline),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          // Ширина кнопки «назад» плюс тот же зазор — заголовок остаётся ровно
          // по центру экрана.
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

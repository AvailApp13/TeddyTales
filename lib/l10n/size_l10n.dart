import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Рост и вес мишки в подписи (КП 2.2): рост с одним знаком после запятой
/// по правилам языка («15,3» / «15.3»), вес целым.
String formatCm(BuildContext context, double cm) =>
    NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    ).format(cm);

String formatG(double g) => g.round().toString();

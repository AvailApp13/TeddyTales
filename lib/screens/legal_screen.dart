import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Правовые документы (КП 14.2): условия использования и политика
/// конфиденциальности. Открываются со стартовой страницы (строка «Продолжая,
/// вы принимаете…») и из настроек.
///
/// Тексты лежат в `assets/legal/<документ>_<язык>.md` и подставляются без
/// правок кода: заказчик 25.09 — тексты пришлёт Ирина. До них там заглушки
/// «текст готовится». Нет файла на языке интерфейса — берётся английский.
///
/// Разметка нарочно простая, чтобы не тянуть библиотеку ради двух
/// страниц: `# Заголовок`, `## Подзаголовок`, `- пункт`, абзацы через
/// пустую строку.
enum LegalDoc {
  terms('terms'),
  privacy('privacy');

  const LegalDoc(this.file);

  final String file;

  String title(AppLocalizations l10n) => switch (this) {
    LegalDoc.terms => l10n.legalTerms,
    LegalDoc.privacy => l10n.legalPrivacy,
  };
}

/// Загрузить текст документа на языке [languageCode]; нет такого — на
/// английском.
Future<String> loadLegalText(LegalDoc doc, String languageCode) async {
  for (final lang in [languageCode, 'en']) {
    try {
      return await rootBundle.loadString('assets/legal/${doc.file}_$lang.md');
    } on FlutterError {
      continue;
    }
  }
  return '';
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  static Future<void> open(BuildContext context, LegalDoc doc) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(doc.title(l10n)),
        // «Политика конфиденциальности» стандартным кеглем в шапку 390 px
        // не входит — обрезалась многоточием.
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: loadLegalText(doc, lang),
          builder: (context, snapshot) {
            final text = snapshot.data;
            if (text == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: LegalText(text),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Текст документа простой разметкой: заголовки, пункты, абзацы.
class LegalText extends StatelessWidget {
  const LegalText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = theme.bodyMedium?.copyWith(
      height: 1.5,
      color: AppColors.textPrimary,
    );
    final children = <Widget>[];
    for (final block in text.trim().split(RegExp(r'\n\s*\n'))) {
      final lines = block.trim().split('\n');
      if (lines.first.startsWith('# ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              lines.first.substring(2),
              style: theme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        );
      } else if (lines.first.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(
              lines.first.substring(3),
              style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (lines.every((l) => l.trimLeft().startsWith('- '))) {
        for (final line in lines) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: body),
                  Expanded(
                    child: Text(line.trimLeft().substring(2), style: body),
                  ),
                ],
              ),
            ),
          );
        }
        children.add(const SizedBox(height: 8));
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(lines.join(' '), style: body),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

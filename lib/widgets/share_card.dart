import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../bear/bear.dart';
import '../game/game_calendar.dart';
import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../l10n/size_l10n.dart';
import '../l10n/zodiac_l10n.dart';
import '../theme/app_colors.dart';

/// «Поделиться» (сверх ТЗ, заказчик 25.09): карточка мишки картинкой —
/// имя, стадия, возраст, знак, рост и вес при рождении. Сначала человек
/// видит карточку, потом отправляет её в любое приложение телефона.
///
/// [grown] — повод «подрос!» (новая стадия); иначе «Знакомьтесь».
Future<void> showShareCard(
  BuildContext context, {
  required GameState game,
  required BearStage stage,
  bool grown = false,
  GameCalendar calendar = const GameCalendar(),
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ShareDialog(
      game: game,
      stage: stage,
      grown: grown,
      calendar: calendar,
    ),
  );
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({
    required this.game,
    required this.stage,
    required this.grown,
    required this.calendar,
  });

  final GameState game;
  final BearStage stage;
  final bool grown;
  final GameCalendar calendar;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final boundary =
          _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final name = petDisplayName(l10n, widget.game.profile.name);
      await SharePlus.instance.share(
        ShareParams(
          text: l10n.shareText(name),
          files: [
            XFile.fromData(
              png!.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'teddytales.png',
            ),
          ],
          fileNameOverrides: const ['teddytales.png'],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(
              // Углы скругляет окно, а не карточка: в картинке углы прямые,
              // иначе мессенджеры закрашивают прозрачные уголки чёрным.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: RepaintBoundary(
                  key: _card,
                  child: PetShareCard(
                    game: widget.game,
                    stage: widget.stage,
                    grown: widget.grown,
                    calendar: widget.calendar,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                ),
                child: Text(l10n.shareClose),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const ValueKey('share-send'),
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(l10n.shareAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Сама карточка: 360 в ширину, высота по тексту; в картинку снимается
/// втрое крупнее.
class PetShareCard extends StatelessWidget {
  const PetShareCard({
    super.key,
    required this.game,
    required this.stage,
    this.grown = false,
    this.calendar = const GameCalendar(),
  });

  final GameState game;
  final BearStage stage;
  final bool grown;
  final GameCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = game.profile;
    final name = petDisplayName(l10n, profile.name);
    final zodiac = profile.zodiac;
    final birthday = DateFormat.yMMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(profile.birthAt.toLocal());
    final facts = [
      if (zodiac != null) '${zodiac.symbol} ${zodiacTitle(l10n, zodiac)}',
      if (profile.birthHeightCm case final cm?)
        l10n.profileHeightValue(formatCm(context, cm)),
      if (profile.birthWeightG case final g?)
        l10n.profileWeightValue(formatG(g)),
    ];

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 360,
        color: AppColors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Спальня мишки и он сам — те же картинки, что в игре.
            SizedBox(
              height: 290,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/rooms/bedroom.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, 0.1),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00FFFBF2), Color(0xCCFFFBF2)],
                        stops: [0.55, 1],
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.95),
                    child: Image.asset(
                      'assets/rooms/bedroom/bear_open.png',
                      height: 230,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grown ? l10n.shareGrown(name) : l10n.shareMeet(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stageTitle(l10n, stage)} · '
                    '${formatAge(l10n, calendar.ageAt(profile.birthAt))}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final fact in facts) _Chip(fact),
                      _Chip(l10n.shareBirthday(birthday)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(Icons.pets, size: 16, color: AppColors.tan),
                      SizedBox(width: 6),
                      Text(
                        'TeddyTales',
                        style: TextStyle(
                          color: AppColors.tan,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

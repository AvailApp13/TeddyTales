import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../bear/bear.dart';
import '../game/game_calendar.dart';
import '../game/game_state.dart';
import '../game/referral_info.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../l10n/size_l10n.dart';
import '../l10n/zodiac_l10n.dart';
import '../theme/app_colors.dart';

/// «Поделиться» (сверх ТЗ, заказчик 25.09): одно окно на карточку мишки и
/// приглашение друга. Карточка — фото мишки, имя, стадия, возраст, знак,
/// рост и вес; ниже свой код приглашения и поле для кода друга. «Поделиться»
/// отправляет картинку вместе с приглашением в любое приложение телефона.
/// Открывается кнопкой в шапке главного экрана.
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
  final _friend = TextEditingController();
  bool _busy = false;
  bool _redeeming = false;

  /// Код приглашения с сервера; `null` — нет аккаунта или связи, тогда
  /// делимся только карточкой.
  ReferralInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _friend.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await widget.game.referral();
    if (mounted) setState(() => _info = info);
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _share() async {
    final l10n = context.l10n;
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
      final info = _info;
      // Картинка и приглашение уходят одним сообщением: куда — выбирает
      // сам телефон (WhatsApp, WeChat, Telegram, почта…).
      await SharePlus.instance.share(
        ShareParams(
          text: info == null || info.code.isEmpty
              ? l10n.shareText(name)
              : l10n
                    .inviteShareText(info.code, info.coins, info.inviteLink)
                    .trim(),
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
      _say(l10n.shareFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeem(ReferralInfo info) async {
    final l10n = context.l10n;
    final code = _friend.text.trim();
    if (code.isEmpty) return;
    setState(() => _redeeming = true);
    final result = await widget.game.redeemReferral(code);
    if (!mounted) return;
    setState(() => _redeeming = false);
    _say(redeemMessage(l10n, result, info.coins));
    if (result != RedeemResult.offline && result != RedeemResult.notFound) {
      _friend.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = _info;
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Углы скругляет окно, а не карточка: в картинке углы прямые,
            // иначе мессенджеры закрашивают прозрачные уголки чёрным.
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: FittedBox(
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
            if (info != null && info.code.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InviteBlock(
                info: info,
                friend: _friend,
                busy: _redeeming,
                onCopied: () => _say(l10n.inviteCopied),
                onRedeem: () => _redeem(info),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('share-send'),
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text(l10n.shareAction),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.shareClose),
            ),
          ],
        ),
      ),
    );
  }
}

/// Код приглашения и поле для кода друга (миграция 0021): обоим монеты.
class _InviteBlock extends StatelessWidget {
  const _InviteBlock({
    required this.info,
    required this.friend,
    required this.busy,
    required this.onCopied,
    required this.onRedeem,
  });

  final ReferralInfo info;
  final TextEditingController friend;
  final bool busy;
  final VoidCallback onCopied;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.inviteYourCode,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      info.code,
                      key: const ValueKey('invite-code'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.inviteCopied,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: info.code));
                  onCopied();
                },
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              l10n.inviteLead(info.coins),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InviteStats(info: info),
          ),
          if (info.canRedeem) ...[
            const Divider(height: 20, color: AppColors.outline),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('invite-field'),
                      controller: friend,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (_, value) =>
                              value.copyWith(text: value.text.toUpperCase()),
                        ),
                      ],
                      decoration: InputDecoration(
                        hintText: l10n.inviteHaveCode,
                        counterText: '',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => onRedeem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    key: const ValueKey('invite-redeem'),
                    onPressed: busy ? null : onRedeem,
                    child: Text(l10n.inviteRedeem),
                  ),
                ],
              ),
            ),
          ],
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
            // Фото настоящего мишки TeddyTales (прислал заказчик 25.09).
            SizedBox(
              height: 330,
              child: Image.asset(
                'assets/images/share_bear.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(0, 0.33),
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

/// Статистика приглашений (заказчик 26.09): сколько друзей пришло, сколько
/// монет это принесло, и лестница бонусов — 3, 5, 10 друзей.
class InviteStats extends StatelessWidget {
  const InviteStats({super.key, required this.info});

  final ReferralInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final next = info.nextMilestone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                key: const ValueKey('invite-friends'),
                value: '${info.invited}',
                label: l10n.inviteStatsFriends,
                icon: Icons.people_alt_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                key: const ValueKey('invite-earned'),
                value: '${info.earned}',
                label: l10n.inviteStatsEarned,
                icon: Icons.monetization_on,
                iconColor: AppColors.coin,
              ),
            ),
          ],
        ),
        if (info.milestones.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (final m in info.milestones)
                Expanded(
                  child: _Step(
                    friends: m.friends,
                    bonus: m.bonus,
                    reached: info.invited >= m.friends,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            next == null
                ? l10n.inviteLadderDone
                : l10n.inviteNextBonus(next.friends - info.invited, next.bonus),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.iconColor = AppColors.sageDark,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ступень лестницы: кружок с числом друзей, под ним бонус; пройдена —
/// зелёная с галочкой.
class _Step extends StatelessWidget {
  const _Step({
    required this.friends,
    required this.bonus,
    required this.reached,
  });

  final int friends;
  final int bonus;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: reached ? AppColors.sage : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: reached ? AppColors.sageDark : AppColors.outline,
              width: 2,
            ),
          ),
          child: reached
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : Text(
                  '$friends',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(height: 3),
        Text(
          '+$bonus',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: reached ? AppColors.sageDark : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Что сказать после ввода кода друга.
String redeemMessage(AppLocalizations l10n, RedeemResult result, int coins) =>
    switch (result) {
      RedeemResult.ok => l10n.inviteDone(coins),
      RedeemResult.notFound => l10n.inviteNotFound,
      RedeemResult.ownCode => l10n.inviteOwn,
      RedeemResult.alreadyUsed => l10n.inviteUsed,
      RedeemResult.tooLate => l10n.inviteLate,
      RedeemResult.inviterFull => l10n.inviteFull,
      RedeemResult.offline => l10n.inviteOffline,
    };

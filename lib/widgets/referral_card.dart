import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/game_state.dart';
import '../game/referral_info.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// «Пригласи друга» в профиле (сверх ТЗ, заказчик 25.09; миграция 0021):
/// свой код, приглашение в любое приложение и поле для кода друга.
///
/// Без аккаунта или без связи блока нет вовсе: код выдаёт только сервер.
class ReferralCard extends StatefulWidget {
  const ReferralCard({super.key, required this.game, required this.title});

  final GameState game;

  /// Заголовок раздела — прячется вместе с блоком.
  final Widget title;

  @override
  State<ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<ReferralCard> {
  ReferralInfo? _info;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
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

  Future<void> _invite(ReferralInfo info) async {
    final l10n = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: l10n
            .inviteShareText(info.code, info.coins, info.inviteLink)
            .trim(),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _redeem(ReferralInfo info) async {
    final l10n = context.l10n;
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    final result = await widget.game.redeemReferral(code);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(switch (result) {
      RedeemResult.ok => l10n.inviteDone(info.coins),
      RedeemResult.notFound => l10n.inviteNotFound,
      RedeemResult.ownCode => l10n.inviteOwn,
      RedeemResult.alreadyUsed => l10n.inviteUsed,
      RedeemResult.tooLate => l10n.inviteLate,
      RedeemResult.inviterFull => l10n.inviteFull,
      RedeemResult.offline => l10n.inviteOffline,
    });
    if (result != RedeemResult.offline && result != RedeemResult.notFound) {
      _code.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || info.code.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.title,
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.inviteLead(info.coins),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
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
                            fontSize: 24,
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
                      _say(l10n.inviteCopied);
                    },
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('invite-share'),
                onPressed: () => _invite(info),
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(l10n.inviteShare),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.inviteCount(info.invited),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (info.canRedeem) ...[
                const Divider(height: 24, color: AppColors.outline),
                Text(
                  l10n.inviteHaveCode,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('invite-field'),
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (_, value) =>
                                value.copyWith(text: value.text.toUpperCase()),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: l10n.inviteCodeHint,
                          counterText: '',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _redeem(info),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      key: const ValueKey('invite-redeem'),
                      onPressed: _busy ? null : () => _redeem(info),
                      child: Text(l10n.inviteRedeem),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

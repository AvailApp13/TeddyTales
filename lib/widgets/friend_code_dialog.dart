import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_state.dart';
import '../game/referral_info.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'gift_reveal.dart' show showCoinReward;
import 'glass_panel.dart';
import 'share_card.dart' show redeemMessage;

/// «Тебя пригласил друг?» — после имени мишки при первом запуске
/// (заказчик 26.09).
///
/// Друг прислал ссылку → страница приглашения скопировала код в буфер
/// («TEDDY-ZP65BM») → человек поставил приложение. Здесь код находится сам:
/// одна кнопка «Получить +100», и монеты приходят обоим. Кода в буфере нет
/// — поле, куда его можно вставить руками, и «Пропустить».
///
/// Без связи или если код вводить уже поздно — окна нет.
Future<void> showFriendCodeDialog(BuildContext context, GameState game) async {
  final info = await game.referral();
  if (info == null || !info.canRedeem || !context.mounted) return;

  String? found;
  try {
    // hasStrings не показывает системный вопрос о вставке; само чтение
    // на iPhone спросит «Разрешить вставку» — один раз.
    if (await Clipboard.hasStrings()) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      found = ReferralInfo.codeFrom(data?.text);
      if (found == info.code) found = null;
    }
  } on Object {
    found = null;
  }
  if (!context.mounted) return;

  final ok = await showGlassPanel<bool>(
    context: context,
    center: const Offset(0.5, 0.42),
    width: 330,
    builder: (context) =>
        _FriendCodeDialog(game: game, info: info, found: found),
  );
  // Монеты пришли — праздник на экране (заказчик 26.09).
  if (ok == true && context.mounted) {
    await showCoinReward(
      context,
      amount: info.coins,
      total: game.coins,
      title: context.l10n.rewardFromFriend,
    );
  }
}

class _FriendCodeDialog extends StatefulWidget {
  const _FriendCodeDialog({
    required this.game,
    required this.info,
    required this.found,
  });

  final GameState game;
  final ReferralInfo info;
  final String? found;

  @override
  State<_FriendCodeDialog> createState() => _FriendCodeDialogState();
}

class _FriendCodeDialogState extends State<_FriendCodeDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.found ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final l10n = context.l10n;
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.game.redeemReferral(code);
    if (!mounted) return;
    final message = redeemMessage(l10n, result, widget.info.coins);
    if (result == RedeemResult.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    if (result == RedeemResult.alreadyUsed || result == RedeemResult.tooLate) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final found = widget.found;
    final coins = widget.info.coins;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassTitle(
          l10n.friendCodeTitle,
          close: false,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.blushStrong, width: 3),
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              size: 18,
              color: Color(0xFFD42A33),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          found != null
              ? l10n.friendCodeFound(found, coins)
              : l10n.friendCodeAsk(coins),
          style: glassText(14.5, 650, color: AppColors.textPrimary),
        ),
        if (found == null) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('friend-code-field'),
            controller: _code,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (_, value) => value.copyWith(text: value.text.toUpperCase()),
              ),
            ],
            style: glassText(
              22,
              900,
              color: AppColors.textPrimary,
            ).copyWith(letterSpacing: 4),
            decoration: glassField(hint: 'ZP65BM', error: _error, counter: ''),
            onSubmitted: (_) => _redeem(),
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: glassText(13, 700, color: const Color(0xFFB3261E)),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                key: const ValueKey('friend-code-skip'),
                label: l10n.friendCodeSkip,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                key: const ValueKey('friend-code-claim'),
                primary: true,
                icon: Icons.monetization_on,
                label: l10n.friendCodeClaim(coins),
                onPressed: _busy ? null : _redeem,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

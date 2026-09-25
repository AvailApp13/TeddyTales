/// «Пригласи друга» (сверх ТЗ, заказчик 25.09; миграция 0021): свой код,
/// сколько друзей пришло, можно ли ещё ввести код друга.
class ReferralInfo {
  const ReferralInfo({
    required this.code,
    required this.invited,
    required this.coins,
    required this.link,
    required this.canRedeem,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) => ReferralInfo(
    code: json['code']?.toString() ?? '',
    invited: (json['invited'] as num?)?.toInt() ?? 0,
    coins: (json['coins'] as num?)?.toInt() ?? 0,
    link: json['link']?.toString() ?? '',
    canRedeem: json['can_redeem'] == true,
  );

  final String code;
  final int invited;

  /// Сколько монет получает каждый из двоих.
  final int coins;

  /// Куда ведёт приглашение; код добавляется к ней как `?ref=`.
  final String link;
  final bool canRedeem;

  /// Ссылка приглашения с кодом.
  String get inviteLink {
    if (link.isEmpty) return '';
    final uri = Uri.parse(link);
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'ref': code})
        .toString();
  }
}

/// Итог ввода кода друга.
enum RedeemResult {
  ok,
  notFound,
  ownCode,
  alreadyUsed,
  tooLate,
  inviterFull,
  offline,
}

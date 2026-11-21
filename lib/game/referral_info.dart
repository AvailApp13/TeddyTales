/// «Пригласи друга» (сверх ТЗ, заказчик 25.09; миграция 0021): свой код,
/// сколько друзей пришло, можно ли ещё ввести код друга.
class ReferralInfo {
  const ReferralInfo({
    required this.code,
    required this.invited,
    required this.coins,
    required this.link,
    required this.canRedeem,
    this.earned = 0,
    this.milestones = const [],
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) => ReferralInfo(
    code: json['code']?.toString() ?? '',
    invited: (json['invited'] as num?)?.toInt() ?? 0,
    coins: (json['coins'] as num?)?.toInt() ?? 0,
    link: json['link']?.toString() ?? '',
    canRedeem: json['can_redeem'] == true,
    earned: (json['earned'] as num?)?.toInt() ?? 0,
    milestones: [
      for (final m
          in (json['milestones'] is List
              ? json['milestones'] as List
              : const []))
        if (m is Map)
          (
            friends: (m['friends'] as num?)?.toInt() ?? 0,
            bonus: (m['bonus'] as num?)?.toInt() ?? 0,
          ),
    ],
  );

  final String code;
  final int invited;

  /// Сколько монет получает каждый из двоих.
  final int coins;

  /// Куда ведёт приглашение; код добавляется к ней как `?ref=`.
  final String link;
  final bool canRedeem;

  /// Сколько монет принесли приглашения: по другу и бонусы лестницы
  /// (миграция 0024).
  final int earned;

  /// Лестница: сколько друзей — какой бонус сверху (3, 5, 10).
  final List<({int friends, int bonus})> milestones;

  /// Следующая ступень; `null` — все пройдены.
  ({int friends, int bonus})? get nextMilestone {
    for (final m in milestones) {
      if (invited < m.friends) return m;
    }
    return null;
  }

  /// Метка кода в буфере обмена: страница приглашения копирует
  /// «TEDDY-ZP65BM», приложение при первом запуске её находит.
  static String clipboardText(String code) => 'TEDDY-$code';

  /// Код друга из текста буфера: «TEDDY-ZP65BM» или ссылка с `ref=`.
  /// Знаки — как в коде на сервере: без 0/O и 1/I/L.
  static String? codeFrom(String? text) {
    if (text == null) return null;
    final match = RegExp(
      r'(?:TEDDY[-\s]?|[?&]ref=)([A-HJKMNP-Z2-9]{6})\b',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.toUpperCase();
  }

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

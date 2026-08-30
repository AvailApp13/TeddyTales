import 'package:flutter/material.dart';

import '../game/game_calendar.dart';
import '../game/pet_profile.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Шапка главного экрана: аватар, имя питомца, игровой возраст, монеты
/// (КП 3.3).
///
/// На макете правее монет есть счётчик сердец и полоса уровня — обе механики
/// в КП отсутствуют и отложены во вторую версию, поэтому здесь их нет.
class PetHeader extends StatelessWidget {
  const PetHeader({
    super.key,
    required this.profile,
    required this.age,
  });

  final PetProfile profile;
  final GameAge age;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          _Avatar(profile: profile),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  petDisplayName(context.l10n, profile.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatAge(context.l10n, age),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _CoinBalance(coins: profile.coins),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final PetProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // Цвет кружка — по меху героя: SLOW тёплый бежевый, JOY белый.
        color: profile.skin.furColor == 'White'
            ? AppColors.cream
            : AppColors.tan,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outline),
      ),
      // Портрет питомца появится, когда будет риг: КП 3.3 показывает в шапке
      // именно мишку, а не иконку.
      child: const Icon(Icons.pets, size: 20, color: Colors.white),
    );
  }
}

class _CoinBalance extends StatelessWidget {
  const _CoinBalance({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

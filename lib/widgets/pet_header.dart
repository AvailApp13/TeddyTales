import 'package:flutter/material.dart';

import '../game/game_calendar.dart';
import '../game/pet_profile.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Шапка главного экрана: монеты, имя питомца с возрастом, вход в профиль
/// (КП 3.3).
///
/// Перестроена 20.09 решением заказчика: профиль поднялся из нижнего меню
/// сюда, на место, где стояли монеты, а монеты ушли левее. Шапка перестала
/// быть одной карточкой — теперь это три отдельных предмета поверх комнаты:
/// комната идёт на весь экран, и сплошная плашка закрывала бы её зря.
///
/// На макете правее монет есть счётчик сердец и полоса уровня — обе механики
/// в КП отсутствуют и отложены во вторую версию, поэтому здесь их нет.
class PetHeader extends StatelessWidget {
  const PetHeader({
    super.key,
    required this.profile,
    required this.age,
    this.onOpenProfile,
  });

  final PetProfile profile;
  final GameAge age;

  /// Открыть профиль. `null` — кружок справа не нажимается.
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _CoinBalance(coins: profile.coins),
        // Имя не в плашке, а прямо на потолке: обводка по букве держит его
        // читаемым на любом фоне комнаты, от розовой детской до голубой
        // ванной, и не отнимает у комнаты полосу во всю ширину.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Outlined(
                  text: petDisplayName(context.l10n, profile.name),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _Outlined(
                  text: formatAge(context.l10n, age),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        _ProfileButton(profile: profile, onTap: onOpenProfile),
      ],
    );
  }
}

/// Текст со светлой обводкой — чтобы читался поверх комнаты.
///
/// Две копии одна поверх другой: нижняя обведена цветом фона приложения,
/// верхняя залита. Тень тут не годится — она читается как объём и на
/// светлом потолке превращается в грязь.
class _Outlined extends StatelessWidget {
  const _Outlined({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.background,
          ),
        ),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ],
    );
  }
}

/// Вход в профиль: кружок с портретом питомца.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.profile, required this.onTap});

  final PetProfile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.navSectionProfile,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.outline, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  // Цвет кружка — по меху героя: SLOW тёплый бежевый, JOY
                  // белый.
                  color: profile.skin.furColor == 'White'
                      ? AppColors.cream
                      : AppColors.tan,
                  shape: BoxShape.circle,
                ),
                // Портрет питомца появится, когда будет риг: КП 3.3
                // показывает в шапке именно мишку, а не иконку.
                child: const Icon(Icons.pets, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinBalance extends StatelessWidget {
  const _CoinBalance({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [Color(0xFFFCE4AC), AppColors.coin],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFDFA83E), width: 1.5),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$coins',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

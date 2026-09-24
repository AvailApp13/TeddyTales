import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_calendar.dart';
import '../game/pet_profile.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'feed_burst.dart';
import 'scene_label.dart';

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
    this.fx,
  });

  final PetProfile profile;
  final GameAge age;

  /// Пузырь сытости: монеты делают «у-у» в момент его удара (заказчик
  /// 24.09) — до удара на кнопке прежний баланс.
  final FeedFx? fx;

  /// Открыть профиль. `null` — кружок справа не нажимается.
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (fx case final fx?)
          ListenableBuilder(
            listenable: fx,
            builder: (context, _) => _CoinBalance(
              coins: fx.coins(profile.coins),
              bump: fx.coinBump,
              delta: fx.coinDelta,
              chip: fx.coinChip,
            ),
          )
        else
          _CoinBalance(coins: profile.coins),
        // Имя с возрастом — одной капсулой, как подписи колец и лепестков.
        // Обводка по букве, стоявшая здесь до 20.09, на светлом потолке
        // сливалась с фоном, а на тёмном давала ореол.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SceneLabel(
                text: petDisplayName(context.l10n, profile.name),
                trailing: formatAge(context.l10n, age),
                size: 13.5,
                weight: 800,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 5,
                ),
              ),
            ),
          ),
        ),
        _ProfileButton(profile: profile, onTap: onOpenProfile),
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

class _CoinBalance extends StatefulWidget {
  const _CoinBalance({
    required this.coins,
    this.bump,
    this.delta = 0,
    this.chip,
  });

  final int coins;

  /// «У-у»: 0…1 от удара пузыря до покоя, `null` — покой.
  final double? bump;

  /// Сколько монет ушло или пришло и где плашка «−7» в своём пути 0…1.
  final int delta;
  final double? chip;

  @override
  State<_CoinBalance> createState() => _CoinBalanceState();
}

class _CoinBalanceState extends State<_CoinBalance> {
  // Плашка «−7» живёт в оверлее, а к кнопке привязана ссылкой: в колонке
  // шапки кольца показателей идут следом и рисовались поверх неё — «−7»
  // пряталось под кружком «Игра» (заказчик 24.09: «чтобы он был поверх
  // всего»).
  final _link = LayerLink();
  final _portal = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) {
    final t = widget.bump;
    final pill = _pill(context, t);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _chip,
      child: CompositedTransformTarget(
        link: _link,
        child: t == null
            ? pill
            // Кнопка вздыхает: раздувается и, покачавшись, сдувается. Вокруг
            // — тёплое свечение.
            : Transform.scale(
                scale: 1 + 0.16 * FeedFx.bounce(t),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFFFFD58A,
                        ).withValues(alpha: 0.8 * math.pow(1 - t, 2)),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: pill,
                ),
              ),
      ),
    );
  }

  Widget _chip(BuildContext context) {
    final c = widget.chip;
    final delta = widget.delta;
    if (c == null || delta == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        offset: Offset(26, 34 + 22 * Curves.easeOutCubic.transform(c)),
        child: IgnorePointer(
          child: Opacity(
            key: const ValueKey('coins-delta'),
            opacity: (c < 0.15 ? c / 0.15 : 1 - (c - 0.15) / 0.85).clamp(
              0.0,
              1.0,
            ),
            child: Transform.scale(
              scale: c < 0.15 ? 0.6 + 0.4 * (c / 0.15) : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: delta < 0
                      ? const Color(0xFFD6705F)
                      : AppColors.sageDark,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  delta < 0 ? '−${-delta}' : '+$delta',
                  style: sceneText(
                    size: 12.5,
                    weight: 900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, double? t) {
    // Монетка крутится ребром, пока кнопка «вздыхает».
    final spin = t == null ? 1.0 : math.cos(t * math.pi * 3).abs();
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
            width: 22 * math.max(spin, 0.15),
            height: 22,
            margin: EdgeInsets.symmetric(
              horizontal: 11 * (1 - math.max(spin, 0.15)),
            ),
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
            '${widget.coins}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

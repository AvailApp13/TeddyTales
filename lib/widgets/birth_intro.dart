import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../bear/bear.dart';
import '../game/game_state.dart';
import '../l10n/birth_l10n.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../l10n/size_l10n.dart';
import '../l10n/zodiac_l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

/// «Родился малыш!» — первый запуск, до выбора имени (КП 2.1, 2.2;
/// заказчик 26.09).
///
/// Сверху — видео рождения: мишка качается в кроватке. Под ним — карточка
/// рождения: пол и герой, дата, рост, вес, знак, первая черта характера.
/// Кнопка «Дать имя» ведёт к «Как зовут малыша?».
///
/// ⚠ ВИДЕО ЖДЁТ СОГЛАСОВАНИЯ С ИРИНОЙ (владелица, 26.09): сцена и
/// картинки для анимации сначала утверждаются, только потом — Higgsfield.
/// План, раскадровка и цена — `docs/birth-scene.md`. Пока видео нет, на
/// его месте заглушка «Видео рождения».
///
/// Когда ролик будет готов: положить `assets/video/birth_slow.mp4` и
/// `birth_joy.mp4`, прописать `assets/video/` в pubspec.yaml и заполнить
/// [birthVideos]. Проигрывание, субтитры по тактам [BirthSceneScript] и
/// «Пропустить» через 5 секунд уже здесь.
Future<void> showBirthIntro(
  BuildContext context, {
  required GameState game,
  required BearTrait trait,
}) => showGlassPanel<void>(
  context: context,
  center: const Offset(0.5, 0.5),
  width: 340,
  dismissible: false,
  builder: (context) => BirthIntro(game: game, trait: trait),
);

/// Ролики рождения по героям. Пусто, пока видео не согласовано с Ириной.
const Map<BearSkin, String> birthVideos = {};

class BirthIntro extends StatelessWidget {
  const BirthIntro({
    super.key,
    required this.game,
    required this.trait,
    this.video,
  });

  final GameState game;
  final BearTrait trait;

  /// Какой ролик играть; по умолчанию — из [birthVideos] по герою.
  final String? video;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = game.profile;
    final skin = profile.skin;
    final zodiac = profile.zodiac;
    final birthday = DateFormat.yMMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(profile.birthAt.toLocal());
    final facts = <(String, String)>[
      (
        l10n.birthIntroSex,
        '${skin == BearSkin.girl ? l10n.profileSexGirl : l10n.profileSexBoy}'
            ' · ${skin.heroName}',
      ),
      (l10n.profileBirthdayLabel, birthday),
      if (profile.birthHeightCm case final cm?)
        (
          l10n.profileHeightLabel,
          l10n.profileHeightValue(formatCm(context, cm)),
        ),
      if (profile.birthWeightG case final g?)
        (l10n.profileWeightLabel, l10n.profileWeightValue(formatG(g))),
      if (zodiac != null)
        (
          l10n.profileZodiacLabel,
          '${zodiac.symbol} ${zodiacTitle(l10n, zodiac)}',
        ),
      (l10n.birthIntroTrait, traitTitle(l10n, trait)),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BirthVideo(asset: video ?? birthVideos[skin]),
            const SizedBox(height: 12),
            Text(
              l10n.birthIntroTitle,
              key: const ValueKey('birth-intro-title'),
              textAlign: TextAlign.center,
              style: glassText(24, 900, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: glassTile(),
              child: Column(
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            facts[i].$1,
                            style: glassText(
                              13,
                              650,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              facts[i].$2,
                              textAlign: TextAlign.right,
                              style: glassText(
                                14,
                                800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i != facts.length - 1)
                      Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassButton(
              key: const ValueKey('birth-intro-name'),
              primary: true,
              icon: Icons.edit_rounded,
              label: l10n.birthIntroName,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Место под видео рождения. Ролика нет — заглушка «Видео рождения».
/// Есть — играет с субтитрами; «Пропустить» через 5 секунд (КП 2.1).
class _BirthVideo extends StatefulWidget {
  const _BirthVideo({this.asset});

  final String? asset;

  @override
  State<_BirthVideo> createState() => _BirthVideoState();
}

class _BirthVideoState extends State<_BirthVideo> {
  static const _script = BirthSceneScript();
  VideoPlayerController? _video;
  Duration _position = Duration.zero;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    if (asset == null) return;
    final video = VideoPlayerController.asset(asset);
    _video = video;
    unawaited(
      video
          .initialize()
          .then((_) {
            if (!mounted) return;
            video
              ..setVolume(0)
              ..play()
              ..addListener(_tick);
            setState(() {});
          })
          .catchError((Object _) {
            if (mounted) setState(() => _video = null);
          }),
    );
  }

  void _tick() {
    final video = _video;
    if (video == null || !mounted) return;
    setState(() => _position = video.value.position);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final video = _video;
    final ready = video != null && video.value.isInitialized;
    final cue = ready && !_skipped ? _script.cueAt(_position) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              )
            else
              const _VideoPlaceholder(),
            if (cue != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text(
                  birthCueText(l10n, cue.id),
                  textAlign: TextAlign.center,
                  style: glassText(14, 800).copyWith(
                    shadows: const [
                      Shadow(color: Color(0xAA000000), blurRadius: 6),
                    ],
                  ),
                ),
              ),
            if (ready &&
                !_skipped &&
                _script.canSkipAt(_position) &&
                !_script.isFinishedAt(_position))
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    video.seekTo(video.value.duration);
                    setState(() => _skipped = true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(l10n.birthSkip, style: glassText(12, 800)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Заглушка на месте видео: ночная кроватка словами, пока ролик не готов.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      key: const ValueKey('birth-video-placeholder'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3E4A78), Color(0xFF8C86C0)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.nightlight_round,
            size: 40,
            color: Color(0xFFFFE9B0),
          ),
          const SizedBox(height: 8),
          Text(l10n.birthIntroVideo, style: glassText(18, 900)),
          const SizedBox(height: 2),
          Text(
            l10n.birthIntroVideoSoon,
            style: glassText(
              12.5,
              650,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

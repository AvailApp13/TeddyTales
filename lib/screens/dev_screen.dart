import 'package:flutter/material.dart';

import '../bear/bear.dart';

/// Дев-панель для рига мишки.
///
/// Это не продуктовый экран: комнаты, магазина и прочего из КП здесь нет.
/// Экран нужен, чтобы вживую крутить входы State Machine и проверять, что риг
/// на них отзывается, — аналог демо-страницы из пункта 10.7 ТЗ аниматора,
/// только внутри приложения.
class BearDevScreen extends StatefulWidget {
  const BearDevScreen({super.key, required this.controller});

  /// Контроллер приходит снаружи: панель крутит того же мишку, что и главный
  /// экран, иначе смотреть на неё бессмысленно.
  final BearController controller;

  @override
  State<BearDevScreen> createState() => _BearDevScreenState();
}

class _BearDevScreenState extends State<BearDevScreen> {
  BearController get _bear => widget.controller;
  BearLanguage _language = BearLanguage.ru;

  void _openBirthScene() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BirthSceneView(
          language: _language,
          onFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TeddyTales — риг мишки'),
        actions: [
          IconButton(
            tooltip: 'Сцена рождения',
            onPressed: _openBirthScene,
            icon: const Icon(Icons.nights_stay_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                Positioned.fill(child: BearView(controller: _bear)),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: AnimatedBuilder(
                    animation: _bear,
                    builder: (context, _) => _SpeechBubble(
                      controller: _bear,
                      language: _language,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 4,
            child: AnimatedBuilder(
              animation: _bear,
              builder: (context, _) => _DevPanel(
                controller: _bear,
                language: _language,
                onLanguageChanged: (value) =>
                    setState(() => _language = value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Пузырь инициативы и реплика питомца (КП 3.4, 13.3).
///
/// В дев-панели реплика берётся первой из контекста, чтобы не мигала на каждой
/// перерисовке. В приложении её нужно выбирать случайно и держать до смены
/// контекста.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.controller, required this.language});

  final BearController controller;
  final BearLanguage language;

  @override
  Widget build(BuildContext context) {
    final initiative = controller.initiative;
    final context0 = switch (initiative?.action) {
      BearAction.play => BearPhraseContext.invitePlay,
      BearAction.learn => BearPhraseContext.inviteLearn,
      BearAction.feed => BearPhraseContext.hungry,
      BearAction.sleep => BearPhraseContext.sleepy,
      BearAction.wash => BearPhraseContext.dirty,
      BearAction.pet => BearPhraseContext.sad,
      _ => BearPhrases.contextForMood(controller.state.mood),
    };

    final phrase = BearPhrases.forContext(context0).first;
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(phrase.text(language), style: theme.textTheme.bodyMedium),
            if (initiative != null)
              Text(
                'инициатива: ${initiative.action.name} '
                '(${initiative.reason.name}), '
                'раз в ${controller.initiativeCooldown.inMinutes} мин',
                style: theme.textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Панель отладки: показатели ухода, входы State Machine и триггеры.
class _DevPanel extends StatelessWidget {
  const _DevPanel({
    required this.controller,
    required this.language,
    required this.onLanguageChanged,
  });

  final BearController controller;
  final BearLanguage language;
  final ValueChanged<BearLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final stats = state.stats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Text('Язык'),
            const SizedBox(width: 12),
            SegmentedButton<BearLanguage>(
              segments: const [
                ButtonSegment(value: BearLanguage.ru, label: Text('RU')),
                ButtonSegment(value: BearLanguage.en, label: Text('EN')),
                ButtonSegment(value: BearLanguage.zh, label: Text('中文')),
              ],
              selected: {language},
              onSelectionChanged: (s) => onLanguageChanged(s.first),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _SectionTitle('Показатели ухода → вход mood: ${state.mood.name}'),
        _StatSlider(
          label: 'Еда',
          value: stats.food,
          onChanged: (v) => controller.setStats(stats.copyWith(food: v)),
        ),
        _StatSlider(
          label: 'Гигиена',
          value: stats.hygiene,
          onChanged: (v) => controller.setStats(stats.copyWith(hygiene: v)),
        ),
        _StatSlider(
          label: 'Сон',
          value: stats.sleep,
          onChanged: (v) => controller.setStats(stats.copyWith(sleep: v)),
        ),
        _StatSlider(
          label: 'Игра',
          value: stats.play,
          onChanged: (v) => controller.setStats(stats.copyWith(play: v)),
        ),
        _StatSlider(
          label: 'Любовь',
          value: stats.love,
          onChanged: (v) => controller.setStats(stats.copyWith(love: v)),
        ),

        const SizedBox(height: 16),
        _SectionTitle('Действия ухода'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () => controller.feedBear(),
              child: const Text('Покормить'),
            ),
            FilledButton.tonal(
              onPressed: () => controller.washBear(),
              child: const Text('Умыть'),
            ),
            FilledButton.tonal(
              onPressed: () => controller.putToSleep(),
              child: const Text('Спать'),
            ),
            FilledButton.tonal(
              onPressed: controller.wakeBear,
              child: const Text('Разбудить'),
            ),
            FilledButton.tonal(
              onPressed: () => controller.playWithBear(),
              child: const Text('Играть'),
            ),
            FilledButton.tonal(
              onPressed: () => controller.petBear(),
              child: const Text('Погладить'),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionTitle('Эмоции'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: controller.showHappy,
              child: const Text('Радость'),
            ),
            OutlinedButton(
              onPressed: controller.showSad,
              child: const Text('Огорчение'),
            ),
            OutlinedButton(
              onPressed: controller.showSurprise,
              child: const Text('Удивление'),
            ),
            OutlinedButton(
              onPressed: controller.showLove,
              child: const Text('Любовь'),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionTitle('Стадия (${state.stage.riveValue}/5)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final stage in BearStage.values)
              ChoiceChip(
                label: Text(stage.title),
                selected: state.stage == stage,
                onSelected: (_) => controller.setStage(stage),
              ),
            FilledButton.icon(
              onPressed: controller.growUp,
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Взросление'),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionTitle(
          'Характер — накоплено действий: '
          '${controller.traitTracker.history.length}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final trait in BearTrait.values)
              ChoiceChip(
                label: Text(trait.title),
                selected: state.trait == trait,
                onSelected: (_) => controller.setTrait(trait),
              ),
          ],
        ),

        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Пол'),
            const SizedBox(width: 12),
            SegmentedButton<BearSkin>(
              segments: const [
                ButtonSegment(value: BearSkin.boy, label: Text('Мальчик')),
                ButtonSegment(value: BearSkin.girl, label: Text('Девочка')),
              ],
              selected: {state.skin},
              onSelectionChanged: (s) => controller.setSkin(s.first),
            ),
            const Spacer(),
            const Text('Ходьба'),
            Switch(
              value: state.isWalking,
              onChanged: state.canWalk ? controller.setWalking : null,
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionTitle('Одежда'),
        _SlotStepper(
          label: 'Комплект',
          value: state.outfit.outfitId,
          max: BearOutfit.maxOutfitId,
          onChanged: (v) =>
              controller.setOutfit(state.outfit.copyWith(outfitId: v)),
        ),
        _SlotStepper(
          label: 'Головной убор',
          value: state.outfit.headwearId,
          max: BearOutfit.maxHeadwearId,
          onChanged: (v) =>
              controller.setOutfit(state.outfit.copyWith(headwearId: v)),
        ),
        _SlotStepper(
          label: 'Обувь',
          value: state.outfit.shoesId,
          max: BearOutfit.maxShoesId,
          onChanged: (v) =>
              controller.setOutfit(state.outfit.copyWith(shoesId: v)),
        ),
        _SlotStepper(
          label: 'Аксессуар',
          value: state.outfit.accessoryId,
          max: BearOutfit.maxAccessoryId,
          onChanged: (v) =>
              controller.setOutfit(state.outfit.copyWith(accessoryId: v)),
        ),

        const SizedBox(height: 16),
        Text(
          controller.isRigAttached
              ? 'Риг подключён'
              : 'Риг не подключён — команды никуда не уходят',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _StatSlider extends StatelessWidget {
  const _StatSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: BearCareStats.min,
            max: BearCareStats.max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value.toStringAsFixed(0), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _SlotStepper extends StatelessWidget {
  const _SlotStepper({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 140, child: Text(label)),
        IconButton(
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 48,
          child: Text('$value / $max', textAlign: TextAlign.center),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

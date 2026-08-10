import 'package:flutter/material.dart';
import 'package:rive/rive.dart' show RiveNative;

import 'bear/bear.dart';

/// Дев-харнесс для рига мишки.
///
/// Это не экран продуктового приложения: тут нет комнаты, магазина, дневника и
/// прочей бизнес-логики — она вне границ этого ТЗ (раздел 0, пункт 9.5).
/// Экран нужен, чтобы вживую крутить `hunger`/`mood`/`growthStage` и проверять,
/// как на них реагирует State Machine.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Обязательно для rive >= 0.14: инициализация нативного рантайма до runApp.
  await RiveNative.init();

  runApp(const TeddyTalesDevApp());
}

class TeddyTalesDevApp extends StatelessWidget {
  const TeddyTalesDevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeddyTales — риг мишки',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFB07B4F),
        brightness: Brightness.light,
      ),
      home: const BearDevScreen(),
    );
  }
}

class BearDevScreen extends StatefulWidget {
  const BearDevScreen({super.key});

  @override
  State<BearDevScreen> createState() => _BearDevScreenState();
}

class _BearDevScreenState extends State<BearDevScreen> {
  late final BearController _bear = BearController()..startDecay();

  @override
  void dispose() {
    _bear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TeddyTales — риг мишки')),
      body: Column(
        children: [
          Expanded(child: BearView(controller: _bear)),
          const Divider(height: 1),
          AnimatedBuilder(
            animation: _bear,
            builder: (context, _) => _DevPanel(controller: _bear),
          ),
        ],
      ),
    );
  }
}

/// Панель отладки: слайдеры характеристик и кнопки событий.
class _DevPanel extends StatelessWidget {
  const _DevPanel({required this.controller});

  final BearController controller;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatSlider(
            label: 'hunger',
            value: stats.hunger,
            onChanged: controller.setHunger,
          ),
          _StatSlider(
            label: 'mood',
            value: stats.mood,
            onChanged: controller.setMood,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('growthStage'),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<BearGrowthStage>(
                  segments: [
                    for (final stage in BearGrowthStage.values)
                      ButtonSegment(value: stage, label: Text(stage.name)),
                  ],
                  selected: {stats.growthStage},
                  onSelectionChanged: (selection) =>
                      controller.setGrowthStage(selection.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => controller.feedBear(),
                icon: const Icon(Icons.restaurant),
                label: const Text('Покормить'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => controller.petBear(),
                icon: const Icon(Icons.volunteer_activism),
                label: const Text('Погладить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            controller.isRigAttached
                ? 'Риг подключён'
                : 'Риг не подключён — значения никуда не уходят',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: BearStats.min,
            max: BearStats.max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(0),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

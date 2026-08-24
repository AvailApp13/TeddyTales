import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' show RiveNative;

import 'package:flutter_localizations/flutter_localizations.dart';

import 'bear/bear.dart';
import 'game/game_calendar.dart';
import 'game/game_state.dart';
import 'game/pet_profile.dart';
import 'l10n/l10n.dart';
import 'screens/dev_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Обязательно для rive >= 0.14: инициализация нативного рантайма до runApp.
  //
  // Обёрнуто в таймаут намеренно. В вебе рантайм подтягивает wasm с CDN
  // (jsdelivr), и если сети нет, `init()` не падает, а просто не завершается —
  // без таймаута `runApp` не вызовется вообще и пользователь увидит белый
  // экран. КП 1.1 требует обратного: при отсутствии сети приложение работает
  // офлайн. Не поднялся рантайм — мишка покажет плейсхолдер, остальное живо.
  try {
    await RiveNative.init().timeout(const Duration(seconds: 5));
  } on Object catch (error) {
    debugPrint('[TeddyTales] Rive runtime не инициализировался: $error');
  }

  runApp(const TeddyTalesApp());
}

class TeddyTalesApp extends StatefulWidget {
  const TeddyTalesApp({super.key});

  @override
  State<TeddyTalesApp> createState() => _TeddyTalesAppState();
}

class _TeddyTalesAppState extends State<TeddyTalesApp> {
  static const GameCalendar _calendar = GameCalendar();

  late final BearController _bear = BearController(
    initialState: const BearState(
      stage: BearStage.growing,
      stats: BearCareStats(
        food: 60,
        hygiene: 80,
        sleep: 70,
        play: 90,
        love: 100,
      ),
    ),
  )..startDecay();

  /// Демонстрационная карточка питомца.
  ///
  /// Значения повторяют шапку макета: имя «Мой малыш», возраст «3 месяца
  /// 12 дней», 1250 монет. В бою профиль приезжает с сервера вместе с
  /// прогрессом (КП 1.4, 2.2).
  late final GameState _game = GameState(bear: _bear, profile: _profile);

  BearLanguage _language = BearLanguage.ru;

  late final PetProfile _profile = PetProfile(
    name: 'Мой малыш',
    birthAt: DateTime.now().subtract(
      _calendar.realTimePerGameMonth * 3 + _calendar.realTimePerGameDay * 12,
    ),
    skin: BearSkin.boy,
    coins: 1250,
  );

  @override
  void dispose() {
    _game.dispose();
    _bear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeddyTales',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Язык один на всё приложение: реплики питомца и интерфейс
      // переключаются одним значением из настроек (КП 16.1: ru/en/zh).
      locale: _language.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(
        controller: _bear,
        game: _game,
        calendar: _calendar,
        language: _language,
        onLanguageChanged: (value) => setState(() => _language = value),
        // ВРЕМЕННО: настоящего рига ещё нет, поэтому показываем сторонний
        // демонстрационный файл — он подтверждает, что пайплайн загрузки,
        // выбора State Machine и рендера работает. Убрать, как только придёт
        // bear_main.riv.
        riveAssetPath: BearRigSpec.demoAssetPath,
        // Дев-панель со всеми входами State Machine — только в отладке.
        onOpenDevPanel: kDebugMode
            ? (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BearDevScreen(controller: _bear),
                ),
              )
            : null,
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' show RiveNative;

import 'package:flutter_localizations/flutter_localizations.dart';

import 'backend/bootstrap.dart';
import 'bear/bear.dart';
import 'game/game_calendar.dart';
import 'game/game_state.dart';
import 'game/pet_profile.dart';
import 'l10n/l10n.dart';
import 'screens/dev_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
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

  // Прогресс поднимается до первого кадра: показать демонстрационные
  // значения, а через секунду подменить их настоящими — значит мигнуть
  // пользователю чужими цифрами. Не вышло достучаться до сервера — идём
  // офлайн (КП 1.1), приложение открывается в любом случае.
  final boot = await Bootstrap.start();

  runApp(TeddyTalesApp(boot: boot));
}

class TeddyTalesApp extends StatefulWidget {
  const TeddyTalesApp({super.key, required this.boot});

  /// С чем запустились: хранилище прогресса и состояние на момент старта.
  final BootResult boot;

  @override
  State<TeddyTalesApp> createState() => _TeddyTalesAppState();
}

class _TeddyTalesAppState extends State<TeddyTalesApp> {
  static const GameCalendar _calendar = GameCalendar();

  /// Локальное затухание работает и при живом сервере — но только ради
  /// плавности: между действиями показатели должны сползать на глазах, а не
  /// прыгать раз в запрос. Истина всё равно приходит с сервера, который
  /// пересчитывает их по своим часам (КП 1.5) и присылает при каждом
  /// действии.
  late final BearController _bear = BearController(
    initialState: widget.boot.isOnline
        ? widget.boot.snapshot.state
        : const BearState(
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

  late final GameState _game = GameState(
    bear: _bear,
    profile: _profile,
    // Пустые наборы означают, что сервера не было: тогда GameState сам
    // выдаст стартовый набор из двенадцати предметов (КП 10.8).
    owned: widget.boot.snapshot.inventory.isEmpty
        ? null
        : widget.boot.snapshot.inventory,
    placed: widget.boot.snapshot.placed.isEmpty
        ? null
        : widget.boot.snapshot.placed,
  );

  BearLanguage _language = BearLanguage.ru;

  /// Прошёл ли пользователь экран входа.
  ///
  /// Настоящей сессии за этим пока нет: ни один способ входа не подключён,
  /// и любая кнопка просто пускает внутрь. Флаг живёт в памяти намеренно —
  /// когда появится Supabase, его место займёт состояние сессии, и менять
  /// придётся одну строку, а не разметку экранов.
  bool _signedIn = false;

  /// Карточка питомца. С сервера, если он ответил; иначе — прежние
  /// демонстрационные значения из макета, чтобы офлайн не выглядел пустым
  /// экраном.
  late final PetProfile _profile = widget.boot.isOnline
      ? widget.boot.snapshot.profile
      : PetProfile(
          name: PetProfile.defaultName,
          birthAt: DateTime.now().subtract(
            _calendar.realTimePerGameMonth * 3 +
                _calendar.realTimePerGameDay * 12,
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
      home: _signedIn
          ? _home()
          : SignInScreen(onSignedIn: () => setState(() => _signedIn = true)),
    );
  }

  Widget _home() {
    return HomeScreen(
      controller: _bear,
      game: _game,
      calendar: _calendar,
      language: _language,
      onLanguageChanged: (value) => setState(() => _language = value),
      // ВРЕМЕННО: настоящего рига ещё нет, поэтому показываем сторонний
      // демонстрационный файл — он подтверждает, что пайплайн загрузки,
      // выбора State Machine и рендера работает. Убрать, как только придёт
      // bear_main.riv.
      riveAssetPath: BearRigSpec.assetPath,
      // Дев-панель со всеми входами State Machine — только в отладке.
      onOpenDevPanel: kDebugMode
          ? (context) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BearDevScreen(controller: _bear),
              ),
            )
          : null,
    );
  }
}

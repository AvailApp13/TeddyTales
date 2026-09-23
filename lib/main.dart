import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:rive/rive.dart' show RiveNative;

import 'package:flutter_localizations/flutter_localizations.dart';

import 'backend/bootstrap.dart';
import 'backend/progress_sync.dart';
import 'bear/bear.dart';
import 'game/game_calendar.dart';
import 'game/game_state.dart';
import 'game/pet_name.dart';
import 'game/pet_profile.dart';
import 'l10n/l10n.dart';
import 'notifications/notification_service.dart';
import 'game/test_stubs.dart';
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

  // Напоминания не обязательны для игры: не поднялись — она работает молча.
  final notifications = await NotificationService.create();

  // Замедленная съёмка для проверки плавности по кадрам: сборка с
  // --dart-define=SLOW_MOTION=8 идёт в восемь раз медленнее, и моргание в
  // 90 мс раскладывается на кадры. В обычной сборке множитель 1.
  timeDilation = kSlowMotion;
  runApp(TeddyTalesApp(boot: boot, notifications: notifications));
}

class TeddyTalesApp extends StatefulWidget {
  const TeddyTalesApp({super.key, required this.boot, this.notifications});

  /// С чем запустились: хранилище прогресса и состояние на момент старта.
  final BootResult boot;

  /// Напоминания об уходе. `null` — механизм не поднялся.
  final NotificationService? notifications;

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
    // Заглушка на испытания: еда закреплена, см. `lib/game/test_stubs.dart`.
    pinnedFood: kTestFood,
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

  /// Мост к серверу: отправляет действия и применяет ответы (КП 1.4).
  ///
  /// Создаётся после мишки и состояния игры, потому что подписывается на
  /// оба. Работает и в офлайне: там хранилище в памяти, действия копятся в
  /// очереди и уходят, когда связь вернётся.
  late final ProgressSync _sync = ProgressSync(
    store: widget.boot.store,
    bear: _bear,
    game: _game,
    onSnapshot: (snapshot) => widget.boot.cache?.save(snapshot),
  );

  BearLanguage _language = BearLanguage.ru;

  /// Прошёл ли пользователь экран входа.
  ///
  /// Настоящей сессии за этим пока нет: ни один способ входа не подключён,
  /// и любая кнопка просто пускает внутрь. Флаг живёт в памяти намеренно —
  /// когда появится Supabase, его место займёт состояние сессии, и менять
  /// придётся одну строку, а не разметку экранов.
  bool _signedIn = !kShowSignIn;

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

  /// Наблюдатель хранится полем, а не создаётся на лету: снять его можно
  /// только по той же ссылке, а неснятый переживёт экран и продолжит
  /// дёргать уничтоженный мост.
  late final _Lifecycle _lifecycle = _Lifecycle(
    onPaused: _planReminders,
    onResumed: () {
      _sync.retry();
      // Игрок открыл приложение — напоминания ему больше не нужны, он уже
      // здесь. Оставить их значит показать «малыш проголодался» человеку,
      // который в эту секунду его кормит.
      widget.notifications?.cancelAll();
    },
  );

  /// Строит расписание напоминаний от текущих показателей (КП 13.1).
  ///
  /// Момент выбран — уход в фон. Планировать на каждое действие значит
  /// перестраивать расписание десятки раз за сессию впустую: пока
  /// приложение открыто, напоминания всё равно не показываются.
  void _planReminders() {
    final service = widget.notifications;
    if (service == null) return;

    service.enabled = {
      for (final kind in NotificationKind.values)
        if (_game.isNotificationOn(kind.id)) kind.id,
    };
    service.reschedule(
      stats: _bear.stats,
      decay: _bear.decay,
      language: _language,
    );
  }

  @override
  void initState() {
    super.initState();
    // Обращение к полю поднимает `late final` и включает подписку на
    // действия. Без этой строки мост создался бы только при первом
    // обращении из разметки, то есть никогда.
    _sync.retry();
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    _sync.dispose();
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

  /// Выход из аккаунта (КП 14.2).
  ///
  /// Пока за флагом нет настоящей сессии, выход — это возврат на экран
  /// входа. Когда появится Supabase, сюда добавится `signOut()` хранилища, а
  /// разметка экранов не изменится: они знают только про обратный вызов.
  ///
  /// Напоминания снимаем обязательно. Они запланированы на часы вперёд и
  /// говорят от лица питомца — «малыш проголодался» человеку, который из
  /// аккаунта вышел, выглядит как чужое уведомление на своём телефоне.
  void _signOut() {
    widget.notifications?.cancelAll();
    setState(() => _signedIn = false);
  }

  /// Переименовать питомца. `null` — сервер имя принял.
  ///
  /// Текст ошибки от сервера человеку не показываем: он на языке базы и
  /// говорит про `check_violation`. Здесь только разбираем, отказали нам
  /// из-за имени или не достучались вовсе, — переводит экран.
  Future<PetNameError?> _rename(String name) async {
    final error = await _sync.rename(name);
    if (error == null) return null;

    return error.contains('check_violation') || error.contains('запрещ')
        ? PetNameError.rejected
        : PetNameError.network;
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
      onSignOut: _signOut,
      // Переименование идёт через мост: имя проверяет сервер (КП 2.3), он
      // же возвращает снимок с новым именем, и оно доезжает до всех
      // экранов разом.
      onRename: _rename,
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

/// Две точки, где приложение переключается между «на экране» и «в кармане».
///
/// Уход в фон — момент, когда имеет смысл строить расписание напоминаний:
/// показатели актуальны, а показывать уведомления станет кому.
///
/// Возвращение — момент, когда стоит дослать накопленное: телефон,
/// пролежавший без связи, почти всегда находит её в первые секунды после
/// разблокировки. Без этого очередь ждала бы следующего действия игрока, а
/// он мог бы и не прийти.
class _Lifecycle extends WidgetsBindingObserver {
  _Lifecycle({required this.onPaused, required this.onResumed});

  final VoidCallback onPaused;
  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        onPaused();
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

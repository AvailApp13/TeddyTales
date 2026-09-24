import Flutter
import UIKit

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WakeAlarmPlugin") {
      WakeAlarmPlugin.register(with: registrar)
    }
  }
}

/// Будильник «проснёмся вместе» на iPhone.
///
/// С iOS 26 — настоящий системный будильник через AlarmKit: звонит в
/// беззвучном режиме и в режиме фокусирования, на заблокированном экране
/// показывается во весь экран. Apple не даёт приложениям писать в «Часы»,
/// но будильник AlarmKit ведёт себя так же.
///
/// До iOS 26 AlarmKit нет: канал отвечает "unavailable", и Dart ставит
/// запасное уведомление со звуком.
///
/// Канал `teddytales/wake_alarm`, тот же, что на Android:
///  - `set` {hour, minute, label, stop} → "alarmKit" | "unavailable" | "denied" | "failed";
///  - `cancel` → снять поставленный будильник;
///  - `openClock` → false (на iPhone будильник живёт не в «Часах»).
final class WakeAlarmPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "teddytales/wake_alarm",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(WakeAlarmPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "set":
      guard
        let args = call.arguments as? [String: Any],
        let hour = args["hour"] as? Int,
        let minute = args["minute"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "hour и minute обязательны", details: nil))
        return
      }
      let label = args["label"] as? String ?? "Teddy Tales"
      let stopLabel = args["stop"] as? String ?? "OK"
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task { @MainActor in
          let outcome = await WakeAlarmKit.set(
            hour: hour, minute: minute, label: label, stopLabel: stopLabel)
          result(outcome)
        }
        return
      }
      #endif
      result("unavailable")

    case "cancel":
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        WakeAlarmKit.cancel()
      }
      #endif
      result(nil)

    case "openClock":
      result(false)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

#if canImport(AlarmKit)
/// Метаданные будильника: AlarmKit требует тип, даже пустой.
@available(iOS 26.0, *)
struct TeddyAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
enum WakeAlarmKit {
  /// Где лежит номер поставленного будильника: новый заменяет старый, а не
  /// добавляется вторым.
  static let storageKey = "teddytales.wakeAlarmId"

  @MainActor
  static func set(hour: Int, minute: Int, label: String, stopLabel: String) async -> String {
    let manager = AlarmManager.shared
    do {
      var state = manager.authorizationState
      if state == .notDetermined {
        state = try await manager.requestAuthorization()
      }
      guard state == .authorized else { return "denied" }

      cancel()

      let stop = AlarmButton(
        text: LocalizedStringResource(stringLiteral: stopLabel),
        textColor: .white,
        systemImageName: "stop.circle"
      )
      // Инициализатор со своей кнопкой «стоп» в новых SDK помечен
      // устаревшим (там кнопку рисует система), но есть во всех версиях
      // iOS 26 — поэтому берём его: сборка не зависит от точной версии Xcode.
      let alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: label),
        stopButton: stop,
        secondaryButton: nil,
        secondaryButtonBehavior: nil
      )
      let attributes = AlarmAttributes<TeddyAlarmMetadata>(
        presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
        metadata: TeddyAlarmMetadata(),
        // Шалфей интерфейса TeddyTales (AppColors.sage, #90BF90).
        tintColor: Color(red: 0.565, green: 0.749, blue: 0.565)
      )
      let schedule = Alarm.Schedule.relative(
        Alarm.Schedule.Relative(
          time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
          repeats: .never
        )
      )
      let configuration = AlarmManager.AlarmConfiguration<TeddyAlarmMetadata>.alarm(
        schedule: schedule,
        attributes: attributes,
        stopIntent: nil,
        secondaryIntent: nil,
        sound: .default
      )
      let id = UUID()
      _ = try await manager.schedule(id: id, configuration: configuration)
      UserDefaults.standard.set(id.uuidString, forKey: storageKey)
      return "alarmKit"
    } catch {
      return "failed"
    }
  }

  static func cancel() {
    guard
      let raw = UserDefaults.standard.string(forKey: storageKey),
      let id = UUID(uuidString: raw)
    else { return }
    try? AlarmManager.shared.cancel(id: id)
    UserDefaults.standard.removeObject(forKey: storageKey)
  }
}
#endif

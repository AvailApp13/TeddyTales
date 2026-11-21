package com.teddytales.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Будильник «проснёмся вместе» на Android — в системных «Часах».
 *
 * Приложение не звонит само: время уходит в «Часы» телефона стандартной
 * командой SET_ALARM, и будит уже системный будильник — громко, в любом
 * режиме звука, со своими «Отложить» и «Выключить». Отдельного разрешения
 * у пользователя это не спрашивает (SET_ALARM — обычное разрешение из
 * манифеста).
 *
 * Канал `teddytales/wake_alarm`, тот же, что на iPhone:
 *  - `set` {hour, minute, label} → "clock" — поставлен в «Часах»;
 *    "unavailable" — на телефоне нет приложения часов, которое принимает
 *    команду, Dart ставит запасное уведомление;
 *  - `openClock` → открыть список будильников в «Часах»;
 *  - `cancel` → ничего: убрать будильник из чужих «Часов» без участия
 *    человека Android не даёт.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        val hour = call.argument<Int>("hour")
                        val minute = call.argument<Int>("minute")
                        val label = call.argument<String>("label") ?: "Teddy Tales"
                        if (hour == null || minute == null) {
                            result.error("bad_args", "hour и minute обязательны", null)
                        } else {
                            result.success(setAlarm(hour, minute, label))
                        }
                    }
                    "openClock" -> result.success(openClock())
                    "cancel" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    /** Ставит будильник в «Часах» без открытия их экрана. */
    private fun setAlarm(hour: Int, minute: Int, label: String): String {
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            putExtra(AlarmClock.EXTRA_MESSAGE, label)
            putExtra(AlarmClock.EXTRA_VIBRATE, true)
            // Без экрана «Часов»: будильник сохраняется сразу, человек
            // остаётся в приложении и видит подтверждение от мишки.
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        }
        if (intent.resolveActivity(packageManager) == null) return "unavailable"
        return try {
            startActivity(intent)
            "clock"
        } catch (error: ActivityNotFoundException) {
            "unavailable"
        } catch (error: SecurityException) {
            "unavailable"
        }
    }

    /** Открывает список будильников в «Часах», чтобы человек увидел свой. */
    private fun openClock(): Boolean {
        val intent = Intent(ACTION_SHOW_ALARMS)
        if (intent.resolveActivity(packageManager) == null) return false
        return try {
            startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            false
        }
    }

    private companion object {
        const val CHANNEL = "teddytales/wake_alarm"

        // AlarmClock.ACTION_SHOW_ALARMS (API 19) строкой: так же, как её
        // объявляет сам Android.
        const val ACTION_SHOW_ALARMS = "android.intent.action.SHOW_ALARMS"
    }
}

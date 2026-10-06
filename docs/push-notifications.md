# Push-уведомления с сервера (КП 13.1)

Шесть типов из восьми телефон считает сам (`lib/notifications`):
голоден, играть, спать, задание, подарок, новая стадия. «Событие» и
«Новинки магазина» знает только сервер — для них push.

## Как устроено

- **iPhone** получает токен APNs (`PushTokenPlugin` в
  `ios/Runner/AppDelegate.swift`, канал `teddytales/push`) и отдаёт его
  серверу вместе с языком и включёнными типами
  (`PushRegistration`, `SupabaseStore.registerPushToken` →
  `register_push_token`, таблица `push_tokens`, миграция 0028).
  Обновляется при запуске, после разрешения и при уходе в фон.
- **Право push** у `com.teddytales.app` включает Codemagic (шаг «Вход через
  Apple и push в портале»), в `Runner.entitlements` —
  `aps-environment = production` (TestFlight и App Store).
- **Отправка** — Edge Function `send-push` (только администратор), напрямую
  в Apple по HTTP/2. Ключ APNs — в Vault Supabase: `apns_key_p8`,
  `apns_key_id`, `apns_team_id`; читает только `public.apns_config()` под
  service_role. История — `push_log`.
- **Панель** → «Отправить уведомление»: тип, тексты на трёх языках,
  «Сколько получат» и «Отправить».

## ⚠ Ждёт

1. **Ключ APNs** — создаётся только вручную: developer.apple.com →
   Certificates, Identifiers & Profiles → **Keys** → «+» → галочка **Apple
   Push Notifications service (APNs)** → Continue → Register → Download.
   Нужны файл `.p8`, его Key ID и Team ID (Membership details). Ключ App
   Store Connect API (Users and Access → Integrations) для push **не
   подходит**.
   Положить в Vault (SQL Editor Supabase):
   `select vault.create_secret('<.p8 целиком>', 'apns_key_p8');`
   `select vault.create_secret('<Key ID>', 'apns_key_id');`
   `select vault.create_secret('<Team ID>', 'apns_team_id');`
2. **Android** — FCM после проекта Firebase. В материковом Китае без
   сервисов Google серверные push на Android не дойдут — нужны службы
   производителей (Huawei, Xiaomi), отдельная работа.
3. Панель на сайте (gh-pages) обновляется отдельно — с разрешения
   заказчика.

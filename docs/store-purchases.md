# Покупки в App Store и Google Play (КП 11.3)

> **⚠ Ждёт согласования и настройки.** Код готов 26.09 (заказчик: «подготовить
> в коде сейчас»). Пока список товаров на сервере пуст, в приложении за
> деньги ничего не продаётся и «Восстановить покупки» не показывается.

## Что уже сделано

- **Сервер** (миграция 0026, применена):
  - `store_products()` — что продаётся;
  - `grant_store_purchase(...)` — выдача после проверки чека (один чек —
    одна выдача, повтор и восстановление не удваивают);
  - `refund_store_purchase(...)` — возврат денег забирает предмет.

  Проверено на сервере с откатом: +500 монет, повтор того же чека +0,
  предмет выдан и после возврата забран.
- **Функция `verify-purchase`** (развёрнута): проверяет чек у Apple (App
  Store Server API) или Google (Play Developer API, заодно подтверждает
  покупку) и вызывает выдачу. Без ключей отвечает 503 `not_configured`.
- **Приложение** (`lib/backend/store_purchases.dart`): покупка → чек на
  сервер → выдано → только тогда покупка закрывается. Сервер не ответил —
  покупка остаётся открытой, магазин пришлёт её снова. «Восстановить
  покупки» — в Настройках → Аккаунт.

## Что нужно, чтобы включить

1. **Решение Ирины / заказчика (КП 10.8, 10.9):** какие 12 предметов
   премиальные и цена каждого. Возможно, ещё наборы монет.
2. **App Store Connect** → приложение → Monetization → In-App Purchases:
   завести товары (Non-Consumable — предмет, Consumable — монеты),
   product_id вида `premium.<item_id>`, цены, описания на 3 языках.
   Там же подписать Paid Apps Agreement (Business).
3. **Google Play Console** → Monetize → In-app products: те же product_id.
4. **Ключи для `verify-purchase`** (Supabase → Edge Functions → Secrets):
   - `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, `APPSTORE_PRIVATE_KEY`:
     App Store Connect → Users and Access → Integrations → In-App
     Purchase, ключ .p8;
   - `APPSTORE_BUNDLE_ID` = `com.teddytales.app`;
   - `GOOGLE_SERVICE_ACCOUNT`: JSON сервисного аккаунта с доступом к
     Play Console, «Просмотр финансов» и «Управление заказами»;
   - `GOOGLE_PACKAGE_NAME`.
5. **Список товаров на сервер:** панель → Экономика → `store_products`:

   ```json
   {"products": {"premium.sofa_royal": {"item": "sofa_royal"},
                 "coins.500": {"coins": 500}}}
   ```

6. **Магазин в приложении:** кнопка «Купить за 199 ₽» у премиальных
   предметов. ⚠ Это правка «вещей» — делаю только по команде, когда будет
   список из п. 1.

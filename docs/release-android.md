# Android: бета во внутреннем канале Google Play (КП 17.2)

> **⚠ Ждёт доступа к Google Play Console.** Сценарий
> `android-play-internal` в `codemagic.yaml` готов 26.09. Без трёх шагов ниже
> он упадёт на подписи или на публикации. Прежний сценарий «Android → APK»
> не изменился и работает как раньше.

## Один раз

1. **Google Play Console** (аккаунт разработчика, $25):
   - создать приложение, пакет `com.teddytales.app`;
   - заполнить «Контент приложения»: политика конфиденциальности (ссылка),
     возрастной рейтинг, целевая аудитория (дети → раздел «Для всей
     семьи»), безопасность данных;
   - «Тестирование → Внутреннее тестирование» — список почт тестировщиков.
2. **Ключ загрузки.** Создать один раз:

   ```
   keytool -genkey -v -keystore teddytales_upload.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias upload
   ```

   В Codemagic → Teams → Code signing identities → Android keystores
   загрузить его под именем `teddytales_upload`. Файл и пароли хранить:
   потерять ключ — значит просить Google о сбросе.
3. **Первый AAB — вручную** (так требует Google для нового приложения):
   запустить сценарий один раз, скачать `.aab` из Artifacts и загрузить в
   «Внутреннее тестирование». Дальше Codemagic публикует сам.
4. **Сервисный аккаунт** для публикации: Google Cloud → IAM → Service
   accounts → ключ JSON. В Play Console → Пользователи и разрешения —
   пригласить его почту с правом «Выпуски». В Codemagic — группа
   переменных `google_play`, переменная `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`
   = содержимое JSON (секретная).

## Каждая сборка

Codemagic → «Android → Google Play (внутренний)» → Start. Тесты →
номер сборки = последний в Google Play + 1 → AAB → внутренний канал,
черновиком (после первой проверки Google можно поменять `release_status`
на `completed`).

Тот же сервисный аккаунт пригодится для проверки покупок
(`docs/store-purchases.md`, секрет `GOOGLE_SERVICE_ACCOUNT`).

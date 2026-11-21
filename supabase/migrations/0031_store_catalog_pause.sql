-- «Мишки»: витрина сайта TeddyTales спрятана, загрузка товаров на паузе.
--
-- Заказчик 14.10 после разговора с Ириной: teddytales.com — магазин для
-- отправок по всему миру, в ценах растаможка и налоги. В приложении вместо
-- витрины — «Скоро здесь появятся мишки TeddyTales» (`kStoreCatalogShown`
-- в `lib/screens/catalog_screen.dart`). Таблица, функции и задание cron
-- остаются; ежечасная загрузка с сайта остановлена, чтобы сервер зря не
-- ходил на чужой сайт.
--
-- Включить снова:
--   select cron.alter_job(jobid, active := true)
--     from cron.job where jobname = 'store-catalog-refresh';
--   select public.refresh_store_catalog();
--
-- Применена 14.10 через execute_sql (подтверждение apply_migration —
-- `docs/store-catalog.md`), запись в schema_migrations внесена отдельно.

select cron.alter_job(jobid, active := false)
  from cron.job
 where jobname = 'store-catalog-refresh';

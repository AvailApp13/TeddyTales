-- Закрываем функции от неавторизованных запросов.
--
-- Postgres выдаёт право выполнения роли PUBLIC при создании функции, а
-- `anon` — обычная роль Supabase для запросов с публичным ключом, то есть
-- вообще без входа, — это право наследует. Простой `grant ... to
-- authenticated` ничего не отменяет: он добавляет ещё одно разрешение
-- поверх унаследованного, и функция остаётся вызываемой снаружи.
--
-- На деле неавторизованный вызов упёрся бы в проверку владения внутри
-- функции (`auth.uid()` там пуст), но полагаться на это нельзя: право
-- выполнения и проверка внутри — две разные линии обороны, и терять внешнюю
-- ради «и так не пройдёт» неразумно.
--
-- Нашёл это линтер Supabase уже после накатывания схемы. Правило на будущее:
-- после каждой миграции с функциями смотреть его отчёт.

revoke execute on function public.cfg(text) from public, anon, authenticated;
revoke execute on function public.pet_snapshot(uuid) from public, anon;
revoke execute on function public.current_stats(uuid) from public, anon;
revoke execute on function public.record_care(uuid, public.care_action) from public, anon;
revoke execute on function public.buy_item(uuid, text) from public, anon;
revoke execute on function public.complete_level(uuid, text, smallint) from public, anon;

-- `cfg` читает настройки и вызывается только изнутри других функций —
-- наружу её выставлять незачем вовсе.

-- У `decayed` не был закреплён search_path. Функция чистая, схем не
-- касается, но при незакреплённом пути её поведение зависит от настроек
-- вызывающей роли — а это ровно тот механизм, которым подменяют функции.
alter function public.decayed(real, real, double precision, real)
  set search_path = '';

revoke execute on function public.decayed(real, real, double precision, real)
  from public, anon, authenticated;

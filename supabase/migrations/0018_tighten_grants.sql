-- 0018: подтяжка прав по проверке безопасности Supabase (25.09).
--
--   * current_stats(pet) могли вызвать любые вошедшие для ЧУЖОГО мишки:
--     проверки владельца в ней нет, это внутренняя функция. Приложение её
--     не зовёт — показатели приходят в снимке. Закрыта.
--   * Три функции без закреплённого search_path — закреплён.
--
-- Остальные замечания проверки — намеренные: действия игры (record_care,
-- feed_dish, claim_daily_gift…) вызываются из приложения и сами проверяют,
-- что мишка свой (pet_owner); player_tasks без политик — читать её
-- напрямую нельзя никому, только через функции.

revoke execute on function public.current_stats(uuid) from authenticated;

alter function public.birth_size() set search_path = public;
alter function public.next_stage(public.bear_stage) set search_path = public;
alter function public.task_of_reason(text) set search_path = public;

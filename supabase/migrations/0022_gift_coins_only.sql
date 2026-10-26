-- 0022: подарок дня — только монеты (заказчик 25.09).
--
-- «Никаких мишек и вещей в подарке»: дни 1–6 по 20 монет, седьмой —
-- большая коробка с 70 монетами. Пропустил день — серия начинается
-- сначала (grace_days = 0). Вещь-сюрприз из 0020 убрана; её настройки
-- удаляются. Числа — в панели, «Экономика» → daily_gift.

update public.game_config
set value = jsonb_build_object(
  'day1', 20, 'day2', 20, 'day3', 20, 'day4', 20, 'day5', 20, 'day6', 20,
  'day7', 70, 'grace_days', 0)
where key = 'daily_gift';

delete from public.game_config where key in ('gift_day7', 'gift_day7_pool');

create or replace function public.claim_daily_gift(p_pet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  v_today date := public.player_now(v_player)::date;
  v_day smallint;
  v_reward integer;
begin
  if exists (select 1 from public.players
             where id = v_player and gift_date = v_today) then
    raise exception 'Подарок уже забран сегодня' using errcode = 'TT409';
  end if;
  v_day := public.next_gift_day(v_player);
  v_reward := public.cfg_num('daily_gift', 'day' || v_day, 0)::integer;
  if v_reward > 0 then
    perform public.wallet_change(v_player, v_reward, 'gift:' || v_today);
  end if;

  update public.players
  set gift_day = v_day, gift_date = v_today,
      gift_last = jsonb_build_object('day', v_day, 'coins', v_reward)
  where id = v_player;

  return public.pet_snapshot(p_pet_id);
end;
$$;

revoke execute on function public.claim_daily_gift(uuid) from public, anon;
grant execute on function public.claim_daily_gift(uuid) to authenticated;

do $$
begin
  if public.cfg_num('daily_gift', 'day7', 0) <> 70
     or public.cfg_num('daily_gift', 'day1', 0) <> 20
     or public.cfg_num('daily_gift', 'grace_days', 1) <> 0 then
    raise exception 'daily_gift: награды не обновились';
  end if;
  if public.cfg('gift_day7_pool') is not null then
    raise exception 'gift_day7_pool не удалён';
  end if;
end;
$$;

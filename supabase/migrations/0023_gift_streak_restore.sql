-- 0023: вернуть серию подарка дня за монеты (заказчик 25.09).
--
-- Пропустил день — серия начинается сначала (0022). Но вчерашний пропуск
-- можно выкупить за daily_gift.restore_price монет (30): серия
-- продолжается, как будто вчера заходил. Монет за пропущенный день не
-- дают — выкупается только серия. Позавчера и раньше — уже не вернуть.
-- После седьмого дня выкупать нечего: календарь и так начинается с первого.

update public.game_config
set value = value || jsonb_build_object('restore_price', 30)
where key = 'daily_gift';

-- Можно ли сегодня выкупить вчерашний пропуск.
create or replace function public.gift_restorable(p_player uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select pl.gift_date = public.player_now(p_player)::date - 2
           and pl.gift_day between 1 and 6
    from public.players pl where pl.id = p_player), false);
$$;

create or replace function public.restore_gift_streak(p_pet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  v_today date := public.player_now(v_player)::date;
  v_price integer := public.cfg_num('daily_gift', 'restore_price', 0)::integer;
begin
  perform 1 from public.players where id = v_player for update;
  if not public.gift_restorable(v_player) then
    raise exception 'Серию не вернуть' using errcode = 'TT409';
  end if;
  if v_price > 0 then
    -- Не хватает монет — TT402 из wallet_change.
    perform public.wallet_change(v_player, -v_price, 'gift_restore:' || v_today);
  end if;
  update public.players set gift_date = v_today - 1 where id = v_player;
  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Окно «Сегодня» знает, можно ли вернуть серию и сколько это стоит.
create or replace function public.daily_outlook(p_player uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.ensure_tasks(p_player);
  v_week_start date := date_trunc('week', v_day)::date;
begin
  return jsonb_build_object(
    'day', v_day,
    'gift', jsonb_build_object(
      'available', not exists (select 1 from public.players
                               where id = p_player and gift_date = v_day),
      'next_day', public.next_gift_day(p_player),
      'claimed_day', (select gift_day from public.players where id = p_player),
      'last', (select gift_last from public.players where id = p_player),
      'rewards', (select jsonb_agg(public.cfg_num('daily_gift', 'day' || n, 0)
                                   order by n)
                  from generate_series(1, 7) n),
      'can_restore', public.gift_restorable(p_player),
      'restore_price', public.cfg_num('daily_gift', 'restore_price', 0)
    ),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.task, 'target', t.target, 'progress', t.progress,
               'done', t.done_at is not null,
               'reward', public.cfg_num('daily_tasks_reward', t.task, 0))
             order by t.task)
      from public.player_tasks t
      where t.player_id = p_player and t.day = v_day), '[]'::jsonb),
    'weekly', jsonb_build_object(
      'days_done', (
        select count(distinct d.day) from public.player_tasks d
        where d.player_id = p_player
          and d.day between v_week_start and v_week_start + 6
          and not exists (select 1 from public.player_tasks x
                          where x.player_id = d.player_id and x.day = d.day
                            and x.done_at is null)),
      'target', public.cfg_num('daily_tasks_meta', 'weekly_days', 5),
      'reward', public.cfg_num('daily_tasks_meta', 'weekly_reward', 0),
      'claimed', exists (select 1 from public.coin_ledger
                         where player_id = p_player
                           and reason = 'weekly:' || v_week_start))
  );
end;
$$;

revoke execute on function public.daily_outlook(uuid) from public, anon, authenticated;
revoke execute on function public.gift_restorable(uuid) from public, anon, authenticated;
revoke execute on function public.restore_gift_streak(uuid) from public, anon;
grant execute on function public.restore_gift_streak(uuid) to authenticated;

do $$
begin
  if public.cfg_num('daily_gift', 'restore_price', 0) <> 30 then
    raise exception 'daily_gift.restore_price не задан';
  end if;
end;
$$;

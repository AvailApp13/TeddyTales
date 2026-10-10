-- 0019: потолок монет за уход в день (КП 11.1, заказчик 25.09).
--
-- КП 11.1: «монеты за вход, уход, обучение, мини-игры, достижения;
-- ориентир 80–120 в день». За каждое действие ухода платилось 5 монет без
-- ограничения — сотня поглаживаний давала 500 монет, и ориентир ломался.
-- Теперь за уход в сумме не больше care_cap.coins_per_day за местный день
-- игрока (20 — четыре действия); дальше мишка радуется, но монет нет.
--
-- Задания дня «погладь», «поиграй», «искупай» считались по книге монет —
-- после потолка записей нет, и задание встало бы. Они переезжают на
-- журнал действий care_events: засчитывается каждое действие, с монетами
-- или без.

insert into public.game_config (key, value)
values ('care_cap', '{"coins_per_day": 20}')
on conflict (key) do nothing;

-- Начало местного дня игрока в UTC.
create or replace function public.player_day_start(p_player uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select ((public.player_now(p_player)::date)::timestamp
          - make_interval(mins => coalesce(
              (select tz_offset_min from public.players where id = p_player), 0)))
         at time zone 'UTC';
$$;

create or replace function public.record_care(
  p_pet_id uuid,
  p_action public.care_action
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  gain jsonb := public.cfg('care_gain');
  rewards jsonb := public.cfg('care_rewards');
  bonus real := 0;
  coins integer := 0;
  v_paid integer;
begin
  bonus := coalesce((gain ->> p_action::text)::real, 0);
  coins := coalesce((rewards ->> p_action::text)::integer, 0);

  perform public.settle_stats(p_pet_id,
    p_food    => case when p_action = 'feed'  then bonus else 0 end,
    p_hygiene => case when p_action = 'wash'  then bonus
                      when p_action = 'play'
                        then -public.cfg_num('hygiene_events', 'play', 0)::real
                      else 0 end,
    p_sleep   => case when p_action = 'sleep' then bonus else 0 end,
    p_play    => case when p_action = 'play'  then bonus else 0 end,
    p_love    => case when p_action = 'pet'   then bonus else 0 end);

  if p_action = 'sleep' then
    update public.pets set asleep_since = now() where id = p_pet_id;
    perform public.rhythm_bonus(p_pet_id, 'sleep');
  elsif p_action <> 'pet' then
    update public.pets set asleep_since = null where id = p_pet_id;
  end if;

  insert into public.care_events (pet_id, action) values (p_pet_id, p_action);

  -- Потолок за день (КП 11.1): сколько уже заплачено за уход сегодня.
  if coins > 0 then
    select coalesce(sum(amount), 0) into v_paid
    from public.coin_ledger
    where player_id = v_player and reason like 'care:%'
      and happened_at >= public.player_day_start(v_player);
    coins := least(coins, greatest(0,
      public.cfg_num('care_cap', 'coins_per_day', 1000000)::integer - v_paid));
  end if;

  if coins > 0 then
    perform public.wallet_change(v_player, coins, 'care:' || p_action::text);
  end if;

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Уход двигает задания дня по журналу действий, а не по монетам.
create or replace function public.task_of_reason(p_reason text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_reason like 'dish:%' then 'feed'
    when p_reason like 'recipe:%' then 'cook'
    when p_reason like 'edu:%' then 'learn'
    when p_reason like 'rhythm:bedtime:%' then 'bedtime'
    when p_reason like 'rhythm:breakfast:%'
      or p_reason like 'rhythm:lunch:%'
      or p_reason like 'rhythm:dinner:%' then 'meal_on_time'
    else null
  end;
$$;

create or replace function public.on_care_event_task()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.action in ('pet', 'play', 'wash') then
    perform public.task_step(
      (select player_id from public.pets where id = new.pet_id),
      new.action::text);
  end if;
  return new;
end;
$$;

drop trigger if exists care_events_tasks on public.care_events;
create trigger care_events_tasks
  after insert on public.care_events
  for each row execute function public.on_care_event_task();

revoke execute on function public.player_day_start(uuid) from public, anon, authenticated;
revoke execute on function public.on_care_event_task() from public, anon, authenticated;
grant execute on function public.record_care(uuid, public.care_action) to authenticated;

do $$
begin
  if public.task_of_reason('care:pet') is not null then
    raise exception 'уход не должен считаться по книге монет';
  end if;
  if public.cfg_num('care_cap', 'coins_per_day', 0) <> 20 then
    raise exception 'care_cap: нет потолка';
  end if;
end;
$$;

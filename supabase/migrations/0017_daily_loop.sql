-- 0017: подарок дня, задания дня и недели, награда за новую стадию.
--
-- Утверждено заказчиком 25.09 (первый этап игровой логики): причины
-- возвращаться каждый день. КП 11.1 — «монеты за вход, уход, обучение,
-- мини-игры, достижения; ориентир 80–120 в день»; КП 13.1 — уведомления
-- «Подарок» и «Задание»; КП 5.6 — переход стадии как событие.
--
--   * Подарок дня: календарь на 7 дней, награда растёт (10 → 50). Пропуск
--     одного дня прощается (grace_days), дольше — календарь с первого дня.
--     Забирается кнопкой (claim_daily_gift) — это момент радости, а не
--     молчаливое начисление.
--   * Задания дня: три из пула на каждый местный день игрока (выбор
--     устойчивый: весь день одни и те же). Засчитываются сами — по книге
--     монет: погладил, поиграл, умыл, накормил блюдом, приготовил, поел
--     вовремя, уложил вовремя, прошёл урок. Выполнил — награда сразу.
--   * Задание недели: все задания дня выполнены в 5 днях из 7 одной
--     недели — бонус.
--   * Новая стадия: монеты при переходе (stage_rewards).
--
-- Все числа в game_config, плоскими таблицами — их правит панель
-- (раздел «Экономика», КП 15.4).

-- --- Состояние ---------------------------------------------------------------

alter table public.players
  add column if not exists gift_day smallint not null default 0
    check (gift_day between 0 and 7),
  add column if not exists gift_date date;
comment on column public.players.gift_day is
  'Какой день календаря подарков забран последним (1–7); 0 — ещё ни разу.';

create table if not exists public.player_tasks (
  player_id uuid not null references public.players (id) on delete cascade,
  day date not null,
  task text not null,
  target smallint not null check (target > 0),
  progress smallint not null default 0,
  done_at timestamptz,
  primary key (player_id, day, task)
);
comment on table public.player_tasks is
  'Задания дня игрока (местный день). Пишут только серверные функции.';

-- Читать и писать напрямую нельзя никому: всё через функции.
alter table public.player_tasks enable row level security;
revoke all on public.player_tasks from anon, authenticated;

-- --- Настройки ---------------------------------------------------------------

insert into public.game_config (key, value) values
  ('daily_gift', '{"day1": 10, "day2": 15, "day3": 20, "day4": 25,
                   "day5": 30, "day6": 35, "day7": 50, "grace_days": 1}'),
  ('daily_tasks_target', '{"pet": 3, "play": 2, "wash": 1, "feed": 2,
                           "cook": 1, "learn": 1, "meal_on_time": 2,
                           "bedtime": 1}'),
  ('daily_tasks_reward', '{"pet": 10, "play": 10, "wash": 10, "feed": 10,
                           "cook": 15, "learn": 15, "meal_on_time": 15,
                           "bedtime": 15}'),
  ('daily_tasks_meta', '{"per_day": 3, "weekly_days": 5, "weekly_reward": 50}'),
  ('stage_rewards', '{"crawling": 20, "firstSteps": 30, "growing": 40,
                      "adult": 100}')
on conflict (key) do nothing;

-- --- Задания -----------------------------------------------------------------

-- Задания на сегодня: заводит три, если их ещё нет. Выбор устойчивый — хэш
-- от игрока и дня, — и разный у разных игроков.
create or replace function public.ensure_tasks(p_player uuid)
returns date
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.player_now(p_player)::date;
begin
  if not exists (select 1 from public.player_tasks
                 where player_id = p_player and day = v_day) then
    insert into public.player_tasks (player_id, day, task, target)
    select p_player, v_day, t.key, greatest(1, (t.value)::text::integer)
    from jsonb_each(coalesce(public.cfg('daily_tasks_target'), '{}'::jsonb)) t
    where jsonb_typeof(t.value) = 'number'
    order by md5(p_player::text || v_day::text || t.key)
    limit public.cfg_num('daily_tasks_meta', 'per_day', 3)::integer
    on conflict do nothing;
  end if;
  return v_day;
end;
$$;

-- Какое задание двигает запись в книге монет.
create or replace function public.task_of_reason(p_reason text)
returns text
language sql
immutable
as $$
  select case
    when p_reason = 'care:pet' then 'pet'
    when p_reason = 'care:play' then 'play'
    when p_reason = 'care:wash' then 'wash'
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

-- Засчитать шаг задания; выполнено — награда, все за день — проверка недели.
create or replace function public.task_step(p_player uuid, p_task text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.ensure_tasks(p_player);
  v_done boolean;
  v_reward integer;
  v_week_start date;
  v_week_days integer;
  v_week_reason text;
begin
  update public.player_tasks t
  set progress = least(t.target, t.progress + 1),
      done_at = case when t.progress + 1 >= t.target then now() else null end
  where t.player_id = p_player and t.day = v_day and t.task = p_task
    and t.done_at is null
  returning t.done_at is not null into v_done;

  if not coalesce(v_done, false) then
    return;
  end if;

  v_reward := public.cfg_num('daily_tasks_reward', p_task, 0)::integer;
  if v_reward > 0 then
    perform public.wallet_change(p_player, v_reward,
      'task:' || p_task || ':' || v_day);
  end if;

  -- Все задания дня выполнены — к неделе.
  if exists (select 1 from public.player_tasks
             where player_id = p_player and day = v_day and done_at is null) then
    return;
  end if;
  v_week_start := date_trunc('week', v_day)::date;
  select count(distinct day) into v_week_days
  from public.player_tasks d
  where d.player_id = p_player
    and d.day between v_week_start and v_week_start + 6
    and not exists (select 1 from public.player_tasks x
                    where x.player_id = d.player_id and x.day = d.day
                      and x.done_at is null);
  v_week_reason := 'weekly:' || v_week_start;
  if v_week_days >= public.cfg_num('daily_tasks_meta', 'weekly_days', 5)
     and not exists (select 1 from public.coin_ledger
                     where player_id = p_player and reason = v_week_reason) then
    perform public.wallet_change(p_player,
      public.cfg_num('daily_tasks_meta', 'weekly_reward', 0)::integer,
      v_week_reason);
  end if;
end;
$$;

-- Книга монет двигает задания. Награды за сами задания (task:, weekly:) не
-- двигают ничего — круга нет.
create or replace function public.on_coin_ledger_task()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task text := public.task_of_reason(new.reason);
begin
  if v_task is not null then
    perform public.task_step(new.player_id, v_task);
  end if;
  return new;
end;
$$;

drop trigger if exists coin_ledger_tasks on public.coin_ledger;
create trigger coin_ledger_tasks
  after insert on public.coin_ledger
  for each row execute function public.on_coin_ledger_task();

-- --- Подарок дня -------------------------------------------------------------

-- Какой день календаря будет следующим.
create or replace function public.next_gift_day(p_player uuid)
returns smallint
language sql
stable
security definer
set search_path = public
as $$
  select case
    when pl.gift_date is not null
         and pl.gift_date >= public.player_now(p_player)::date
                             - (1 + public.cfg_num('daily_gift', 'grace_days', 1)::integer)
    then (pl.gift_day % 7 + 1)::smallint
    else 1::smallint
  end
  from public.players pl where pl.id = p_player;
$$;

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
  update public.players set gift_day = v_day, gift_date = v_today
  where id = v_player;
  if v_reward > 0 then
    perform public.wallet_change(v_player, v_reward, 'gift:' || v_today);
  end if;
  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Что показать игроку на сегодня: подарок, задания, неделя.
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
      'rewards', (select jsonb_agg(public.cfg_num('daily_gift', 'day' || n, 0)
                                   order by n)
                  from generate_series(1, 7) n)
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

-- --- Награда за новую стадию -------------------------------------------------

create or replace function public.advance_growth(p_pet_id uuid)
returns public.bear_stage
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  p public.pets%rowtype;
  cur record;
  v_care real;
  v_hours double precision;
  v_need double precision;
  v_next public.bear_stage;
  v_reward integer;
begin
  select * into p from public.pets where id = p_pet_id for update;
  if not found then
    return null;
  end if;

  select * into cur from public.current_stats(p_pet_id);
  v_care := (cur.food + cur.hygiene + cur.sleep + cur.play + cur.love) / 5.0;

  v_hours := extract(epoch from (now() - p.growth_at)) / 3600.0
             * (public.growth_speed(coalesce(p.growth_care, v_care))
                + public.growth_speed(v_care)) / 2.0;
  p.growth_hours := p.growth_hours + greatest(0, v_hours);

  loop
    v_next := public.next_stage(p.stage);
    exit when v_next is null;
    v_need := (public.cfg('stage_durations') ->> p.stage::text)::double precision;
    exit when v_need is null or p.growth_hours < v_need;
    p.growth_hours := p.growth_hours - v_need;
    p.stage := v_next;
    p.stage_changed_at := now();
    -- Подрос — подарок (КП 5.6: переход стадии — событие).
    v_reward := public.cfg_num('stage_rewards', v_next::text, 0)::integer;
    if v_reward > 0 then
      perform public.wallet_change(p.player_id, v_reward, 'stage:' || v_next::text);
    end if;
  end loop;

  if public.next_stage(p.stage) is null then
    p.growth_hours := 0;
  end if;

  update public.pets
  set stage = p.stage,
      stage_changed_at = p.stage_changed_at,
      growth_hours = p.growth_hours,
      growth_at = now(),
      growth_care = v_care
  where id = p_pet_id;

  return p.stage;
end;
$$;

-- --- Снимок: сегодняшний день ------------------------------------------------

create or replace function public.pet_snapshot(p_pet_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  cur record;
  result jsonb;
begin
  perform public.advance_growth(p_pet_id);

  select * into cur from public.current_stats(p_pet_id);

  select jsonb_build_object(
    'server_time', now(),
    'account', (
      select jsonb_build_object(
        'coins', pl.coins,
        'locale', pl.locale,
        'player_age', pl.player_age,
        'quiet_hours', pl.quiet_hours,
        'created_at', pl.created_at,
        'registered_at', coalesce(u.created_at, pl.created_at),
        'is_anonymous', coalesce(u.is_anonymous, false),
        'email', u.email,
        'email_confirmed', u.email_confirmed_at is not null,
        'providers', coalesce(
          (select jsonb_agg(distinct i.provider) from auth.identities i
           where i.user_id = pl.id), '[]'::jsonb)
      )
      from public.players pl
      left join auth.users u on u.id = pl.id
      where pl.id = v_player
    ),
    'pet', to_jsonb(p) - 'player_id',
    'zodiac', (
      select to_jsonb(z) from public.zodiac_signs z where z.id = p.zodiac
    ),
    'zodiac_inclinations', coalesce(
      public.cfg('zodiac_inclinations') -> (p.zodiac::text), '{}'::jsonb),
    'growth', public.growth_outlook(p.id),
    'asleep', public.is_asleep(p.id),
    'rates', public.needs_now(p.id),
    'daily', public.daily_outlook(v_player),
    'stats', jsonb_build_object(
      'food', cur.food, 'hygiene', cur.hygiene, 'sleep', cur.sleep,
      'play', cur.play, 'love', cur.love
    ),
    'outfit', coalesce(to_jsonb(o) - 'pet_id', '{}'::jsonb),
    'inventory', coalesce(
      (select jsonb_agg(i.item_id) from public.inventory i
       where i.player_id = v_player), '[]'::jsonb),
    'placed', coalesce(
      (select jsonb_agg(r.item_id) from public.room_layout r
       where r.player_id = v_player), '[]'::jsonb),
    'edu', coalesce(
      (select jsonb_object_agg(e.category_id, e.levels_done)
       from public.edu_progress e where e.player_id = v_player), '{}'::jsonb)
  )
  into result
  from public.pets p
  left join public.pet_outfit o on o.pet_id = p.id
  where p.id = p_pet_id;

  return result;
end;
$$;

-- --- Права -------------------------------------------------------------------

revoke execute on function public.ensure_tasks(uuid) from public, anon, authenticated;
revoke execute on function public.task_step(uuid, text) from public, anon, authenticated;
revoke execute on function public.on_coin_ledger_task() from public, anon, authenticated;
revoke execute on function public.next_gift_day(uuid) from public, anon, authenticated;
revoke execute on function public.daily_outlook(uuid) from public, anon, authenticated;
revoke execute on function public.advance_growth(uuid) from public, anon, authenticated;
revoke execute on function public.claim_daily_gift(uuid) from public, anon;
grant execute on function public.claim_daily_gift(uuid) to authenticated;
revoke execute on function public.pet_snapshot(uuid) from public, anon;
grant execute on function public.pet_snapshot(uuid) to authenticated;

-- --- Самопроверка ------------------------------------------------------------

do $$
begin
  if public.task_of_reason('care:pet') <> 'pet'
     or public.task_of_reason('rhythm:lunch:2026-09-25') <> 'meal_on_time'
     or public.task_of_reason('rhythm:bedtime:2026-09-25') <> 'bedtime'
     or public.task_of_reason('recipe:cookie') <> 'cook'
     or public.task_of_reason('task:pet:2026-09-25') is not null
     or public.task_of_reason('test_floor') is not null then
    raise exception 'task_of_reason: неверное соответствие';
  end if;
  if public.cfg_num('daily_gift', 'day7', 0) <> 50 then
    raise exception 'daily_gift: нет календаря';
  end if;
end;
$$;

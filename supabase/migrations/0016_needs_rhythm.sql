-- 0016: распорядок дня, ночной сон, возраст и «мишка у бабушки».
--
-- Утверждено заказчиком 25.09 (первый этап игровой логики). До этого все
-- пять показателей падали круглые сутки с одной скоростью, а «Еда» — на
-- 25 % в час: к порогу голода мишка приходил меньше чем за три часа, и
-- кто спит ночью, каждое утро находил его на дне. По КП 6.2 последствия
-- мягкие — так быть не должно.
--
-- Что меняется (все числа — в game_config, правятся в панели, КП 15.4):
--
--   * Скорости спокойнее: еда 10 %/ч (порог голода через ~7 ч), гигиена 6,
--     сон 5, игра 7, любовь 4.
--   * Возраст (needs_by_stage): малыш просит чаще (×1,3), взрослый реже
--     (×0,7) — первые дни самые живые, дальше игра не становится
--     обязанностью.
--   * Сон (night): «Уложить спать» теперь состояние на сервере
--     (pets.asleep_since). Пока мишка спит, еда, гигиена, игра и любовь
--     падают вчетверо медленнее, а сон восстанавливается 12 %/ч. Больше
--     10 часов не спит — просыпается сам.
--   * Распорядок (rhythm, по местному времени игрока): покормил в окно
--     завтрака, обеда или ужина — бонус монет и любви, раз за окно; уложил
--     вовремя (20–23) — бонус раз за вечер.
--   * «Мишка у бабушки» (away): не заходил больше 3 суток — показатели при
--     возвращении не ниже 70, подарок монетами и радостная встреча. Ушедших
--     не наказываем.
--   * Еда (food_rules): одно и то же блюдо за сутки сытит всё меньше
--     (×0,6 за каждый повтор, не меньше ×0,3) — поощряем разнообразие и
--     готовку. Отказ от еды на полный живот — refuse_at; пока 0 (выключен):
--     в приложении «Еда» закреплена заглушкой испытаний, и отказ сервера
--     спорил бы с ней. Перед публикацией — 95 (CLAUDE.md, заглушки).
--   * Гигиена от событий (hygiene_events): поел — чуть испачкался, поиграл
--     — заметнее.

-- --- Состояние ---------------------------------------------------------------

alter table public.pets
  add column if not exists asleep_since timestamptz;
comment on column public.pets.asleep_since is
  'Когда уложили спать; null — не спит. Сам просыпается через night.max_sleep_hours.';

alter table public.players
  add column if not exists tz_offset_min integer
    check (tz_offset_min between -840 and 840);
comment on column public.players.tz_offset_min is
  'Смещение часового пояса игрока, минуты. Присылает приложение при входе.';

-- --- Настройки ---------------------------------------------------------------

update public.game_config
set value = '{"floor": 20, "food_per_hour": 10, "hygiene_per_hour": 6,
              "sleep_per_hour": 5, "play_per_hour": 7, "love_per_hour": 4}'::jsonb
where key = 'decay';

-- Сон теперь восстанавливается во сне, а не рывком от кнопки.
update public.game_config
set value = jsonb_set(value, '{sleep}', '10')
where key = 'care_gain';

insert into public.game_config (key, value) values
  ('needs_by_stage', '{"newborn": 1.3, "crawling": 1.15, "firstSteps": 1.0,
                       "growing": 0.85, "adult": 0.7}'),
  ('night', '{"asleep_factor": 0.25, "sleep_restore_per_hour": 12,
              "max_sleep_hours": 10}'),
  ('rhythm', '{"breakfast_from": 7, "breakfast_to": 10,
               "lunch_from": 12, "lunch_to": 15,
               "dinner_from": 18, "dinner_to": 21,
               "bedtime_from": 20, "bedtime_to": 23,
               "meal_bonus_coins": 5, "meal_bonus_love": 10,
               "bedtime_bonus_coins": 5}'),
  ('away', '{"after_hours": 72, "restore_to": 70, "gift_coins": 20}'),
  ('food_rules', '{"repeat_factor": 0.6, "min_factor": 0.3, "refuse_at": 0}'),
  ('hygiene_events', '{"feed": 5, "play": 10}')
on conflict (key) do nothing;

-- --- Вспомогательное ---------------------------------------------------------

create or replace function public.cfg_num(p_key text, p_field text, p_default double precision)
returns double precision
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((public.cfg(p_key) ->> p_field)::double precision, p_default);
$$;

-- Местное время игрока.
create or replace function public.player_now(p_player uuid)
returns timestamp
language sql
stable
security definer
set search_path = public
as $$
  select (now() at time zone 'UTC')
         + make_interval(mins => coalesce(
             (select tz_offset_min from public.players where id = p_player), 0));
$$;

-- В каком окне распорядка сейчас игрок: 'breakfast' / 'lunch' / 'dinner' /
-- 'bedtime' / null. Окна еды и сна проверяются отдельно (p_kind).
create or replace function public.rhythm_window(p_player uuid, p_kind text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  h integer := extract(hour from public.player_now(p_player));
  w text;
begin
  foreach w in array case when p_kind = 'sleep'
                          then array['bedtime']
                          else array['breakfast', 'lunch', 'dinner'] end loop
    if h >= public.cfg_num('rhythm', w || '_from', -1)
       and h < public.cfg_num('rhythm', w || '_to', -1) then
      return w;
    end if;
  end loop;
  return null;
end;
$$;

-- Спит ли мишка сейчас (с учётом самостоятельного пробуждения).
create or replace function public.is_asleep(p_pet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p.asleep_since is not null
         and now() < p.asleep_since
             + make_interval(secs => public.cfg_num('night', 'max_sleep_hours', 10) * 3600)
  from public.pets p where p.id = p_pet_id;
$$;

-- Множитель потребностей по стадии.
create or replace function public.needs_factor(p_pet_id uuid)
returns double precision
language sql
stable
security definer
set search_path = public
as $$
  select public.cfg_num('needs_by_stage', p.stage::text, 1.0)
  from public.pets p where p.id = p_pet_id;
$$;

-- --- Показатели «сейчас» -----------------------------------------------------

create or replace function public.current_stats(p_pet_id uuid)
returns table (
  food real, hygiene real, sleep real, play real, love real, at_time timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d jsonb := public.cfg('decay');
  s public.pet_stats%rowtype;
  p public.pets%rowtype;
  hours double precision;
  asleep_h double precision := 0;
  awake_h double precision;
  k double precision;
  af double precision := public.cfg_num('night', 'asleep_factor', 0.25);
  restore double precision := public.cfg_num('night', 'sleep_restore_per_hour', 12);
  floor_value real;
  v_end timestamptz;
begin
  select * into s from public.pet_stats where pet_id = p_pet_id;
  if not found then
    raise exception 'Нет показателей для питомца %', p_pet_id;
  end if;
  select * into p from public.pets where id = p_pet_id;

  hours := greatest(0, extract(epoch from (now() - s.measured_at)) / 3600.0);
  floor_value := (d ->> 'floor')::real;
  k := public.cfg_num('needs_by_stage', p.stage::text, 1.0);

  -- Сон всегда в начале промежутка: уложить спать — действие, а оно
  -- досчитывает показатели и ставит новый замер.
  if p.asleep_since is not null then
    v_end := p.asleep_since
             + make_interval(secs => public.cfg_num('night', 'max_sleep_hours', 10) * 3600);
    asleep_h := greatest(0, least(hours,
      extract(epoch from (least(now(), v_end) - greatest(s.measured_at, p.asleep_since))) / 3600.0));
  end if;
  awake_h := hours - asleep_h;

  return query select
    public.decayed(s.food,    ((d ->> 'food_per_hour')::double precision * k)::real,    awake_h + asleep_h * af, floor_value),
    public.decayed(s.hygiene, ((d ->> 'hygiene_per_hour')::double precision * k)::real, awake_h + asleep_h * af, floor_value),
    public.decayed(least(100, s.sleep + restore * asleep_h)::real,
                              ((d ->> 'sleep_per_hour')::double precision * k)::real,   awake_h, floor_value),
    public.decayed(s.play,    ((d ->> 'play_per_hour')::double precision * k)::real,    awake_h + asleep_h * af, floor_value),
    public.decayed(s.love,    ((d ->> 'love_per_hour')::double precision * k)::real,    awake_h + asleep_h * af, floor_value),
    now();
end;
$$;

-- Скорости «прямо сейчас», в процентах за час; отрицательная — показатель
-- растёт (сон во сне). Приложение плавно двигает шкалы между ответами
-- сервера по этим же числам.
create or replace function public.needs_now(p_pet_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d jsonb := public.cfg('decay');
  k double precision := public.needs_factor(p_pet_id);
  f double precision := 1;
  asleep boolean := public.is_asleep(p_pet_id);
begin
  if asleep then
    f := public.cfg_num('night', 'asleep_factor', 0.25);
  end if;
  return jsonb_build_object(
    'food',    (d ->> 'food_per_hour')::double precision * k * f,
    'hygiene', (d ->> 'hygiene_per_hour')::double precision * k * f,
    'sleep',   case when asleep
                    then -public.cfg_num('night', 'sleep_restore_per_hour', 12)
                    else (d ->> 'sleep_per_hour')::double precision * k end,
    'play',    (d ->> 'play_per_hour')::double precision * k * f,
    'love',    (d ->> 'love_per_hour')::double precision * k * f,
    'floor',   (d ->> 'floor')::double precision
  );
end;
$$;

-- Досчитать показатели до «сейчас» и записать с поправками.
create or replace function public.settle_stats(
  p_pet_id uuid,
  p_food real default 0,
  p_hygiene real default 0,
  p_sleep real default 0,
  p_play real default 0,
  p_love real default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur record;
  fl real := public.cfg_num('decay', 'floor', 20)::real;
begin
  -- Поправка вниз не опускает ниже дна (КП 6.3), вверх — не выше 100.
  select * into cur from public.current_stats(p_pet_id);
  update public.pet_stats set
    food    = least(100, greatest(least(cur.food, fl),    cur.food + p_food)),
    hygiene = least(100, greatest(least(cur.hygiene, fl), cur.hygiene + p_hygiene)),
    sleep   = least(100, greatest(least(cur.sleep, fl),   cur.sleep + p_sleep)),
    play    = least(100, greatest(least(cur.play, fl),    cur.play + p_play)),
    love    = least(100, greatest(least(cur.love, fl),    cur.love + p_love)),
    measured_at = cur.at_time
  where pet_id = p_pet_id;
end;
$$;

-- Бонус распорядка: раз за окно (еда) или раз за вечер (сон).
create or replace function public.rhythm_bonus(p_pet_id uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := (select player_id from public.pets where id = p_pet_id);
  w text := public.rhythm_window(v_player, p_kind);
  v_reason text;
  v_coins integer;
begin
  if w is null then
    return;
  end if;
  v_reason := 'rhythm:' || w || ':' || public.player_now(v_player)::date;
  if exists (select 1 from public.coin_ledger
             where player_id = v_player and reason = v_reason) then
    return;
  end if;
  v_coins := public.cfg_num('rhythm',
    case when p_kind = 'sleep' then 'bedtime_bonus_coins' else 'meal_bonus_coins' end, 0)::integer;
  if v_coins > 0 then
    perform public.wallet_change(v_player, v_coins, v_reason);
  end if;
  if p_kind = 'meal' then
    perform public.settle_stats(p_pet_id,
      p_love => public.cfg_num('rhythm', 'meal_bonus_love', 0)::real);
  end if;
end;
$$;

-- --- Действия ----------------------------------------------------------------

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

  -- Уложили — спит; разбудили или занялись им (кроме поглаживания) — проснулся.
  if p_action = 'sleep' then
    update public.pets set asleep_since = now() where id = p_pet_id;
    perform public.rhythm_bonus(p_pet_id, 'sleep');
  elsif p_action <> 'pet' then
    update public.pets set asleep_since = null where id = p_pet_id;
  end if;

  insert into public.care_events (pet_id, action) values (p_pet_id, p_action);

  if coins > 0 then
    perform public.wallet_change(v_player, coins, 'care:' || p_action::text);
  end if;

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Прежняя подпись без p_what уступает место новой: две сразу сделали бы
-- вызов feed_pet(id, x) двусмысленным.
drop function if exists public.feed_pet(uuid, real);

-- Покормить на p_food: одно и то же за сутки сытит всё меньше, еда пачкает,
-- мишка просыпается; в окно завтрака, обеда, ужина — бонус.
-- p_what — 'dish:<id>' или 'recipe:<id>', как в книге монет.
create or replace function public.feed_pet(p_pet_id uuid, p_food real, p_what text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := (select player_id from public.pets where id = p_pet_id);
  v_repeats integer := 0;
  v_factor double precision := 1;
begin
  if p_what is not null then
    -- Сама покупка уже записана в книгу — её не считаем.
    select greatest(count(*) - 1, 0) into v_repeats
    from public.coin_ledger
    where player_id = v_player and reason = p_what
      and happened_at > now() - interval '24 hours';
    v_factor := greatest(
      public.cfg_num('food_rules', 'min_factor', 0.3),
      power(public.cfg_num('food_rules', 'repeat_factor', 1), v_repeats));
  end if;

  perform public.settle_stats(p_pet_id,
    p_food => (greatest(p_food, 0) * v_factor)::real,
    p_hygiene => -public.cfg_num('hygiene_events', 'feed', 0)::real);
  update public.pets set asleep_since = null where id = p_pet_id;
  insert into public.care_events (pet_id, action) values (p_pet_id, 'feed');
  perform public.rhythm_bonus(p_pet_id, 'meal');
end;
$$;

-- Сыт — отказывается (food_rules.refuse_at; 0 — выключено).
create or replace function public.check_hungry(p_pet_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at double precision := public.cfg_num('food_rules', 'refuse_at', 0);
  cur record;
begin
  if v_at <= 0 then
    return;
  end if;
  select * into cur from public.current_stats(p_pet_id);
  if cur.food >= v_at then
    raise exception 'Мишка сыт' using errcode = 'TT409';
  end if;
end;
$$;

create or replace function public.feed_dish(p_pet_id uuid, p_dish_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  v_dish jsonb := public.cfg('dishes') -> p_dish_id;
  v_price integer;
begin
  if v_dish is null then
    raise exception 'Нет блюда %', p_dish_id using errcode = 'TT404';
  end if;
  perform public.check_hungry(p_pet_id);
  v_price := coalesce((v_dish ->> 'price')::integer, 0);

  if v_price > 0 then
    perform public.wallet_change(v_player, -v_price, 'dish:' || p_dish_id);
  end if;
  perform public.feed_pet(p_pet_id, coalesce((v_dish ->> 'food')::real, 0),
                          'dish:' || p_dish_id);

  return public.pet_snapshot(p_pet_id);
end;
$$;

create or replace function public.complete_recipe(p_pet_id uuid, p_recipe_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  v_recipe jsonb := public.cfg('recipes') -> p_recipe_id;
  v_reward integer;
begin
  if v_recipe is null then
    raise exception 'Нет рецепта %', p_recipe_id using errcode = 'TT404';
  end if;
  perform public.check_hungry(p_pet_id);
  v_reward := coalesce((v_recipe ->> 'reward')::integer, 0);

  if v_reward > 0 then
    perform public.wallet_change(v_player, v_reward, 'recipe:' || p_recipe_id);
  end if;
  perform public.feed_pet(p_pet_id, coalesce((v_recipe ->> 'food')::real, 0),
                          'recipe:' || p_recipe_id);

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- --- Вход: часовой пояс и «мишка у бабушки» -----------------------------------

drop function if exists public.open_account();

create or replace function public.open_account(p_tz_offset_min integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_pet uuid;
  v_floor integer := coalesce((public.cfg('test_wallet_floor'))::text::integer, 0);
  v_coins integer;
  v_last timestamptz;
  v_back boolean := false;
  v_to real;
  cur record;
  v_gift integer;
begin
  if v_player is null then
    raise exception 'Нет входа' using errcode = 'TT401';
  end if;

  select id into v_pet from public.pets
  where player_id = v_player
  order by created_at
  limit 1;
  if v_pet is null then
    raise exception 'У игрока нет питомца' using errcode = 'TT404';
  end if;

  select last_seen_at into v_last from public.players where id = v_player;

  -- Долго не было: мишка гостил у бабушки — сыт, умыт, выспался, ждёт.
  if v_last is not null
     and v_last < now() - make_interval(secs => public.cfg_num('away', 'after_hours', 72) * 3600) then
    v_back := true;
    v_to := public.cfg_num('away', 'restore_to', 70)::real;
    select * into cur from public.current_stats(v_pet);
    update public.pet_stats set
      food = greatest(cur.food, v_to), hygiene = greatest(cur.hygiene, v_to),
      sleep = greatest(cur.sleep, v_to), play = greatest(cur.play, v_to),
      love = greatest(cur.love, v_to), measured_at = now()
    where pet_id = v_pet;
    update public.pets set asleep_since = null where id = v_pet;
    v_gift := public.cfg_num('away', 'gift_coins', 0)::integer;
    if v_gift > 0 then
      perform public.wallet_change(v_player, v_gift, 'welcome_back');
    end if;
  end if;

  update public.players
  set last_seen_at = now(),
      tz_offset_min = case when p_tz_offset_min between -840 and 840
                           then p_tz_offset_min else tz_offset_min end
  where id = v_player
  returning coins into v_coins;

  -- Испытания: при каждом входе поднять до порога. Разница идёт по книге
  -- операций с пометкой test_floor, чтобы её было видно в отчётах.
  if v_floor > 0 and v_coins < v_floor then
    perform public.wallet_change(v_player, v_floor - v_coins, 'test_floor');
  end if;

  return public.pet_snapshot(v_pet) || jsonb_build_object('welcome_back', v_back);
end;
$$;

-- --- Снимок: сон и скорости --------------------------------------------------

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

revoke execute on function public.cfg_num(text, text, double precision) from public, anon, authenticated;
revoke execute on function public.player_now(uuid) from public, anon, authenticated;
revoke execute on function public.rhythm_window(uuid, text) from public, anon, authenticated;
revoke execute on function public.is_asleep(uuid) from public, anon, authenticated;
revoke execute on function public.needs_factor(uuid) from public, anon, authenticated;
revoke execute on function public.current_stats(uuid) from public, anon;
revoke execute on function public.needs_now(uuid) from public, anon, authenticated;
revoke execute on function public.settle_stats(uuid, real, real, real, real, real) from public, anon, authenticated;
revoke execute on function public.rhythm_bonus(uuid, text) from public, anon, authenticated;
revoke execute on function public.check_hungry(uuid) from public, anon, authenticated;
revoke execute on function public.feed_pet(uuid, real, text) from public, anon, authenticated;
revoke execute on function public.open_account(integer) from public, anon;
grant execute on function public.open_account(integer) to authenticated;
grant execute on function public.record_care(uuid, public.care_action) to authenticated;
grant execute on function public.feed_dish(uuid, text) to authenticated;
grant execute on function public.complete_recipe(uuid, text) to authenticated;
revoke execute on function public.pet_snapshot(uuid) from public, anon;
grant execute on function public.pet_snapshot(uuid) to authenticated;

-- --- Самопроверка ------------------------------------------------------------

do $$
begin
  if public.cfg_num('decay', 'food_per_hour', 0) <> 10 then
    raise exception 'decay: скорости не обновились';
  end if;
  if public.cfg_num('needs_by_stage', 'adult', 0) <> 0.7 then
    raise exception 'needs_by_stage: нет настроек возраста';
  end if;
end;
$$;

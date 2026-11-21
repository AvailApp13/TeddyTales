-- Серверные функции: всё, что двигает показатели и монеты.
--
-- Каждая функция объявлена `security definer`, то есть выполняется с правами
-- владельца и построчную защиту обходит. Поэтому владение проверяется внутри
-- явно, первой же строкой: `security definer` без такой проверки — это дыра,
-- через которую чужой питомец становится своим.

-- --- Доступ к настройкам ---------------------------------------------------

create or replace function public.cfg(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select value from public.game_config where key = p_key;
$$;

-- --- Пересчёт показателей --------------------------------------------------

-- Что стало с показателями к моменту `p_now`.
--
-- Здесь и живёт серверное время (КП 1.5). Значение падает со скоростью из
-- настроек, но не ниже безопасного предела (КП 6.3): болезней и смерти в игре
-- нет (КП 6.2), поэтому дно мягкое, а не ноль.
create or replace function public.decayed(
  p_value real,
  p_per_hour real,
  p_hours double precision,
  p_floor real
)
returns real
language sql
immutable
as $$
  select greatest(
    least(p_value, p_floor),              -- уже ниже дна — ниже не опустим
    (p_value - p_per_hour * p_hours)::real
  );
$$;

comment on function public.decayed is
  'Падение показателя за p_hours. Ниже пола не опускает, но и не поднимает того, кто уже под ним.';

-- Показатели питомца на текущий серверный момент.
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
  hours double precision;
  floor_value real;
begin
  select * into s from public.pet_stats where pet_id = p_pet_id;
  if not found then
    raise exception 'Нет показателей для питомца %', p_pet_id;
  end if;

  hours := extract(epoch from (now() - s.measured_at)) / 3600.0;
  floor_value := (d ->> 'floor')::real;

  return query select
    public.decayed(s.food,    (d ->> 'food_per_hour')::real,    hours, floor_value),
    public.decayed(s.hygiene, (d ->> 'hygiene_per_hour')::real, hours, floor_value),
    public.decayed(s.sleep,   (d ->> 'sleep_per_hour')::real,   hours, floor_value),
    public.decayed(s.play,    (d ->> 'play_per_hour')::real,    hours, floor_value),
    public.decayed(s.love,    (d ->> 'love_per_hour')::real,    hours, floor_value),
    now();
end;
$$;

-- --- Действия ухода --------------------------------------------------------

-- Выполняет действие ухода: поднимает нужный показатель, записывает событие
-- для расчёта характера (КП 7.3) и начисляет монеты (КП 6.4, 11.1).
--
-- Порядок важен: сначала показатели досчитываются до «сейчас», и только потом
-- к ним прибавляется эффект действия. Иначе покормленный питомец получил бы
-- сытость от старого замера, то есть время отката простаивало бы впустую.
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
  v_player uuid;
  gain jsonb := public.cfg('care_gain');
  rewards jsonb := public.cfg('care_rewards');
  cur record;
  bonus real := coalesce((gain ->> p_action::text)::real, 0);
  coins integer := coalesce((rewards ->> p_action::text)::integer, 0);
begin
  select player_id into v_player from public.pets where id = p_pet_id;
  if v_player is null or v_player <> auth.uid() then
    raise exception 'Питомец % не принадлежит игроку', p_pet_id;
  end if;

  select * into cur from public.current_stats(p_pet_id);

  update public.pet_stats set
    food    = least(100, cur.food    + case when p_action = 'feed'  then bonus else 0 end),
    hygiene = least(100, cur.hygiene + case when p_action = 'wash'  then bonus else 0 end),
    sleep   = least(100, cur.sleep   + case when p_action = 'sleep' then bonus else 0 end),
    play    = least(100, cur.play    + case when p_action = 'play'  then bonus else 0 end),
    love    = least(100, cur.love    + case when p_action = 'pet'   then bonus else 0 end),
    measured_at = cur.at_time
  where pet_id = p_pet_id;

  insert into public.care_events (pet_id, action) values (p_pet_id, p_action);

  if coins > 0 then
    perform public.grant_coins(p_pet_id, coins, 'care:' || p_action::text);
  end if;

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Начисление монет. Единственное место, где баланс растёт: любой приход
-- обязан оставить след в книге, иначе на вопрос «откуда столько монет»
-- ответить будет нечем.
create or replace function public.grant_coins(
  p_pet_id uuid,
  p_amount integer,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid;
  v_balance integer;
begin
  select player_id into v_player from public.pets where id = p_pet_id;
  if v_player is null then
    raise exception 'Питомец % не найден', p_pet_id;
  end if;

  update public.pets set coins = coins + p_amount
  where id = p_pet_id
  returning coins into v_balance;

  insert into public.coin_ledger (player_id, amount, reason)
  values (v_player, p_amount, p_reason);

  return v_balance;
end;
$$;

-- --- Покупка предмета ------------------------------------------------------

-- Цену берём из настроек, а не из запроса: цена, присланная клиентом, —
-- это предложение купить слона за рубль.
create or replace function public.buy_item(p_pet_id uuid, p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid;
  v_price integer;
  v_coins integer;
begin
  select player_id into v_player from public.pets where id = p_pet_id;
  if v_player is null or v_player <> auth.uid() then
    raise exception 'Питомец % не принадлежит игроку', p_pet_id;
  end if;

  v_price := (public.cfg('item_prices') ->> p_item_id)::integer;
  if v_price is null then
    raise exception 'Нет цены для предмета %', p_item_id;
  end if;

  if exists (select 1 from public.inventory
             where player_id = v_player and item_id = p_item_id) then
    raise exception 'Предмет % уже куплен', p_item_id;
  end if;

  select coins into v_coins from public.pets where id = p_pet_id;
  if v_coins < v_price then
    raise exception 'Не хватает монет: нужно %, есть %', v_price, v_coins;
  end if;

  if v_price > 0 then
    perform public.grant_coins(p_pet_id, -v_price, 'buy:' || p_item_id);
  end if;

  insert into public.inventory (player_id, item_id, source, price_paid)
  values (v_player, p_item_id,
          case when v_price = 0 then 'free'::public.item_source
               else 'coins'::public.item_source end,
          v_price);

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- --- Обучение --------------------------------------------------------------

create or replace function public.complete_level(
  p_pet_id uuid,
  p_category text,
  p_level smallint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid;
  v_done smallint;
  v_reward integer := coalesce((public.cfg('edu') ->> 'level_reward')::integer, 10);
begin
  select player_id into v_player from public.pets where id = p_pet_id;
  if v_player is null or v_player <> auth.uid() then
    raise exception 'Питомец % не принадлежит игроку', p_pet_id;
  end if;

  insert into public.edu_progress (player_id, category_id, levels_done, stars)
  values (v_player, p_category, 0, 0)
  on conflict (player_id, category_id) do nothing;

  select levels_done into v_done from public.edu_progress
  where player_id = v_player and category_id = p_category;

  -- Награда только за новый уровень: перепройти пройденное можно сколько
  -- угодно, но монеты за это второй раз не идут (КП 11.1 — ориентир
  -- 80–120 монет в день, а не сколько наберёшь повтором).
  if p_level >= v_done then
    update public.edu_progress set
      levels_done = least(10, v_done + 1),
      stars = stars + 1,
      updated_at = now()
    where player_id = v_player and category_id = p_category;

    perform public.grant_coins(p_pet_id, v_reward, 'edu:' || p_category);
    insert into public.care_events (pet_id, action) values (p_pet_id, 'learn');
  end if;

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- --- Полное состояние ------------------------------------------------------

-- Один запрос, которым приложение забирает всё своё состояние при старте
-- (КП 1.4). Отдельными запросами это было бы восемь обращений и восемь
-- поводов для рассинхрона.
create or replace function public.pet_snapshot(p_pet_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_player uuid;
  cur record;
  result jsonb;
begin
  select player_id into v_player from public.pets where id = p_pet_id;
  if v_player is null or v_player <> auth.uid() then
    raise exception 'Питомец % не принадлежит игроку', p_pet_id;
  end if;

  select * into cur from public.current_stats(p_pet_id);

  select jsonb_build_object(
    'server_time', now(),
    'pet', to_jsonb(p) - 'player_id',
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

-- --- Новый игрок -----------------------------------------------------------

-- Заводит профиль, питомца и стартовый набор сразу после регистрации.
-- Вход без регистрации (КП 1.2) означает, что аккаунт создаётся сам, и
-- пустой профиль игроку показывать нельзя.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet uuid;
  v_skin public.bear_skin;
begin
  insert into public.players (id) values (new.id);

  -- Пол определяет сервер (КП 2.4).
  v_skin := case when random() < 0.5 then 'boy' else 'girl' end;

  insert into public.pets (player_id, name, skin)
  values (new.id, 'Мой малыш', v_skin)
  returning id into v_pet;

  insert into public.pet_stats (pet_id) values (v_pet);
  insert into public.pet_outfit (pet_id) values (v_pet);

  -- Двенадцать бесплатных предметов на старте (КП 10.8).
  insert into public.inventory (player_id, item_id, source, price_paid)
  select new.id, item, 'free', 0
  from jsonb_array_elements_text(
    coalesce(public.cfg('starting_items'), '[]'::jsonb)) as item;

  -- Обои и пол ставятся сразу: без них комната не нарисуется. Мебель
  -- игрок расставляет сам — решение заказчика, герой в кадре один.
  insert into public.room_layout (player_id, item_id)
  select new.id, item
  from (values ('wall_rose'), ('floor_wood')) as v(item)
  where exists (select 1 from public.inventory i
                where i.player_id = new.id and i.item_id = v.item);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- --- История изменений настроек (КП 15.4) ----------------------------------

create or replace function public.log_config_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.config_history (key, old_value, new_value, changed_by)
  values (new.key,
          case when tg_op = 'UPDATE' then old.value else null end,
          new.value,
          auth.uid());
  new.updated_at := now();
  return new;
end;
$$;

create trigger game_config_audit
  before insert or update on public.game_config
  for each row execute function public.log_config_change();

-- --- Кому что можно вызывать -----------------------------------------------
--
-- `grant_coins` начисляет монеты и владения не проверяет: её зовут функции,
-- которые уже проверили. Оставить её открытой всё равно что вынести кассу
-- в зал — клиент вызвал бы её напрямую и выписал себе сколько угодно.

revoke execute on function public.grant_coins(uuid, integer, text)
  from public, anon, authenticated;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.log_config_change() from public, anon, authenticated;

grant execute on function public.pet_snapshot(uuid) to authenticated;
grant execute on function public.current_stats(uuid) to authenticated;
grant execute on function public.record_care(uuid, public.care_action) to authenticated;
grant execute on function public.buy_item(uuid, text) to authenticated;
grant execute on function public.complete_level(uuid, text, smallint) to authenticated;

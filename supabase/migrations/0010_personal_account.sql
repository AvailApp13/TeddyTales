-- Личный кабинет: у каждого пользователя свой аккаунт и один кошелёк.
--
-- Заказчик 24.09: «регистрировать пользователя на отдельный ID, чтобы к нему
-- привязывался счёт; общий кошелёк — еда и всё остальное списываются с
-- общего счёта пользователя».
--
-- Кто есть кто:
--   auth.users      — учётная запись Supabase. Создаётся сама при первом
--                     запуске, анонимно (КП 1.2). Вход через Apple, Google
--                     или почту привязывается к ней же (КП 1.3): тот же id,
--                     весь прогресс остаётся.
--   public.players  — личный кабинет: кошелёк, язык, возраст, тихие часы.
--                     Один к одному с auth.users.
--   public.pets     — мишка кабинета. Сейчас один, схема допускает больше.
--
-- Что меняется:
--   1. Монеты переезжают с мишки на кабинет (players.coins). Все списания и
--      начисления — одной функцией wallet_change с записью в coin_ledger.
--   2. Еда за монеты и приготовленные рецепты считаются на сервере
--      (feed_dish, complete_recipe). Цены и сытость — в game_config, их
--      правит панель (КП 15.4). Раньше еда списывалась только в телефоне.
--   3. open_account() — вход в кабинет при запуске: отмечает визит,
--      поднимает тестовый кошелёк до порога и отдаёт снимок.
--   4. Порог тестового кошелька — настройка test_wallet_floor (5000). Перед
--      публикацией поставить 0 (см. CLAUDE.md).
--   5. Имя: pets.named_at — дал ли человек имя на первом запуске (КП 2.3).
--   6. delete_my_account() — удалить аккаунт из приложения. Обязательно
--      для App Store, раз аккаунт создаётся в приложении (правило 5.1.1).
--   7. Сотрудники панели (по приглашению) при регистрации не получают
--      кабинет с мишкой.
--   8. rename_pet больше нельзя вызвать без входа (замечание проверки
--      безопасности Supabase).

-- --- 1. Кошелёк на кабинете -------------------------------------------------

alter table public.players
  add column if not exists coins integer not null default 0
  check (coins >= 0);

comment on column public.players.coins is
  'Кошелёк пользователя (КП 11.1). Меняется только wallet_change.';

update public.players pl
set coins = coalesce((select sum(p.coins) from public.pets p
                      where p.player_id = pl.id), 0);

alter table public.pets drop column if exists coins;

-- Единственный путь изменить баланс. Не пускает в минус: при нехватке
-- бросает ошибку с кодом TT402, который приложение переводит в «не хватает
-- монет».
create or replace function public.wallet_change(
  p_player uuid,
  p_amount integer,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
begin
  if p_amount = 0 then
    select coins into v_balance from public.players where id = p_player;
    return v_balance;
  end if;

  update public.players
  set coins = coins + p_amount
  where id = p_player and coins + p_amount >= 0
  returning coins into v_balance;

  if v_balance is null then
    if not exists (select 1 from public.players where id = p_player) then
      raise exception 'Нет кабинета %', p_player using errcode = 'TT404';
    end if;
    raise exception 'Не хватает монет' using errcode = 'TT402';
  end if;

  insert into public.coin_ledger (player_id, amount, reason)
  values (p_player, p_amount, p_reason);
  return v_balance;
end;
$$;

-- Прежняя функция начисляла на мишку. Её заменяет wallet_change.
drop function if exists public.grant_coins(uuid, integer, text);

-- Хозяин мишки или ошибка TT403. Общая проверка для всех действий.
create or replace function public.pet_owner(p_pet_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_player uuid;
begin
  select player_id into v_player from public.pets where id = p_pet_id;
  if v_player is null or v_player is distinct from auth.uid() then
    raise exception 'Питомец % не принадлежит игроку', p_pet_id
      using errcode = 'TT403';
  end if;
  return v_player;
end;
$$;

-- --- 2. Имя на первом запуске -------------------------------------------------

alter table public.pets add column if not exists named_at timestamptz;

comment on column public.pets.named_at is
  'Когда человек дал имя (КП 2.3). NULL — ещё не давал, приложение спросит.';

-- --- 3. Настройки ---------------------------------------------------------------

insert into public.game_config (key, value) values
  ('test_wallet_floor', '5000'::jsonb),
  ('dishes', '{
    "porridge": {"price": 5,  "food": 20},
    "soup":     {"price": 8,  "food": 28},
    "sandwich": {"price": 7,  "food": 25},
    "fruit":    {"price": 6,  "food": 18},
    "yogurt":   {"price": 5,  "food": 16},
    "cookie":   {"price": 5,  "food": 12},
    "salad":    {"price": 9,  "food": 22},
    "pasta":    {"price": 12, "food": 35},
    "omelette": {"price": 10, "food": 30},
    "pie":      {"price": 15, "food": 40}
  }'::jsonb),
  ('recipes', '{
    "cookie":      {"reward": 8,  "food": 14},
    "sandwich":    {"reward": 9,  "food": 26},
    "fruit_salad": {"reward": 14, "food": 24},
    "meat":        {"reward": 20, "food": 38},
    "veggie":      {"reward": 18, "food": 32}
  }'::jsonb)
on conflict (key) do nothing;

-- --- 4. Снимок кабинета ---------------------------------------------------------

create or replace function public.pet_snapshot(p_pet_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  cur record;
  result jsonb;
begin
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
        'is_anonymous', coalesce(u.is_anonymous, false),
        'email', u.email,
        'providers', coalesce(
          (select jsonb_agg(distinct i.provider) from auth.identities i
           where i.user_id = pl.id), '[]'::jsonb)
      )
      from public.players pl
      left join auth.users u on u.id = pl.id
      where pl.id = v_player
    ),
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

-- Вход в кабинет при запуске приложения. Находит мишку того, кто вошёл,
-- отмечает визит, поднимает тестовый кошелёк до порога и отдаёт снимок.
-- Мишки нет (регистрация прошла без триггера) — ошибка TT404.
create or replace function public.open_account()
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

  update public.players set last_seen_at = now()
  where id = v_player
  returning coins into v_coins;

  -- Испытания: при каждом входе поднять до порога. Разница идёт по книге
  -- операций с пометкой test_floor, чтобы её было видно в отчётах.
  if v_floor > 0 and v_coins < v_floor then
    perform public.wallet_change(v_player, v_floor - v_coins, 'test_floor');
  end if;

  return public.pet_snapshot(v_pet);
end;
$$;

-- --- 5. Действия через кошелёк кабинета -----------------------------------------

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
  cur record;
  bonus real := 0;
  coins integer := 0;
begin
  bonus := coalesce((gain ->> p_action::text)::real, 0);
  coins := coalesce((rewards ->> p_action::text)::integer, 0);

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
    perform public.wallet_change(v_player, coins, 'care:' || p_action::text);
  end if;

  return public.pet_snapshot(p_pet_id);
end;
$$;

create or replace function public.buy_item(p_pet_id uuid, p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  v_price integer;
begin
  v_price := (public.cfg('item_prices') ->> p_item_id)::integer;
  if v_price is null then
    raise exception 'Нет цены для предмета %', p_item_id using errcode = 'TT404';
  end if;

  if exists (select 1 from public.inventory
             where player_id = v_player and item_id = p_item_id) then
    raise exception 'Предмет % уже куплен', p_item_id using errcode = 'TT409';
  end if;

  if v_price > 0 then
    perform public.wallet_change(v_player, -v_price, 'buy:' || p_item_id);
  end if;

  insert into public.inventory (player_id, item_id, source, price_paid)
  values (v_player, p_item_id,
          case when v_price = 0 then 'free'::public.item_source
               else 'coins'::public.item_source end,
          v_price);

  return public.pet_snapshot(p_pet_id);
end;
$$;

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
  v_player uuid := public.pet_owner(p_pet_id);
  v_done smallint;
  v_reward integer := coalesce((public.cfg('edu') ->> 'level_reward')::integer, 10);
begin
  insert into public.edu_progress (player_id, category_id, levels_done, stars)
  values (v_player, p_category, 0, 0)
  on conflict (player_id, category_id) do nothing;

  select levels_done into v_done from public.edu_progress
  where player_id = v_player and category_id = p_category;

  if p_level >= v_done then
    update public.edu_progress set
      levels_done = least(10, v_done + 1),
      stars = stars + 1,
      updated_at = now()
    where player_id = v_player and category_id = p_category;
    perform public.wallet_change(v_player, v_reward, 'edu:' || p_category);
    insert into public.care_events (pet_id, action) values (p_pet_id, 'learn');
  end if;

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Поднять сытость на p_food и отметить кормление. Общая часть еды за монеты
-- и приготовленного рецепта.
create or replace function public.feed_pet(p_pet_id uuid, p_food real)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur record;
begin
  select * into cur from public.current_stats(p_pet_id);
  update public.pet_stats set
    food = least(100, cur.food + greatest(p_food, 0)),
    hygiene = cur.hygiene,
    sleep = cur.sleep,
    play = cur.play,
    love = cur.love,
    measured_at = cur.at_time
  where pet_id = p_pet_id;
  insert into public.care_events (pet_id, action) values (p_pet_id, 'feed');
end;
$$;

-- Готовое блюдо за монеты (КП 8.2). Цена и сытость — из настроек dishes.
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
  v_price := coalesce((v_dish ->> 'price')::integer, 0);

  if v_price > 0 then
    perform public.wallet_change(v_player, -v_price, 'dish:' || p_dish_id);
  end if;
  perform public.feed_pet(p_pet_id, coalesce((v_dish ->> 'food')::real, 0));

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- Приготовленный рецепт (КП 8.4): награда и сытость — из настроек recipes.
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
  v_reward := coalesce((v_recipe ->> 'reward')::integer, 0);

  if v_reward > 0 then
    perform public.wallet_change(v_player, v_reward, 'recipe:' || p_recipe_id);
  end if;
  perform public.feed_pet(p_pet_id, coalesce((v_recipe ->> 'food')::real, 0));

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- --- 6. Имя --------------------------------------------------------------------

create or replace function public.rename_pet(
  p_pet_id uuid,
  p_name text,
  p_locale text default 'ru'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_len integer;
  v_hit text;
begin
  perform public.pet_owner(p_pet_id);

  v_name := regexp_replace(btrim(p_name), '\s+', ' ', 'g');
  v_len := char_length(v_name);

  if v_len < 2 then
    raise exception 'Имя короче двух знаков' using errcode = 'check_violation';
  end if;
  if v_len > 15 then
    raise exception 'Имя длиннее пятнадцати знаков'
      using errcode = 'check_violation';
  end if;

  select b.pattern into v_hit
  from public.name_blocklist b
  where lower(v_name) like '%' || lower(b.pattern) || '%'
     or lower(regexp_replace(v_name, '[\s''\-]', '', 'g'))
        like '%' || lower(b.pattern) || '%'
  limit 1;

  if v_hit is not null then
    insert into public.name_moderation (pet_id, name, locale, status)
    values (p_pet_id, v_name, p_locale, 'rejected');
    raise exception 'Имя содержит запрещённое слово'
      using errcode = 'check_violation';
  end if;

  update public.pets
  set name = v_name,
      name_status = 'pending',
      named_at = coalesce(named_at, now())
  where id = p_pet_id;

  insert into public.name_moderation (pet_id, name, locale, status)
  values (p_pet_id, v_name, p_locale, 'pending');

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- --- 7. Удалить аккаунт ---------------------------------------------------------

-- Удаляет учётную запись того, кто вошёл. Кабинет, мишка, покупки и
-- история уходят каскадом. Требование App Store 5.1.1(v).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Нет входа' using errcode = 'TT401';
  end if;
  delete from auth.users where id = v_user;
end;
$$;

-- --- 8. Регистрация: кабинет с мишкой, кошелёк на кабинете -----------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet uuid;
  v_skin public.bear_skin;
  v_coins integer;
begin
  -- Сотрудник панели по приглашению — не игрок: ему не нужен ни кабинет,
  -- ни мишка. Роль выдаёт соседний триггер on_auth_user_staff.
  if new.email is not null and exists (
    select 1 from public.staff_invites where lower(email) = lower(new.email)
  ) then
    return new;
  end if;

  v_coins := coalesce((public.cfg('starting_coins'))::text::integer, 0);
  insert into public.players (id, coins) values (new.id, 0);

  -- Пол определяет сервер (КП 2.4).
  v_skin := case when random() < 0.5 then 'boy' else 'girl' end;
  insert into public.pets (player_id, name, skin)
  values (new.id, 'Мой малыш', v_skin)
  returning id into v_pet;

  insert into public.pet_stats (pet_id) values (v_pet);
  insert into public.pet_outfit (pet_id) values (v_pet);

  -- Стартовые монеты — через книгу операций, как любые другие.
  if v_coins > 0 then
    perform public.wallet_change(new.id, v_coins, 'welcome');
  end if;

  -- Двенадцать бесплатных предметов на старте (КП 10.8).
  insert into public.inventory (player_id, item_id, source, price_paid)
  select new.id, item, 'free', 0
  from jsonb_array_elements_text(
    coalesce(public.cfg('starting_items'), '[]'::jsonb)) as item;

  -- Обои и пол ставятся сразу: без них комната не нарисуется.
  insert into public.room_layout (player_id, item_id)
  select new.id, item
  from (values ('wall_rose'), ('floor_wood')) as v(item)
  where exists (select 1 from public.inventory i
                where i.player_id = new.id and i.item_id = v.item);

  return new;
end;
$$;

-- --- 9. Панель: монеты теперь на кабинетах ------------------------------------------

create or replace function public.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff('admin') then
    raise exception 'Доступ только для администратора';
  end if;

  return jsonb_build_object(
    'players', (select count(*) from public.players),
    'pets', (select count(*) from public.pets),
    'players_today', (
      select count(*) from public.players
      where created_at >= now() - interval '24 hours'),
    'active_today', (
      select count(distinct p.player_id) from public.pets p
      join public.care_events c on c.pet_id = p.id
      where c.happened_at >= now() - interval '24 hours'),
    'coins_total', (select coalesce(sum(coins), 0) from public.players),
    -- Тестовая добавка до порога — не заработок, её в отчёт не берём.
    'coins_earned_today', (
      select coalesce(sum(amount), 0) from public.coin_ledger
      where amount > 0 and reason <> 'test_floor'
        and happened_at >= now() - interval '24 hours'),
    'purchases_total', (
      select count(*) from public.purchases where status = 'verified'),
    'names_pending', (
      select count(*) from public.name_moderation where status = 'pending'),
    'by_stage', (
      select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb)
      from (select stage::text as stage, count(*) as n
            from public.pets group by stage) s),
    'server_time', now()
  );
end;
$$;

-- --- 10. Права ---------------------------------------------------------------------

-- Внутренние: только из других функций.
revoke execute on function public.wallet_change(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.pet_owner(uuid) from public, anon, authenticated;
revoke execute on function public.feed_pet(uuid, real) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Для приложения: только после входа.
revoke execute on function public.pet_snapshot(uuid) from public, anon;
revoke execute on function public.open_account() from public, anon;
revoke execute on function public.record_care(uuid, public.care_action) from public, anon;
revoke execute on function public.buy_item(uuid, text) from public, anon;
revoke execute on function public.complete_level(uuid, text, smallint) from public, anon;
revoke execute on function public.feed_dish(uuid, text) from public, anon;
revoke execute on function public.complete_recipe(uuid, text) from public, anon;
revoke execute on function public.rename_pet(uuid, text, text) from public, anon;
revoke execute on function public.delete_my_account() from public, anon;

grant execute on function public.pet_snapshot(uuid) to authenticated;
grant execute on function public.open_account() to authenticated;
grant execute on function public.record_care(uuid, public.care_action) to authenticated;
grant execute on function public.buy_item(uuid, text) to authenticated;
grant execute on function public.complete_level(uuid, text, smallint) to authenticated;
grant execute on function public.feed_dish(uuid, text) to authenticated;
grant execute on function public.complete_recipe(uuid, text) to authenticated;
grant execute on function public.rename_pet(uuid, text, text) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

-- Кошелёк клиент читает, но не пишет: политика players_update пускала бы
-- человека переписать себе монеты. Разрешаем обновлять только настройки.
revoke update on public.players from anon, authenticated;
grant update (locale, player_age, quiet_hours) on public.players to authenticated;
revoke insert on public.players from anon, authenticated;

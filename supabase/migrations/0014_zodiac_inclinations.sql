-- 0014: склонности характера по знакам зодиака (КП 7.2).
--
-- КП: «Двенадцать знаков зодиака задают стартовые склонности» — по таблице
-- Заказчика. Таблицы пока нет, поэтому механика ставится с нулями: знак
-- ни на что не влияет, пока Заказчик не впишет числа в панели управления
-- (раздел «Знаки зодиака»). Правки сразу действуют и попадают в историю —
-- таблица живёт в game_config, где история уже ведётся триггером (КП 15.4).
--
-- Формат: {знак: {черта: добавка}}. Добавка — к нормализованному счёту
-- черты 0–1, осмысленно 0–0,3 (см. lib/bear/bear_zodiac.dart): склонность
-- смещает характер, но не перебивает действия игрока (КП 7.3).
--
-- Где действует:
--   * при рождении — стартовый характер = черта с наибольшей добавкой знака
--     (если все нули — «активный», как раньше);
--   * в приложении — снимок отдаёт склонности своего знака, и они
--     добавляются к счёту, когда характер пересчитывается из действий.

insert into public.game_config (key, value)
values ('zodiac_inclinations', '{"aries": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "taurus": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "gemini": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "cancer": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "leo": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "virgo": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "libra": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "scorpio": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "sagittarius": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "capricorn": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "aquarius": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}, "pisces": {"active": 0, "curious": 0, "affectionate": 0, "calm": 0, "independent": 0, "reserved": 0}}'::jsonb)
on conflict (key) do nothing;

-- Черта с наибольшей положительной добавкой для знака; null — таблица
-- пустая или все нули.
create or replace function public.starting_trait(p_zodiac public.bear_zodiac)
returns public.bear_trait
language sql
stable
security definer
set search_path = public
as $$
  select t.key::public.bear_trait
  from jsonb_each(coalesce(
         public.cfg('zodiac_inclinations') -> (p_zodiac::text), '{}'::jsonb)) t
  where jsonb_typeof(t.value) = 'number'
    and (t.value)::text::numeric > 0
    and t.key in ('active', 'curious', 'affectionate', 'calm',
                  'independent', 'reserved')
  order by (t.value)::text::numeric desc, t.key
  limit 1;
$$;

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
  v_born timestamptz := now();
  v_zodiac public.bear_zodiac;
  v_size record;
  v_trait public.bear_trait;
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

  -- Мишка рождается в день регистрации, знак — по дате у человека.
  v_zodiac := public.zodiac_for(
    public.local_date(v_born, coalesce(new.raw_user_meta_data, '{}'::jsonb)));

  -- Пол, рост и вес определяет сервер (КП 2.2, 2.4).
  v_skin := case when random() < 0.5 then 'boy' else 'girl' end;
  select * into v_size from public.birth_size();
  -- Стартовый характер — самая сильная склонность знака (КП 7.2).
  v_trait := coalesce(public.starting_trait(v_zodiac), 'active');
  insert into public.pets
    (player_id, name, skin, birth_at, zodiac, birth_height_cm, birth_weight_g,
     trait)
  values
    (new.id, 'Мой малыш', v_skin, v_born, v_zodiac,
     v_size.height_cm, v_size.weight_g, v_trait)
  returning id into v_pet;

  insert into public.pet_stats (pet_id) values (v_pet);
  insert into public.pet_outfit (pet_id) values (v_pet);

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
    -- Склонности своего знака (КП 7.2): приложение добавляет их к счёту
    -- черт, когда характер пересчитывается из действий (КП 7.3).
    'zodiac_inclinations', coalesce(
      public.cfg('zodiac_inclinations') -> (p.zodiac::text), '{}'::jsonb),
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


revoke execute on function public.starting_trait(public.bear_zodiac) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.pet_snapshot(uuid) from public, anon;
grant execute on function public.pet_snapshot(uuid) to authenticated;

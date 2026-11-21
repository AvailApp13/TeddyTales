-- Знаки зодиака и день рождения мишки — день регистрации.
--
-- Заказчик 24.09: «в базу внести полностью все знаки зодиака… в день его
-- рождения — это тогда, когда человек регистрируется — ему должна быть
-- привязка. Это всё должно отображаться в личном кабинете».
--
-- Раньше знак по КП 2.5 собирались считать по игровому календарю и при
-- регистрации не ставили вовсе (pets.zodiac был пуст). Теперь:
--   * справочник zodiac_signs — 12 знаков с датами, названиями на трёх
--     языках, символом и стихией; правится из панели, если понадобится;
--   * мишка рождается в момент регистрации (pets.birth_at = now()), знак —
--     по календарной дате этого дня у человека: приложение присылает свой
--     часовой пояс в метаданных регистрации (tz_offset_min), иначе UTC;
--   * у уже заведённых мишек знак проставляется по их дате рождения.
-- Стартовые склонности характера по знаку — позже, по таблице заказчика.

create table if not exists public.zodiac_signs (
  id public.bear_zodiac primary key,
  sort smallint not null unique,
  start_month smallint not null check (start_month between 1 and 12),
  start_day smallint not null check (start_day between 1 and 31),
  end_month smallint not null check (end_month between 1 and 12),
  end_day smallint not null check (end_day between 1 and 31),
  symbol text not null,
  element text not null check (element in ('fire', 'earth', 'air', 'water')),
  name_ru text not null,
  name_en text not null,
  name_zh text not null
);

comment on table public.zodiac_signs is
  'Двенадцать знаков зодиака: даты (включительно), названия ru/en/zh, стихия.';

insert into public.zodiac_signs
  (id, sort, start_month, start_day, end_month, end_day, symbol, element,
   name_ru, name_en, name_zh)
values
  ('aries',        1,  3, 21,  4, 19, '♈', 'fire',  'Овен',     'Aries',       '白羊座'),
  ('taurus',       2,  4, 20,  5, 20, '♉', 'earth', 'Телец',    'Taurus',      '金牛座'),
  ('gemini',       3,  5, 21,  6, 20, '♊', 'air',   'Близнецы', 'Gemini',      '双子座'),
  ('cancer',       4,  6, 21,  7, 22, '♋', 'water', 'Рак',      'Cancer',      '巨蟹座'),
  ('leo',          5,  7, 23,  8, 22, '♌', 'fire',  'Лев',      'Leo',         '狮子座'),
  ('virgo',        6,  8, 23,  9, 22, '♍', 'earth', 'Дева',     'Virgo',       '处女座'),
  ('libra',        7,  9, 23, 10, 22, '♎', 'air',   'Весы',     'Libra',       '天秤座'),
  ('scorpio',      8, 10, 23, 11, 21, '♏', 'water', 'Скорпион', 'Scorpio',     '天蝎座'),
  ('sagittarius',  9, 11, 22, 12, 21, '♐', 'fire',  'Стрелец',  'Sagittarius', '射手座'),
  ('capricorn',   10, 12, 22,  1, 19, '♑', 'earth', 'Козерог',  'Capricorn',   '摩羯座'),
  ('aquarius',    11,  1, 20,  2, 18, '♒', 'air',   'Водолей',  'Aquarius',    '水瓶座'),
  ('pisces',      12,  2, 19,  3, 20, '♓', 'water', 'Рыбы',     'Pisces',      '双鱼座')
on conflict (id) do nothing;

-- Справочник открыт на чтение всем: в нём нет ничего личного.
alter table public.zodiac_signs enable row level security;
drop policy if exists zodiac_signs_read on public.zodiac_signs;
create policy zodiac_signs_read on public.zodiac_signs
  for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.zodiac_signs from anon, authenticated;

-- Знак по календарной дате. Козерог переходит через Новый год — у него
-- начало больше конца, поэтому два вида сравнения.
create or replace function public.zodiac_for(p_date date)
returns public.bear_zodiac
language sql
stable
set search_path = public
as $$
  select z.id
  from public.zodiac_signs z,
       lateral (select extract(month from p_date)::int * 100
                       + extract(day from p_date)::int as md) d
  where case
          when z.start_month * 100 + z.start_day <= z.end_month * 100 + z.end_day
            then d.md between z.start_month * 100 + z.start_day
                          and z.end_month * 100 + z.end_day
          else d.md >= z.start_month * 100 + z.start_day
            or d.md <= z.end_month * 100 + z.end_day
        end
  order by z.sort
  limit 1
$$;

-- Дата у человека: сдвиг его пояса в минутах из метаданных регистрации.
-- Мусор и нелепые значения — UTC: знак важнее угадать почти всегда, чем
-- уронить регистрацию из-за кривого поля.
create or replace function public.local_date(p_at timestamptz, p_meta jsonb)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v_offset integer;
begin
  begin
    v_offset := (p_meta ->> 'tz_offset_min')::integer;
  exception when others then
    v_offset := null;
  end;
  if v_offset is null or v_offset not between -840 and 840 then
    v_offset := 0;
  end if;
  return ((p_at at time zone 'UTC') + make_interval(mins => v_offset))::date;
end;
$$;

-- У уже заведённых мишек знак по дню рождения (UTC).
update public.pets
set zodiac = public.zodiac_for((birth_at at time zone 'UTC')::date)
where zodiac is null;

-- Регистрация: как в 0010, плюс день рождения и знак.
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

  -- Пол определяет сервер (КП 2.4).
  v_skin := case when random() < 0.5 then 'boy' else 'girl' end;
  insert into public.pets (player_id, name, skin, birth_at, zodiac)
  values (new.id, 'Мой малыш', v_skin, v_born, v_zodiac)
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

-- Снимок: в кабинете — дата регистрации, подтверждена ли почта и знак
-- целиком (символ, стихия, названия), чтобы профиль показал его без
-- второго запроса.
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

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.local_date(timestamptz, jsonb) from public, anon, authenticated;
revoke execute on function public.pet_snapshot(uuid) from public, anon;
grant execute on function public.pet_snapshot(uuid) to authenticated;
grant execute on function public.zodiac_for(date) to anon, authenticated;

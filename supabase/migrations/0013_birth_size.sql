-- 0013: рост и вес при рождении (КП 2.2).
--
-- До этого в карточке рождения стояли одинаковые «15 см» и «180 г» с
-- пометкой «заглушка». Решение заказчика 25.09: сервер назначает их при
-- рождении случайно в диапазоне — рост 14,0–17,0 см, вес 160–210 г, — как у
-- «Карманного мишки» из каталога; дальше они растут по стадиям, но это
-- считает клиент от этих двух чисел (lib/game/pet_profile.dart).
--
-- pet_snapshot() отдаёт мишку целиком (`to_jsonb(p)`), поэтому новые
-- столбцы попадают в ответ сами.

alter table public.pets
  add column if not exists birth_height_cm real
    check (birth_height_cm between 10 and 30),
  add column if not exists birth_weight_g real
    check (birth_weight_g between 100 and 400);

comment on column public.pets.birth_height_cm is
  'Рост при рождении, см (КП 2.2). Назначает сервер при рождении.';
comment on column public.pets.birth_weight_g is
  'Вес при рождении, г (КП 2.2). Назначает сервер при рождении.';

-- Размеры новорождённого. Рост с одним знаком после запятой, вес целый.
create or replace function public.birth_size(out height_cm real, out weight_g real)
language sql
volatile
as $$
  select round((14 + random() * 3)::numeric, 1)::real,
         round((160 + random() * 50)::numeric)::real;
$$;

-- Уже рождённым — тоже свои числа, чтобы карточки не остались пустыми.
update public.pets p
set (birth_height_cm, birth_weight_g) = (select * from public.birth_size())
where p.birth_height_cm is null or p.birth_weight_g is null;

-- Рождение: к полу и знаку добавились рост и вес.
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
  insert into public.pets
    (player_id, name, skin, birth_at, zodiac, birth_height_cm, birth_weight_g)
  values
    (new.id, 'Мой малыш', v_skin, v_born, v_zodiac,
     v_size.height_cm, v_size.weight_g)
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

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.birth_size() from public, anon, authenticated;

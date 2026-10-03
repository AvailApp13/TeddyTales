-- 0015: мишка взрослеет сам (КП 5.6, 5.7, 6.2).
--
-- Длительности стадий лежали в game_config.stage_durations с 0004, но
-- переход нигде не происходил: стадия менялась только кнопкой «Подрасти» в
-- приложении, а сервер про неё не знал. Теперь сервер ведёт рост сам:
--
--   * у мишки копятся «часы роста» (pets.growth_hours) с момента
--     pets.growth_at;
--   * скорость — от общего ухода (КП 5.7, «не от одного показателя»):
--     среднее пяти показателей на прошлой и нынешней проверке. Ухоженный
--     растёт ×1,0, запущенный — ×0,5 (КП 6.2: «медленнее растёт», но не
--     останавливается). Концы правятся в панели: game_config.growth_speed;
--   * набралось часов на стадию (stage_durations, часы) — переход,
--     лишнее переносится на следующую; stage_changed_at = сейчас.
--
-- Считается при каждом снимке (pet_snapshot), то есть при входе и после
-- любого действия. Часы — серверные (КП 1.5): перевод часов на телефоне
-- ничего не ускоряет.

alter table public.pets
  add column if not exists growth_hours real not null default 0
    check (growth_hours >= 0),
  add column if not exists growth_at timestamptz not null default now(),
  add column if not exists growth_care real
    check (growth_care between 0 and 100);

comment on column public.pets.growth_hours is
  'Накопленные часы роста на текущей стадии (КП 5.6, 5.7).';
comment on column public.pets.growth_at is
  'Момент, до которого часы роста уже посчитаны.';
comment on column public.pets.growth_care is
  'Средний уход (0–100) на момент growth_at — для скорости роста.';

-- Уже живущим мишкам — сколько они прожили на своей стадии.
update public.pets
set growth_hours = greatest(0, extract(epoch from (now() - stage_changed_at)) / 3600.0),
    growth_at = now()
where growth_hours = 0;

insert into public.game_config (key, value)
values ('growth_speed', '{"neglected": 0.5, "cared": 1.0}'::jsonb)
on conflict (key) do nothing;

-- Скорость роста при среднем уходе p_care (0–100). Ниже безопасного
-- предела показатели не падают (КП 6.3), поэтому шкала — от предела до 100.
create or replace function public.growth_speed(p_care real)
returns double precision
language sql
stable
security definer
set search_path = public
as $$
  with c as (
    select coalesce((public.cfg('growth_speed') ->> 'neglected')::double precision, 0.5) as lo,
           coalesce((public.cfg('growth_speed') ->> 'cared')::double precision, 1.0) as hi,
           coalesce((public.cfg('decay') ->> 'floor')::double precision, 20) as fl
  )
  select c.lo + (c.hi - c.lo)
         * least(1, greatest(0, (coalesce(p_care, 100) - c.fl) / nullif(100 - c.fl, 0)))
  from c;
$$;

-- Следующая стадия; для взрослого — null.
create or replace function public.next_stage(p_stage public.bear_stage)
returns public.bear_stage
language sql
immutable
as $$
  select case p_stage
    when 'newborn' then 'crawling'::public.bear_stage
    when 'crawling' then 'firstSteps'::public.bear_stage
    when 'firstSteps' then 'growing'::public.bear_stage
    when 'growing' then 'adult'::public.bear_stage
    else null
  end;
$$;

-- Дорастить мишку до «сейчас». Возвращает стадию после расчёта.
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
begin
  select * into p from public.pets where id = p_pet_id for update;
  if not found then
    return null;
  end if;

  select * into cur from public.current_stats(p_pet_id);
  v_care := (cur.food + cur.hygiene + cur.sleep + cur.play + cur.love) / 5.0;

  -- Средняя скорость за промежуток: по уходу в его начале и конце.
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
  end loop;

  -- Взрослому копить нечего.
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

-- Прогноз: доля пройденной стадии и когда ждать следующую при нынешнем
-- уходе. Для взрослого — пусто.
create or replace function public.growth_outlook(p_pet_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p public.pets%rowtype;
  v_need double precision;
  v_speed double precision;
begin
  select * into p from public.pets where id = p_pet_id;
  if not found or public.next_stage(p.stage) is null then
    return '{}'::jsonb;
  end if;
  v_need := (public.cfg('stage_durations') ->> p.stage::text)::double precision;
  if v_need is null or v_need <= 0 then
    return '{}'::jsonb;
  end if;
  v_speed := greatest(public.growth_speed(p.growth_care), 0.01);
  return jsonb_build_object(
    'progress', least(1, p.growth_hours / v_need),
    'next_stage', public.next_stage(p.stage),
    'next_stage_at', p.growth_at
      + make_interval(secs => greatest(0, v_need - p.growth_hours) / v_speed * 3600)
  );
end;
$$;

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
  -- Сначала мишка дорастает до «сейчас» (КП 5.6, 5.7): любой ответ сервера
  -- — вход, действие, покупка — показывает уже верную стадию.
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
    -- Склонности своего знака (КП 7.2): приложение добавляет их к счёту
    -- черт, когда характер пересчитывается из действий (КП 7.3).
    'zodiac_inclinations', coalesce(
      public.cfg('zodiac_inclinations') -> (p.zodiac::text), '{}'::jsonb),
    -- Когда ждать следующую стадию — для уведомления «Новая стадия»
    -- (КП 13.1) и полоски в «Росте и развитии».
    'growth', public.growth_outlook(p.id),
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


revoke execute on function public.growth_speed(real) from public, anon, authenticated;
revoke execute on function public.advance_growth(uuid) from public, anon, authenticated;
revoke execute on function public.growth_outlook(uuid) from public, anon, authenticated;
revoke execute on function public.pet_snapshot(uuid) from public, anon;
grant execute on function public.pet_snapshot(uuid) to authenticated;

-- Самопроверка: не сошлось — миграция откатывается целиком.
do $$
begin
  if abs(public.growth_speed(100) - 1.0) > 1e-6
     or abs(public.growth_speed(20) - 0.5) > 1e-6
     or abs(public.growth_speed(60) - 0.75) > 1e-6 then
    raise exception 'growth_speed: неверная шкала';
  end if;
  if public.next_stage('newborn') <> 'crawling'
     or public.next_stage('growing') <> 'adult'
     or public.next_stage('adult') is not null then
    raise exception 'next_stage: неверная цепочка';
  end if;
end;
$$;

-- Проверка миграции 0011: знаки зодиака и день рождения при регистрации.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

-- Справочник: 12 знаков, каждый день года (и 29 февраля) — ровно один знак.
do $$
declare
  d date;
  n integer;
begin
  assert (select count(*) from public.zodiac_signs) = 12, 'двенадцать знаков';
  assert (select count(*) from public.zodiac_signs
          where name_ru <> '' and name_en <> '' and name_zh <> '' and symbol <> '') = 12,
         'названия на трёх языках и символ';
  for d in select generate_series('2024-01-01'::date, '2024-12-31'::date, '1 day')::date loop
    select count(*) into n from public.zodiac_signs z,
      lateral (select extract(month from d)::int * 100 + extract(day from d)::int as md) x
    where case when z.start_month * 100 + z.start_day <= z.end_month * 100 + z.end_day
               then x.md between z.start_month * 100 + z.start_day and z.end_month * 100 + z.end_day
               else x.md >= z.start_month * 100 + z.start_day or x.md <= z.end_month * 100 + z.end_day end;
    assert n = 1, format('%s попадает в %s знаков', d, n);
  end loop;
end $$;

-- Границы знаков.
do $$
begin
  assert public.zodiac_for('2026-03-20') = 'pisces', '20 марта — Рыбы';
  assert public.zodiac_for('2026-03-21') = 'aries', '21 марта — Овен';
  assert public.zodiac_for('2026-12-21') = 'sagittarius', '21 декабря — Стрелец';
  assert public.zodiac_for('2026-12-22') = 'capricorn', '22 декабря — Козерог';
  assert public.zodiac_for('2027-01-01') = 'capricorn', '1 января — Козерог';
  assert public.zodiac_for('2027-01-19') = 'capricorn', '19 января — Козерог';
  assert public.zodiac_for('2027-01-20') = 'aquarius', '20 января — Водолей';
  assert public.zodiac_for('2028-02-29') = 'pisces', '29 февраля — Рыбы';
  assert public.zodiac_for('2026-09-24') = 'libra', '24 сентября — Весы';
  assert public.zodiac_for('2026-09-22') = 'virgo', '22 сентября — Дева';
end $$;

-- Пояс человека: 22.09 23:30 UTC — в Пекине (+480) уже 23.09, Весы;
-- без пояса и с мусором — UTC, Дева.
do $$
begin
  assert public.zodiac_for(public.local_date('2026-09-22 23:30+00',
    '{"tz_offset_min": 480}')) = 'libra', 'Пекин — уже Весы';
  assert public.zodiac_for(public.local_date('2026-09-22 23:30+00',
    '{}')) = 'virgo', 'без пояса — UTC';
  assert public.zodiac_for(public.local_date('2026-09-22 23:30+00',
    '{"tz_offset_min": "abc"}')) = 'virgo', 'мусор — UTC';
  assert public.zodiac_for(public.local_date('2026-09-22 23:30+00',
    '{"tz_offset_min": 99999}')) = 'virgo', 'нелепый сдвиг — UTC';
  assert public.local_date('2026-09-23 02:00+00', '{"tz_offset_min": -300}')
    = '2026-09-22', 'Нью-Йорк — ещё 22-е';
end $$;

-- Регистрация по почте: кабинет, мишка родился сейчас, знак сегодняшнего дня.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'mama@example.test', '{"tz_offset_min": 180}');
insert into auth.identities (user_id, provider, provider_id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'email', '00000000-0000-0000-0000-0000000000e1',
   'mama@example.test');

do $$
declare
  p record;
begin
  select * into p from public.pets where player_id = '00000000-0000-0000-0000-0000000000e1';
  assert p.id is not null, 'мишка заведён';
  assert p.birth_at > now() - interval '1 minute', 'родился в момент регистрации';
  assert p.zodiac = public.zodiac_for(((now() at time zone 'UTC') + interval '180 minutes')::date),
    format('знак дня регистрации, а не %s', p.zodiac);
  assert (select coins from public.players where id = '00000000-0000-0000-0000-0000000000e1') = 250,
    'стартовые монеты';
end $$;

-- Снимок от лица человека: почта, дата регистрации, знак целиком.
set role authenticated;
set app.uid = '00000000-0000-0000-0000-0000000000e1';
do $$
declare
  s jsonb := public.open_account();
begin
  assert s -> 'account' ->> 'email' = 'mama@example.test', 'почта в кабинете';
  assert s -> 'account' -> 'providers' ? 'email', 'способ входа — почта';
  assert (s -> 'account' ->> 'is_anonymous')::boolean = false, 'не анонимный';
  assert (s -> 'account' ->> 'email_confirmed')::boolean = false, 'почта не подтверждена';
  assert s -> 'account' ->> 'registered_at' is not null, 'дата регистрации';
  assert s -> 'zodiac' ->> 'id' = s -> 'pet' ->> 'zodiac', 'знак в снимке совпадает с мишкой';
  assert s -> 'zodiac' ->> 'name_ru' <> '', 'название знака';
  assert s -> 'zodiac' ->> 'symbol' <> '', 'символ знака';
end $$;

-- Справочник читают все, пишет никто.
do $$
begin
  assert (select count(*) from public.zodiac_signs) = 12, 'игрок видит знаки';
  begin
    update public.zodiac_signs set name_ru = 'x' where id = 'leo';
    raise exception 'игрок переписал справочник';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set role anon;
do $$
begin
  assert (select count(*) from public.zodiac_signs) = 12, 'гость видит знаки';
end $$;
reset role;

-- У всех мишек в базе знак проставлен.
do $$
begin
  assert not exists (select 1 from public.pets where zodiac is null), 'мишки без знака';
end $$;

select 'ALL 0011 CHECKS PASSED';

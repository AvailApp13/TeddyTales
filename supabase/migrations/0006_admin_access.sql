-- Роли панели управления (КП 15.7) и доступ, который они дают.
--
-- До сих пор настройки игры мог менять только сервер: политик на запись у
-- `game_config` не было вовсе. Для разработки это верно, но КП 15.4 требует,
-- чтобы экономику правил человек из панели — значит нужен способ отличить
-- этого человека от игрока.
--
-- Способ выбран простой: список сотрудников с ролями. Никаких «первый
-- вошедший становится администратором» — такой приём означает, что панель
-- достаётся тому, кто быстрее нажал.

create type public.staff_role as enum (
  -- Полный доступ: экономика, каталог, контент, модерация.
  'admin',
  -- Только заказы физических мишек (КП 15.2). Ни цен, ни экономики.
  'orders'
);

create table public.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role public.staff_role not null,
  added_at timestamptz not null default now()
);

comment on table public.staff is
  'Кто работает в панели управления (КП 15.7). Игроков здесь нет.';

-- Кого пускать, когда он зарегистрируется.
--
-- Сотрудника нельзя добавить в `staff` заранее: там ссылка на учётную
-- запись, а её ещё не существует. Поэтому доступ выдаётся авансом, по
-- адресу почты: человек регистрируется в панели этим адресом и получает
-- роль автоматически.
create table public.staff_invites (
  email text primary key,
  role public.staff_role not null,
  invited_at timestamptz not null default now()
);

comment on table public.staff_invites is
  'Заготовленный доступ по адресу почты. Пустая таблица = в панель не войти.';

-- --- Кто есть кто ----------------------------------------------------------

-- Проверка роли. Вынесена в функцию, потому что используется в каждой
-- политике ниже: одно место правки вместо десяти.
create or replace function public.is_staff(p_role public.staff_role default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.staff s
    where s.user_id = auth.uid()
      and (p_role is null or s.role = p_role)
  );
$$;

revoke execute on function public.is_staff(public.staff_role) from public, anon;
grant execute on function public.is_staff(public.staff_role) to authenticated;

-- Выдаёт роль при регистрации, если адрес был заранее приглашён.
--
-- Работает в том же триггере, что заводит игрока: сотрудник панели — это
-- обычная учётная запись, которой дополнительно выписана роль. Отдельной
-- ветки «сотрудник вместо игрока» нет намеренно: пусть у администратора
-- будет свой питомец, на котором он проверяет, что натворил в настройках.
create or replace function public.grant_staff_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.staff_role;
begin
  select role into v_role from public.staff_invites
  where lower(email) = lower(new.email);

  if v_role is not null then
    insert into public.staff (user_id, role) values (new.id, v_role)
    on conflict (user_id) do update set role = excluded.role;
  end if;

  return new;
end;
$$;

revoke execute on function public.grant_staff_role() from public, anon, authenticated;

create trigger on_auth_user_staff
  after insert on auth.users
  for each row execute function public.grant_staff_role();

-- --- Что панель может делать ----------------------------------------------

alter table public.staff enable row level security;
alter table public.staff_invites enable row level security;

-- Сотрудник видит свою строку: по ней панель понимает, что показывать.
create policy staff_read_self on public.staff
  for select using (user_id = (select auth.uid()));

-- Список приглашений — только администратору.
create policy staff_invites_admin on public.staff_invites
  for all using (public.is_staff('admin'))
  with check (public.is_staff('admin'));

-- Экономика и тайминги (КП 15.4). Читают все вошедшие — приложению нужны
-- скорости; меняет только администратор, и каждая правка попадает в историю
-- триггером, который уже стоит.
create policy game_config_write on public.game_config
  for all to authenticated
  using (public.is_staff('admin'))
  with check (public.is_staff('admin'));

-- История изменений (КП 15.4): администратор читает, но не правит — иначе
-- смысл истории теряется.
create policy config_history_read on public.config_history
  for select using (public.is_staff('admin'));

-- Модерация имён (КП 15.6).
create policy name_moderation_admin on public.name_moderation
  for all using (public.is_staff('admin'))
  with check (public.is_staff('admin'));

create policy name_blocklist_admin on public.name_blocklist
  for all using (public.is_staff('admin'))
  with check (public.is_staff('admin'));

-- --- Сводка для дашборда (КП 15.1) -----------------------------------------

-- Считает показатели одним запросом вместо десятка.
--
-- Отдельная функция, а не запросы из панели, по двум причинам. Первая:
-- построчная защита прячет от администратора чужих игроков — и правильно
-- делает, читать чужой прогресс ему незачем, а вот количество знать нужно.
-- Вторая: считать их по одному значит десять обращений на каждое открытие
-- страницы.
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
    'coins_total', (select coalesce(sum(coins), 0) from public.pets),
    'coins_earned_today', (
      select coalesce(sum(amount), 0) from public.coin_ledger
      where amount > 0 and happened_at >= now() - interval '24 hours'),
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

revoke execute on function public.admin_dashboard() from public, anon;
grant execute on function public.admin_dashboard() to authenticated;

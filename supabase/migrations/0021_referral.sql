-- 0021: «Пригласи друга» (сверх ТЗ, заказчик 25.09).
--
-- У каждого игрока свой код из шести знаков. Друг ставит приложение, мишка
-- у него рождается при регистрации, он вводит код (или открывает ссылку с
-- кодом) — обоим по referral.coins монет (100, решение заказчика).
--
-- Защита от накрутки: код принимает только новый аккаунт (не старше
-- referral.new_account_days дней), один раз; у одного пригласившего не
-- больше referral.max_invites друзей. Все числа — в панели, «Экономика».
-- referral.link — куда ведёт ссылка приглашения; пока веб-версия, после
-- выхода в App Store / Google Play — страница магазина.

insert into public.game_config (key, value)
values ('referral', jsonb_build_object(
  'coins', 100,
  'new_account_days', 7,
  'max_invites', 50,
  'link', 'https://availapp13.github.io/TeddyTales/'))
on conflict (key) do nothing;

alter table public.players add column if not exists ref_code text unique;

create table if not exists public.referrals (
  invitee uuid primary key references public.players (id) on delete cascade,
  inviter uuid not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists referrals_inviter on public.referrals (inviter);
comment on table public.referrals is
  'Кто кого пригласил. Пишут только функции redeem_referral / my_referral.';

-- Таблица только для функций: политик нет, клиент её не видит.
alter table public.referrals enable row level security;
revoke all on public.referrals from anon, authenticated;

-- Код игрока; нет — выдаётся. Без похожих знаков (0/O, 1/I/L).
create or replace function public.referral_code(p_player uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  select ref_code into v_code from public.players where id = p_player;
  if v_code is not null then
    return v_code;
  end if;
  loop
    select string_agg(substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1), '')
      into v_code
    from generate_series(1, 6);
    begin
      update public.players set ref_code = v_code
      where id = p_player and ref_code is null;
      exit;
    exception when unique_violation then
      -- Такой код уже у кого-то — берём другой.
    end;
  end loop;
  select ref_code into v_code from public.players where id = p_player;
  return v_code;
end;
$$;

-- Экран «Пригласи друга»: мой код, сколько друзей пришло, можно ли ещё
-- ввести чужой код.
create or replace function public.my_referral()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_created timestamptz;
begin
  if v_player is null then
    raise exception 'Нет входа' using errcode = 'TT401';
  end if;
  select created_at into v_created from public.players where id = v_player;
  if v_created is null then
    raise exception 'Нет кабинета' using errcode = 'TT404';
  end if;
  return jsonb_build_object(
    'code', public.referral_code(v_player),
    'invited', (select count(*) from public.referrals where inviter = v_player),
    'coins', public.cfg_num('referral', 'coins', 0)::integer,
    'link', coalesce(public.cfg('referral') ->> 'link', ''),
    'can_redeem',
      not exists (select 1 from public.referrals where invitee = v_player)
      and v_created > now() - make_interval(
        days => public.cfg_num('referral', 'new_account_days', 7)::integer));
end;
$$;

-- Ввести код друга. Отказы:
--   TT404 — такого кода нет;
--   TT403 — свой код;
--   TT409 — код уже вводили;
--   TT410 — аккаунт старше new_account_days;
--   TT429 — у друга уже max_invites приглашённых.
create or replace function public.redeem_referral(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_inviter uuid;
  v_created timestamptz;
  v_coins integer := public.cfg_num('referral', 'coins', 0)::integer;
  v_pet uuid;
begin
  if v_player is null then
    raise exception 'Нет входа' using errcode = 'TT401';
  end if;

  select id into v_inviter from public.players
  where ref_code = upper(btrim(coalesce(p_code, '')));
  if v_inviter is null then
    raise exception 'Нет такого кода' using errcode = 'TT404';
  end if;
  if v_inviter = v_player then
    raise exception 'Свой код' using errcode = 'TT403';
  end if;

  -- Одновременные попытки одного игрока не должны пройти обе.
  perform 1 from public.players where id = v_player for update;
  if exists (select 1 from public.referrals where invitee = v_player) then
    raise exception 'Код уже введён' using errcode = 'TT409';
  end if;

  select created_at into v_created from public.players where id = v_player;
  if v_created < now() - make_interval(
       days => public.cfg_num('referral', 'new_account_days', 7)::integer) then
    raise exception 'Код вводят только в первые дни' using errcode = 'TT410';
  end if;

  if (select count(*) from public.referrals where inviter = v_inviter)
     >= public.cfg_num('referral', 'max_invites', 50) then
    raise exception 'У друга больше нет приглашений' using errcode = 'TT429';
  end if;

  insert into public.referrals (invitee, inviter) values (v_player, v_inviter);
  if v_coins > 0 then
    perform public.wallet_change(v_player, v_coins, 'referral:invitee');
    perform public.wallet_change(v_inviter, v_coins, 'referral:inviter');
  end if;

  select id into v_pet from public.pets
  where player_id = v_player order by created_at limit 1;
  return public.pet_snapshot(v_pet);
end;
$$;

revoke execute on function public.referral_code(uuid) from public, anon, authenticated;
revoke execute on function public.my_referral() from public, anon;
revoke execute on function public.redeem_referral(text) from public, anon;
grant execute on function public.my_referral() to authenticated;
grant execute on function public.redeem_referral(text) to authenticated;

do $$
begin
  if public.cfg_num('referral', 'coins', 0) <> 100 then
    raise exception 'referral: нет награды';
  end if;
  if public.cfg('referral') ->> 'link' is null then
    raise exception 'referral: нет ссылки';
  end if;
end;
$$;

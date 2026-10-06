-- Push-уведомления с сервера (КП 13.1): «Событие» и «Новинки магазина»
-- знает только сервер. Остальные шесть типов телефон считает сам
-- (lib/notifications) и шлёт локально.
--
-- Устройство регистрирует свой адрес для push (токен APNs у iPhone, FCM у
-- Android) вместе с языком и включёнными типами — сервер шлёт только тем,
-- кто этот тип не выключил (КП 13.2).

create table if not exists public.push_tokens (
  token text primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')),
  locale text not null default 'ru' check (locale in ('ru', 'en', 'zh')),
  kinds text[] not null default '{}',
  updated_at timestamptz not null default now()
);

create index if not exists push_tokens_player_idx on public.push_tokens (player_id);

comment on table public.push_tokens is
  'Адреса устройств для push (КП 13.1). Пишет только register_push_token, читает функция send-push.';

-- Политик нет: таблица закрыта для приложения, работают только функции.
alter table public.push_tokens enable row level security;

create or replace function public.register_push_token(
  p_token text,
  p_platform text,
  p_locale text default 'ru',
  p_kinds text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  if coalesce(length(p_token), 0) < 16 then
    raise exception 'bad_token';
  end if;
  insert into public.push_tokens (token, player_id, platform, locale, kinds, updated_at)
  values (
    p_token, auth.uid(), p_platform,
    case when p_locale in ('ru', 'en', 'zh') then p_locale else 'ru' end,
    coalesce(p_kinds, '{}'), now()
  )
  on conflict (token) do update
    set player_id = excluded.player_id,
        platform = excluded.platform,
        locale = excluded.locale,
        kinds = excluded.kinds,
        updated_at = now();
end;
$$;

revoke execute on function public.register_push_token(text, text, text, text[]) from public, anon;
grant execute on function public.register_push_token(text, text, text, text[]) to authenticated;

-- Что и кому отправили из панели — для истории (КП 15.5).
create table if not exists public.push_log (
  id bigint generated always as identity primary key,
  kind text not null,
  title_ru text not null,
  sent integer not null default 0,
  failed integer not null default 0,
  note text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.push_log enable row level security;

create policy push_log_read on public.push_log
  for select to authenticated using (public.is_staff());

-- Ключ APNs хранится в Vault (зашифрован), не в коде и не в переменных:
-- apns_key_p8 (.p8 целиком), apns_key_id, apns_team_id. Читать может только
-- серверная функция (service_role).
create or replace function public.apns_config()
returns jsonb
language sql
security definer
set search_path = public, vault
as $$
  select coalesce(jsonb_object_agg(name, decrypted_secret), '{}'::jsonb)
  from vault.decrypted_secrets
  where name in ('apns_key_p8', 'apns_key_id', 'apns_team_id');
$$;

revoke execute on function public.apns_config() from public, anon, authenticated;
grant execute on function public.apns_config() to service_role;

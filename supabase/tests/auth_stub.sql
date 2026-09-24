-- Заглушка схемы auth Supabase для проверки миграций на обычном Postgres.
-- Только то, на что опираются миграции TeddyTales: пользователи, способы
-- входа, auth.uid() и роли API. На живой базе этого файла нет — там всё
-- настоящее.
create extension if not exists pgcrypto;

do $$ begin
  create role anon nologin;
exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role nologin bypassrls;
exception when duplicate_object then null; end $$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  is_anonymous boolean not null default false,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists auth.identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null,
  provider_id text not null,
  email text,
  created_at timestamptz not null default now(),
  unique (provider, provider_id)
);

-- В тестах «кто вошёл» задаётся настройкой: set app.uid = '<uuid>'.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('app.uid', true), '')::uuid
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$ select '{}'::jsonb $$;

create or replace function auth.email() returns text
language sql stable as $$
  select email from auth.users where id = auth.uid()
$$;

-- Supabase выдаёт ролям API права на объекты public по умолчанию.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

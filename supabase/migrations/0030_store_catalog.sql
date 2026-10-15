-- 0030: каталог настоящих мишек — витрина сайта TeddyTales (КП 12).
--
-- Решение Ирины 14.10: покупка — на сайте teddytales.com. Приложение
-- показывает их товары (фото, цены, размеры, наличие — КП 12.1, 12.2), а
-- «Купить на сайте» открывает страницу товара. Адрес, оплата и доставка —
-- на сайте (КП 12.3, 12.4), заказ сразу попадает в их систему продаж
-- (КП 12.5).
--
-- Сайт сделан на Shopify, список товаров у него открыт: /products.json.
-- Сервер раз в час забирает его функцией refresh_store_catalog()
-- (расширение http) и раскладывает в store_catalog. Приложение читает
-- store_catalog() — не сайт: если сайт что-то поменяет, править одно место.
--
-- game_config.store_catalog:
--   url  — адрес магазина;
--   show — какие разделы видны в приложении: bears, clothes, friends.
--          ⚠ ждёт согласования: по умолчанию всё, как на сайте;
--   utm  — метка «из приложения» в ссылках (utm_source).
--
-- Разделы — по типу товара на сайте: Bear → bears, Clothing accessories →
-- clothes, остальные зверята (Cat, Fox, Blind Box…) → friends. Подарочная
-- карта и услуги не показываются: это не физический товар.
--
-- Применена 14.10 по частям через execute_sql (apply_migration ждёт
-- ручного подтверждения), запись в schema_migrations внесена отдельно.

create extension if not exists http with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

insert into public.game_config (key, value)
values ('store_catalog', jsonb_build_object(
  'url', 'https://teddytales.com',
  'show', jsonb_build_array('bears', 'clothes', 'friends'),
  'utm', 'teddytales_app'))
on conflict (key) do nothing;

create table if not exists public.store_catalog (
  id bigint primary key,                 -- id товара в Shopify
  handle text not null,                  -- адрес: /products/<handle>
  title text not null,
  product_type text not null default '',
  category text,                         -- bears | clothes | friends | null
  tags text[] not null default '{}',     -- размеры (30cm), серии, мех
  price numeric(10, 2) not null,         -- самый дешёвый вариант, USD
  price_max numeric(10, 2) not null,
  compare_at numeric(10, 2),             -- цена до скидки, если есть
  available boolean not null,            -- есть хоть один вариант
  images text[] not null default '{}',
  variants jsonb not null default '[]',  -- id, title, price, available…
  position integer not null,             -- порядок как на сайте
  synced_at timestamptz not null default now()
);

-- Прямого доступа нет: приложение читает только через store_catalog().
alter table public.store_catalog enable row level security;

create or replace function public.store_catalog_shown()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select array(select jsonb_array_elements_text(value -> 'show'))
     from public.game_config where key = 'store_catalog'),
    array['bears', 'clothes', 'friends']);
$$;

-- Забрать товары с сайта. Только сервер (cron) и администратор через SQL:
-- вызов через API (session_user = authenticator) отказывается сразу, до
-- запроса к сайту, — иначе любой мог бы гонять наш сервер на их сайт.
-- Отзывать право через REVOKE не стали: на REVOKE, DROP и DELETE Supabase
-- ждёт ручного подтверждения (14.10), а проверка внутри закрывает тот же
-- вызов.
--
-- Товары, которых больше нет на сайте, не удаляются, а прячутся
-- (category = null): вернётся на сайт — появится снова.
create or replace function public.refresh_store_catalog()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := coalesce(
    (select value ->> 'url' from public.game_config where key = 'store_catalog'),
    'https://teddytales.com');
  v_page integer := 1;
  v_status integer;
  v_content text;
  v_batch jsonb;
  v_seen bigint[] := '{}';
begin
  if session_user = 'authenticator' then
    raise exception 'refresh_store_catalog: только для сервера';
  end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  loop
    select r.status, r.content into v_status, v_content
    from extensions.http_get(
      v_url || '/products.json?limit=250&page=' || v_page) r;
    if v_status <> 200 then
      raise exception 'store_catalog: % ответил %', v_url, v_status;
    end if;
    v_batch := v_content::jsonb -> 'products';
    exit when v_batch is null or jsonb_array_length(v_batch) = 0;

    insert into public.store_catalog as s (
      id, handle, title, product_type, category, tags, price, price_max,
      compare_at, available, images, variants, position, synced_at)
    select
      (e.p ->> 'id')::bigint,
      e.p ->> 'handle',
      e.p ->> 'title',
      coalesce(e.p ->> 'product_type', ''),
      case
        when e.p ->> 'product_type' = 'Bear' then 'bears'
        when e.p ->> 'product_type' = 'Clothing accessories' then 'clothes'
        when e.p ->> 'product_type' ilike 'gift card%'
          or e.p ->> 'product_type' ilike '%services%' then null
        else 'friends'
      end,
      array(select jsonb_array_elements_text(e.p -> 'tags')),
      v.price_min,
      v.price_max,
      v.compare_at,
      coalesce(v.available, false),
      array(select i ->> 'src'
            from jsonb_array_elements(e.p -> 'images') i
            order by (i ->> 'position')::integer
            limit 8),
      coalesce(v.variants, '[]'::jsonb),
      coalesce(array_length(v_seen, 1), 0) + e.ord::integer,
      now()
    from jsonb_array_elements(v_batch) with ordinality as e(p, ord)
    cross join lateral (
      select
        min((x ->> 'price')::numeric) as price_min,
        max((x ->> 'price')::numeric) as price_max,
        max(nullif(x ->> 'compare_at_price', '')::numeric) filter (
          where nullif(x ->> 'compare_at_price', '')::numeric
                > (x ->> 'price')::numeric) as compare_at,
        bool_or((x ->> 'available')::boolean) as available,
        jsonb_agg(jsonb_build_object(
          'id', (x ->> 'id')::bigint,
          'title', x ->> 'title',
          'price', (x ->> 'price')::numeric,
          'compare_at', nullif(x ->> 'compare_at_price', '')::numeric,
          'available', (x ->> 'available')::boolean,
          'image', x -> 'featured_image' ->> 'src')
          order by (x ->> 'position')::integer) as variants
      from jsonb_array_elements(e.p -> 'variants') x
    ) v
    on conflict (id) do update set
      handle = excluded.handle,
      title = excluded.title,
      product_type = excluded.product_type,
      category = excluded.category,
      tags = excluded.tags,
      price = excluded.price,
      price_max = excluded.price_max,
      compare_at = excluded.compare_at,
      available = excluded.available,
      images = excluded.images,
      variants = excluded.variants,
      position = excluded.position,
      synced_at = excluded.synced_at;

    v_seen := v_seen || array(
      select (p ->> 'id')::bigint from jsonb_array_elements(v_batch) p);
    exit when jsonb_array_length(v_batch) < 250 or v_page >= 20;
    v_page := v_page + 1;
  end loop;

  -- Пустой ответ — сбой сайта, а не закрытый магазин: витрину не трогаем.
  if coalesce(array_length(v_seen, 1), 0) = 0 then
    raise exception 'store_catalog: % вернул пустой список', v_url;
  end if;
  update public.store_catalog
  set category = null, available = false
  where id <> all (v_seen) and category is not null;
  return array_length(v_seen, 1);
end;
$$;

-- Витрина для приложения: адрес, метка, время сверки и товары видимых
-- разделов в порядке сайта.
create or replace function public.store_catalog()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'url', coalesce(c.value ->> 'url', 'https://teddytales.com'),
    'utm', coalesce(c.value ->> 'utm', 'teddytales_app'),
    'synced_at', (select max(synced_at) from public.store_catalog),
    'products', coalesce(
      (select jsonb_agg(
         to_jsonb(s) - 'product_type' - 'synced_at' order by s.position)
       from public.store_catalog s
       where s.category = any (public.store_catalog_shown())),
      '[]'::jsonb))
  from (select (select value from public.game_config
                where key = 'store_catalog') as value) c;
$$;

-- Раз в час, в 23 минуты: сайт меняется редко, а нагрузка на него — один
-- запрос. Первый прогон — сразу после миграции:
-- `select public.refresh_store_catalog();` (14.10: 223 товара за секунды).
select cron.schedule(
  'store-catalog-refresh', '23 * * * *',
  $$select public.refresh_store_catalog()$$);

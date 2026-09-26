-- 0026: покупки в App Store и Google Play (КП 11.3).
--
-- ⚠ ЖДЁТ СОГЛАСОВАНИЯ: какие предметы премиальные и почём (КП 10.8,
-- 10.9 — «цены утверждаются отдельно»), и товары в App Store Connect /
-- Google Play Console. Пока store_products.products пустой — в приложении
-- покупок за деньги нет, «Восстановить покупки» не показывается.
--
-- Как устроено:
--   1. Приложение спрашивает store_products() — какие товары продаются.
--   2. Человек платит в App Store / Google Play.
--   3. Приложение отдаёт чек функции verify-purchase
--      (supabase/functions/verify-purchase): она проверяет его у Apple или
--      Google и зовёт grant_store_purchase от имени сервера.
--   4. grant_store_purchase выдаёт предмет (inventory, source = 'money')
--      и/или монеты. Один чек — одна выдача (unique platform +
--      transaction_id), повтор и «Восстановить покупки» ничего не удваивают.
--
-- Формат store_products.products:
--   {"<product_id>": {"item": "<item_id>"}}      — премиальный предмет
--   {"<product_id>": {"coins": 500}}             — набор монет
-- product_id — как в App Store Connect и Google Play (одинаковый).

insert into public.game_config (key, value)
values ('store_products', jsonb_build_object('products', '{}'::jsonb))
on conflict (key) do nothing;

alter table public.purchases add column if not exists item_id text;

-- Что продаётся. Клиент по этим id спрашивает у магазина цены на языке
-- телефона — свои цены сервер не хранит, их задаёт App Store / Google Play.
create or replace function public.store_products()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select value -> 'products' from public.game_config
     where key = 'store_products'),
    '{}'::jsonb);
$$;

revoke execute on function public.store_products() from public, anon;
grant execute on function public.store_products() to authenticated;

-- Выдать покупку. Только для verify-purchase (service_role): чек к этому
-- моменту проверен у Apple или Google.
create or replace function public.grant_store_purchase(
  p_player uuid,
  p_platform public.purchase_platform,
  p_product text,
  p_transaction text,
  p_receipt jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product jsonb;
  v_item text;
  v_coins integer;
  v_existing public.purchases;
  v_balance integer;
begin
  select * into v_existing from public.purchases
  where platform = p_platform and transaction_id = p_transaction;
  if found then
    -- Чек уже проведён: повтор или «Восстановить покупки». Предмет на
    -- месте — возвращаем, что было, ничего не начисляя.
    if v_existing.player_id <> p_player then
      raise exception 'Чек принадлежит другому аккаунту' using errcode = 'TT409';
    end if;
    if v_existing.item_id is not null then
      insert into public.inventory (player_id, item_id, source, price_paid)
      values (p_player, v_existing.item_id, 'money', 0)
      on conflict (player_id, item_id) do nothing;
    end if;
    select coins into v_balance from public.players where id = p_player;
    return jsonb_build_object('status', 'already', 'item', v_existing.item_id,
      'coins', 0, 'balance', v_balance);
  end if;

  v_product := public.store_products() -> p_product;
  if v_product is null then
    raise exception 'Неизвестный товар %', p_product using errcode = 'TT404';
  end if;
  v_item := v_product ->> 'item';
  v_coins := coalesce((v_product ->> 'coins')::integer, 0);

  insert into public.purchases (player_id, platform, product_id,
    transaction_id, coins_granted, status, receipt, verified_at, item_id)
  values (p_player, p_platform, p_product, p_transaction, v_coins,
    'verified', p_receipt, now(), v_item);

  if v_item is not null then
    insert into public.inventory (player_id, item_id, source, price_paid)
    values (p_player, v_item, 'money', 0)
    on conflict (player_id, item_id) do nothing;
  end if;

  if v_coins > 0 then
    v_balance := public.wallet_change(p_player, v_coins, 'store:' || p_product);
  else
    select coins into v_balance from public.players where id = p_player;
  end if;

  return jsonb_build_object('status', 'granted', 'item', v_item,
    'coins', v_coins, 'balance', v_balance);
end;
$$;

revoke execute on function public.grant_store_purchase(
  uuid, public.purchase_platform, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.grant_store_purchase(
  uuid, public.purchase_platform, text, text, jsonb) to service_role;

-- Возврат денег (Apple / Google прислали отмену): отметка в истории,
-- предмет забираем. Для verify-purchase и панели.
create or replace function public.refund_store_purchase(
  p_platform public.purchase_platform,
  p_transaction text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.purchases;
begin
  update public.purchases set status = 'refunded'
  where platform = p_platform and transaction_id = p_transaction
  returning * into v_row;
  if found and v_row.item_id is not null then
    delete from public.inventory
    where player_id = v_row.player_id and item_id = v_row.item_id
      and source = 'money';
  end if;
end;
$$;

revoke execute on function public.refund_store_purchase(
  public.purchase_platform, text) from public, anon, authenticated;
grant execute on function public.refund_store_purchase(
  public.purchase_platform, text) to service_role;

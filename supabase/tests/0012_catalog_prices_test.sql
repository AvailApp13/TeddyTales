-- Проверка 0012: у каждого товара магазина есть цена, покупка списывает
-- ровно её, отказ не трогает кошелёк.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

do $$
declare
  prices jsonb := public.cfg('item_prices');
begin
  assert (select count(*) from jsonb_object_keys(prices)) = 74,
    format('цен %s, а товаров в приложении 74', (select count(*) from jsonb_object_keys(prices)));
  assert (prices ->> 'dollhouse')::int = 220, 'кукольный домик 220';
  assert (prices ->> 'armchair_wing')::int = 190, 'кресло с ушами 190';
  assert (prices ->> 'bed')::int = 120, 'старые цены не тронуты';
end $$;

-- Порог испытаний — как на живой базе (тест 0010 ставил его в 0).
update public.game_config set value = '5000'::jsonb where key = 'test_wallet_floor';

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'shop@example.test');

set role authenticated;
set app.uid = '00000000-0000-0000-0000-0000000000d1';
do $$
declare
  pet uuid := (public.open_account() -> 'pet' ->> 'id')::uuid;
  s jsonb;
begin
  -- 5000 после входа; домик 220, кресло 190, паста 12, печенье +8.
  s := public.buy_item(pet, 'dollhouse');
  assert (s -> 'account' ->> 'coins')::int = 4780, format('после домика %s', s -> 'account' ->> 'coins');
  s := public.buy_item(pet, 'armchair_wing');
  assert (s -> 'account' ->> 'coins')::int = 4590, 'после кресла';
  s := public.feed_dish(pet, 'pasta');
  assert (s -> 'account' ->> 'coins')::int = 4578, 'после пасты';
  s := public.complete_recipe(pet, 'cookie');
  assert (s -> 'account' ->> 'coins')::int = 4586, 'после печенья';
  assert s -> 'inventory' ? 'dollhouse' and s -> 'inventory' ? 'armchair_wing', 'вещи в инвентаре';
  begin
    perform public.buy_item(pet, 'dollhouse');
    raise exception 'купил второй раз';
  exception when sqlstate 'TT409' then null;
  end;
  assert (public.pet_snapshot(pet) -> 'account' ->> 'coins')::int = 4586, 'повтор не списал';
end $$;
reset role;

do $$
begin
  assert (select array_agg(amount order by id) from public.coin_ledger
          where player_id = '00000000-0000-0000-0000-0000000000d1')
         = array[250, 4750, -220, -190, -12, 8],
    format('книга операций: %s', (select array_agg(amount order by id) from public.coin_ledger
          where player_id = '00000000-0000-0000-0000-0000000000d1'));
end $$;

select 'ALL 0012 CHECKS PASSED';

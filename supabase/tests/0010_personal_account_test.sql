-- Проверка миграции 0010 на локальном Postgres (auth_stub.sql + все
-- миграции). Запуск: tool/test_supabase.sh. Любая неудача — исключение.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

-- Два игрока и сотрудник.
insert into auth.users (id, is_anonymous) values
  ('00000000-0000-0000-0000-00000000000a', true),
  ('00000000-0000-0000-0000-00000000000b', true);
insert into public.staff_invites (email, role) values ('boss@teddytales.test', 'admin')
  on conflict do nothing;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c0', 'boss@teddytales.test');
insert into auth.identities (user_id, provider, provider_id) values
  ('00000000-0000-0000-0000-00000000000a', 'apple', 'apple-sub-a');

-- Регистрация: кабинет, мишка, стартовые монеты на кабинете; сотрудник без кабинета.
do $$
begin
  assert (select coins from public.players
          where id = '00000000-0000-0000-0000-00000000000a') = 250, 'стартовые монеты';
  assert (select count(*) from public.pets
          where player_id = '00000000-0000-0000-0000-00000000000a') = 1, 'один мишка';
  assert (select named_at from public.pets
          where player_id = '00000000-0000-0000-0000-00000000000a') is null, 'имя не дано';
  assert not exists (select 1 from public.players
                     where id = '00000000-0000-0000-0000-0000000000c0'), 'сотрудник без кабинета';
  assert exists (select 1 from public.staff
                 where user_id = '00000000-0000-0000-0000-0000000000c0'), 'сотрудник с ролью';
end $$;

-- Сытость пониже, чтобы было что поднимать.
update public.pet_stats set food = 10, measured_at = now()
where pet_id = (select id from public.pets where player_id = '00000000-0000-0000-0000-00000000000a');

-- От лица игрока A, как это делает приложение.
set role authenticated;
set app.uid = '00000000-0000-0000-0000-00000000000a';

create temp table t_pet as
  select (public.open_account() -> 'pet' ->> 'id')::uuid as id;

do $$
declare
  s jsonb;
  v_pet uuid := (select id from t_pet);
begin
  s := public.open_account();
  assert (s -> 'account' ->> 'coins')::int = 5000, 'порог 5000 при входе';
  assert (s -> 'account' ->> 'is_anonymous')::boolean, 'анонимный';
  assert s -> 'account' -> 'providers' ? 'apple', 'видна привязка Apple';
  assert not (s -> 'pet' ? 'coins'), 'у мишки монет нет';

  -- Еда за монеты: минус цена, плюс сытость.
  s := public.feed_dish(v_pet, 'pasta');
  assert (s -> 'account' ->> 'coins')::int = 4988, 'паста стоит 12';
  assert (s -> 'stats' ->> 'food')::real between 44 and 46, 'сытость +35';

  -- Рецепт: плюс награда, плюс сытость.
  s := public.complete_recipe(v_pet, 'cookie');
  assert (s -> 'account' ->> 'coins')::int = 4996, 'печенье даёт 8';

  -- Покупка предмета — с того же кошелька.
  s := public.buy_item(v_pet, 'teddy');
  assert (s -> 'account' ->> 'coins')::int = 4906, 'мишка-игрушка стоит 90';

  -- Имя: форма и отметка первого имени.
  s := public.rename_pet(v_pet, '  Тишка  ');
  assert s -> 'pet' ->> 'name' = 'Тишка', 'имя сохранено без пробелов';
  assert s -> 'pet' ->> 'named_at' is not null, 'отметка первого имени';

  -- Незнакомое блюдо — понятная ошибка.
  begin
    perform public.feed_dish(v_pet, 'pizza');
    assert false, 'пицца не должна продаваться';
  exception when sqlstate 'TT404' then null;
  end;
end $$;

-- Нехватка монет: порог выключен, баланс не уходит в минус.
reset role;
update public.game_config set value = '0'::jsonb where key = 'test_wallet_floor';
update public.players set coins = 3 where id = '00000000-0000-0000-0000-00000000000a';
set role authenticated;
set app.uid = '00000000-0000-0000-0000-00000000000a';
do $$
begin
  begin
    perform public.feed_dish((select id from t_pet), 'pie');
    assert false, 'пирог за 15 при 3 монетах';
  exception when sqlstate 'TT402' then null;
  end;
end $$;

-- Права игрока.
do $$
begin
  assert (select coins from public.players
          where id = '00000000-0000-0000-0000-00000000000a') = 3, 'баланс не тронут';
  -- Монеты руками не переписать.
  begin
    update public.players set coins = 999999 where id = '00000000-0000-0000-0000-00000000000a';
    assert false, 'игрок переписал себе монеты';
  exception when insufficient_privilege then null;
  end;
  -- Настройки — можно.
  update public.players set locale = 'en' where id = '00000000-0000-0000-0000-00000000000a';
  -- Внутренний кошелёк недоступен.
  begin
    perform public.wallet_change('00000000-0000-0000-0000-00000000000a', 100, 'cheat');
    assert false, 'игрок вызвал wallet_change';
  exception when insufficient_privilege then null;
  end;
  -- Чужой кабинет не виден.
  assert (select count(*) from public.players) = 1, 'видит только свой кабинет';
  assert (select count(*) from public.pets) = 1, 'видит только своего мишку';
end $$;

-- Игрок B не может кормить мишку A.
set app.uid = '00000000-0000-0000-0000-00000000000b';
do $$
begin
  begin
    perform public.feed_dish((select id from t_pet), 'porridge');
    assert false, 'чужой мишка';
  exception when sqlstate 'TT403' then null;
  end;
end $$;

-- Без входа ничего не вызвать.
reset role;
set role anon;
reset app.uid;
do $$
begin
  begin
    perform public.rename_pet((select id from t_pet), 'Взлом');
    assert false, 'rename_pet без входа';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.open_account();
    assert false, 'open_account без входа';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Удаление аккаунта: всё уходит каскадом.
reset role;
set role authenticated;
set app.uid = '00000000-0000-0000-0000-00000000000a';
select public.delete_my_account();
reset role;
do $$
begin
  assert not exists (select 1 from auth.users
                     where id = '00000000-0000-0000-0000-00000000000a'), 'учётка удалена';
  assert not exists (select 1 from public.players
                     where id = '00000000-0000-0000-0000-00000000000a'), 'кабинет удалён';
  assert not exists (select 1 from public.coin_ledger
                     where player_id = '00000000-0000-0000-0000-00000000000a'), 'история удалена';
  assert exists (select 1 from public.players
                 where id = '00000000-0000-0000-0000-00000000000b'), 'чужой кабинет цел';
end $$;

-- Панель считает монеты с кабинетов.
insert into public.staff (user_id, role) values ('00000000-0000-0000-0000-0000000000c0', 'admin')
  on conflict do nothing;
set role authenticated;
set app.uid = '00000000-0000-0000-0000-0000000000c0';
do $$
declare d jsonb := public.admin_dashboard();
begin
  assert (d ->> 'coins_total')::int = 250, format('монет в игре: %s', d ->> 'coins_total');
end $$;
reset role;

select 'ALL 0010 CHECKS PASSED' as result;

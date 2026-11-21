-- Стартовый кошелёк нового игрока.
--
-- Новый игрок приходил с нулём монет: `pets.coins` по умолчанию 0, а при
-- рождении питомца никто ничего не начислял. Это заметили на живой сборке —
-- в шапке ноль, и вся витрина мертва с первой секунды: подсказки в комнате
-- ведут в магазин, замена вещи предлагает купить, а платить нечем.
--
-- В КП стартового баланса нет: там только «80–120 монет в день» (11.1).
-- Решение заказчика от 17.09 — 250 монет. Этого хватает на кроватку (120) и
-- пару мелочей или на светильник с ковром: первая покупка доступна в первый
-- же вечер, но магазин не теряет смысл — дальше надо зарабатывать.
--
-- Значение живёт в game_config, а не в default колонки: по КП 15.4
-- экономика настраивается из панели с историей изменений, и подбирать
-- стартовый баланс наверняка придётся не один раз.

insert into public.game_config (key, value)
values ('starting_coins', '250'::jsonb)
on conflict (key) do update set value = excluded.value;

-- Начисляем при рождении питомца.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet uuid;
  v_skin public.bear_skin;
  v_coins integer;
begin
  insert into public.players (id) values (new.id);

  -- Пол определяет сервер (КП 2.4).
  v_skin := case when random() < 0.5 then 'boy' else 'girl' end;

  -- Ноль в coalesce намеренный: если настройки почему-то нет, игрок
  -- получает пустой кошелёк, а не падение регистрации.
  v_coins := coalesce((public.cfg('starting_coins'))::text::integer, 0);

  insert into public.pets (player_id, name, skin, coins)
  values (new.id, 'Мой малыш', v_skin, v_coins)
  returning id into v_pet;

  insert into public.pet_stats (pet_id) values (v_pet);
  insert into public.pet_outfit (pet_id) values (v_pet);

  -- Стартовые монеты проходят по книге операций, как любые другие: баланс
  -- без записи о происхождении — дыра в отчётности (КП 15.1), и первая же
  -- сверка «сколько игрок заработал» покажет минус.
  if v_coins > 0 then
    insert into public.coin_ledger (player_id, amount, reason)
    values (new.id, v_coins, 'welcome');
  end if;

  -- Двенадцать бесплатных предметов на старте (КП 10.8).
  insert into public.inventory (player_id, item_id, source, price_paid)
  select new.id, item, 'free', 0
  from jsonb_array_elements_text(
    coalesce(public.cfg('starting_items'), '[]'::jsonb)) as item;

  -- Обои и пол ставятся сразу: без них комната не нарисуется. Мебель
  -- игрок расставляет сам — решение заказчика, герой в кадре один.
  insert into public.room_layout (player_id, item_id)
  select new.id, item
  from (values ('wall_rose'), ('floor_wood')) as v(item)
  where exists (select 1 from public.inventory i
                where i.player_id = new.id and i.item_id = v.item);

  return new;
end;
$$;

-- Уже зарегистрированным игрокам с пустым кошельком выдаём то же самое:
-- иначе все, кто зашёл до этой миграции (включая тестовые прогоны),
-- останутся с мёртвым магазином навсегда.
with grant_to as (
  select p.id, p.player_id
  from public.pets p
  where p.coins = 0
    and not exists (
      select 1 from public.coin_ledger l
      where l.player_id = p.player_id and l.reason = 'welcome'
    )
)
update public.pets p
set coins = coalesce((public.cfg('starting_coins'))::text::integer, 0)
from grant_to g
where p.id = g.id;

insert into public.coin_ledger (player_id, amount, reason)
select p.player_id, p.coins, 'welcome'
from public.pets p
where p.coins > 0
  and not exists (
    select 1 from public.coin_ledger l
    where l.player_id = p.player_id and l.reason = 'welcome'
  );

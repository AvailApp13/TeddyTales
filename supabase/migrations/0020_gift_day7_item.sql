-- 0020: седьмой день календаря — вещь-сюрприз вместо монет (заказчик 25.09:
-- «конверты мы делаем»; дни 1–6 — красный конверт с монетами, день 7 —
-- большая коробка с бантом и вещью внутри).
--
-- Вещь — случайная из gift_day7_pool (мебель, декор, игрушки с настоящими
-- картинками; одежды нет — надевать пока не на кого), по цене каталога в
-- пределах gift_day7.min_price–max_price и которой у игрока ещё нет. Всё
-- собрано — gift_day7.fallback_coins монет.
--
-- Что выдано в последний раз, лежит в players.gift_last — приложение
-- показывает это в анимации открытия.

alter table public.players
  add column if not exists gift_last jsonb;
comment on column public.players.gift_last is
  'Последний подарок дня: {"day": n, "coins": n} или {"day": 7, "item": id}.';

insert into public.game_config (key, value) values
  ('gift_day7', '{"min_price": 100, "max_price": 240, "fallback_coins": 50}'),
  ('gift_day7_pool', '["bed", "table", "shelf", "dresser", "armchair", "basket",
    "shelf_house", "shelf_moon", "armchair_sage", "armchair_bean",
    "armchair_flower", "armchair_wing", "swing", "basket_star", "rug",
    "rug_cloud", "rug_heart", "pic_bear", "pillow_star", "plant", "pic_heart",
    "plant_ivy", "plant_bear", "flowers_daisy", "flowers_orchid", "flowers_euc",
    "teddy", "cubes", "teddy_cream", "bunny", "bunny_pink", "pyramid",
    "dollhouse", "house_felt"]')
on conflict (key) do nothing;

create or replace function public.claim_daily_gift(p_pet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player uuid := public.pet_owner(p_pet_id);
  v_today date := public.player_now(v_player)::date;
  v_day smallint;
  v_reward integer;
  v_item text;
  v_last jsonb;
begin
  if exists (select 1 from public.players
             where id = v_player and gift_date = v_today) then
    raise exception 'Подарок уже забран сегодня' using errcode = 'TT409';
  end if;
  v_day := public.next_gift_day(v_player);

  if v_day = 7 then
    select p.item into v_item
    from jsonb_array_elements_text(coalesce(public.cfg('gift_day7_pool'), '[]'::jsonb)) p(item)
    where (public.cfg('item_prices') ->> p.item)::integer
            between public.cfg_num('gift_day7', 'min_price', 0)
                and public.cfg_num('gift_day7', 'max_price', 1000000)
      and not exists (select 1 from public.inventory i
                      where i.player_id = v_player and i.item_id = p.item)
    order by random()
    limit 1;
  end if;

  if v_item is not null then
    insert into public.inventory (player_id, item_id, source, price_paid)
    values (v_player, v_item, 'free', 0);
    v_last := jsonb_build_object('day', v_day, 'item', v_item);
  else
    v_reward := case when v_day = 7
                     then public.cfg_num('gift_day7', 'fallback_coins', 0)
                     else public.cfg_num('daily_gift', 'day' || v_day, 0)
                end::integer;
    if v_reward > 0 then
      perform public.wallet_change(v_player, v_reward, 'gift:' || v_today);
    end if;
    v_last := jsonb_build_object('day', v_day, 'coins', v_reward);
  end if;

  update public.players
  set gift_day = v_day, gift_date = v_today, gift_last = v_last
  where id = v_player;

  return public.pet_snapshot(p_pet_id);
end;
$$;

-- В «Сегодня» — ещё и последний подарок (для анимации открытия).
create or replace function public.daily_outlook(p_player uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.ensure_tasks(p_player);
  v_week_start date := date_trunc('week', v_day)::date;
begin
  return jsonb_build_object(
    'day', v_day,
    'gift', jsonb_build_object(
      'available', not exists (select 1 from public.players
                               where id = p_player and gift_date = v_day),
      'next_day', public.next_gift_day(p_player),
      'claimed_day', (select gift_day from public.players where id = p_player),
      'last', (select gift_last from public.players where id = p_player),
      'rewards', (select jsonb_agg(public.cfg_num('daily_gift', 'day' || n, 0)
                                   order by n)
                  from generate_series(1, 7) n)
    ),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.task, 'target', t.target, 'progress', t.progress,
               'done', t.done_at is not null,
               'reward', public.cfg_num('daily_tasks_reward', t.task, 0))
             order by t.task)
      from public.player_tasks t
      where t.player_id = p_player and t.day = v_day), '[]'::jsonb),
    'weekly', jsonb_build_object(
      'days_done', (
        select count(distinct d.day) from public.player_tasks d
        where d.player_id = p_player
          and d.day between v_week_start and v_week_start + 6
          and not exists (select 1 from public.player_tasks x
                          where x.player_id = d.player_id and x.day = d.day
                            and x.done_at is null)),
      'target', public.cfg_num('daily_tasks_meta', 'weekly_days', 5),
      'reward', public.cfg_num('daily_tasks_meta', 'weekly_reward', 0),
      'claimed', exists (select 1 from public.coin_ledger
                         where player_id = p_player
                           and reason = 'weekly:' || v_week_start))
  );
end;
$$;

revoke execute on function public.daily_outlook(uuid) from public, anon, authenticated;
revoke execute on function public.claim_daily_gift(uuid) from public, anon;
grant execute on function public.claim_daily_gift(uuid) to authenticated;

do $$
begin
  if jsonb_array_length(public.cfg('gift_day7_pool')) < 30 then
    raise exception 'gift_day7_pool: нет списка вещей';
  end if;
  if (select count(*) from jsonb_array_elements_text(public.cfg('gift_day7_pool')) p(item)
      where (public.cfg('item_prices') ->> p.item)::integer between 100 and 240) = 0 then
    raise exception 'gift_day7_pool: нет вещей в нужной цене';
  end if;
end;
$$;

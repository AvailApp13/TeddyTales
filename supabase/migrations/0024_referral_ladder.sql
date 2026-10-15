-- 0024: лестница наград за приглашения и статистика (заказчик 26.09).
--
-- Каждый друг — по referral.coins обоим (0021). Сверху — бонус
-- пригласившему, когда друзей становится 3, 5 и 10: referral.bonus_3,
-- bonus_5, bonus_10 (числа — в панели, «Экономика»; ставка по умолчанию,
-- заказчик утверждает). Окно «Поделиться» показывает, сколько друзей
-- пришло, сколько монет это принесло и какие ступени впереди.

update public.game_config
set value = value || jsonb_build_object(
  'bonus_3', 50, 'bonus_5', 100, 'bonus_10', 250)
where key = 'referral';

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
  v_count integer;
  v_bonus integer;
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

  perform 1 from public.players where id = v_player for update;
  if exists (select 1 from public.referrals where invitee = v_player) then
    raise exception 'Код уже введён' using errcode = 'TT409';
  end if;

  select created_at into v_created from public.players where id = v_player;
  if v_created < now() - make_interval(
       days => public.cfg_num('referral', 'new_account_days', 7)::integer) then
    raise exception 'Код вводят только в первые дни' using errcode = 'TT410';
  end if;

  -- Пригласивший — под замок: два друга одновременно не должны оба
  -- «стать третьим».
  perform 1 from public.players where id = v_inviter for update;
  select count(*) into v_count from public.referrals where inviter = v_inviter;
  if v_count >= public.cfg_num('referral', 'max_invites', 50) then
    raise exception 'У друга больше нет приглашений' using errcode = 'TT429';
  end if;

  insert into public.referrals (invitee, inviter) values (v_player, v_inviter);
  v_count := v_count + 1;
  if v_coins > 0 then
    perform public.wallet_change(v_player, v_coins, 'referral:invitee');
    perform public.wallet_change(v_inviter, v_coins, 'referral:inviter');
  end if;

  -- Ступень лестницы: ровно 3-й, 5-й, 10-й друг.
  v_bonus := public.cfg_num('referral', 'bonus_' || v_count, 0)::integer;
  if v_bonus > 0 then
    perform public.wallet_change(v_inviter, v_bonus, 'referral:bonus:' || v_count);
  end if;

  select id into v_pet from public.pets
  where player_id = v_player order by created_at limit 1;
  return public.pet_snapshot(v_pet);
end;
$$;

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
    'earned', (select coalesce(sum(amount), 0) from public.coin_ledger
               where player_id = v_player
                 and (reason = 'referral:inviter' or reason like 'referral:bonus:%')),
    'coins', public.cfg_num('referral', 'coins', 0)::integer,
    'link', coalesce(public.cfg('referral') ->> 'link', ''),
    'milestones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'friends', substr(k, 7)::integer,
               'bonus', (public.cfg('referral') ->> k)::integer)
             order by substr(k, 7)::integer)
      from jsonb_object_keys(public.cfg('referral')) k
      where k ~ '^bonus_[0-9]+$'
        and (public.cfg('referral') ->> k)::integer > 0), '[]'::jsonb),
    'can_redeem',
      not exists (select 1 from public.referrals where invitee = v_player)
      and v_created > now() - make_interval(
        days => public.cfg_num('referral', 'new_account_days', 7)::integer));
end;
$$;

revoke execute on function public.my_referral() from public, anon;
revoke execute on function public.redeem_referral(text) from public, anon;
grant execute on function public.my_referral() to authenticated;
grant execute on function public.redeem_referral(text) to authenticated;

do $$
begin
  if public.cfg_num('referral', 'bonus_3', 0) <> 50 then
    raise exception 'referral: нет лестницы';
  end if;
end;
$$;

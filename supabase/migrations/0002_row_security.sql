-- Построчная защита: игрок видит и меняет только своё.
--
-- Правило, которого держимся везде: клиент НЕ имеет права писать туда, где
-- лежит выгода. Монеты, инвентарь и результат покупки он может только
-- читать — меняют их серверные функции из `0003`. Иначе достаточно подменить
-- один запрос, чтобы выписать себе миллион монет и весь гардероб сразу.

-- --- Игрок -----------------------------------------------------------------

alter table public.players enable row level security;

create policy players_read on public.players
  for select using (id = (select auth.uid()));

create policy players_insert on public.players
  for insert with check (id = (select auth.uid()));

-- Менять можно только то, что и правда принадлежит игроку: язык, возраст,
-- тихие часы. Баланса монет в этой таблице нет намеренно — он у питомца.
create policy players_update on public.players
  for update using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

alter table public.auth_links enable row level security;

create policy auth_links_read on public.auth_links
  for select using (player_id = (select auth.uid()));

-- Привязку способа входа заводит сервер при первом входе через провайдера:
-- клиенту тут писать нечего, иначе он привяжет чужой внешний аккаунт.

-- --- Питомец ---------------------------------------------------------------

alter table public.pets enable row level security;

create policy pets_read on public.pets
  for select using (player_id = (select auth.uid()));

create policy pets_insert on public.pets
  for insert with check (player_id = (select auth.uid()));

-- Из карточки питомца клиент меняет только имя. Стадия, характер и монеты —
-- за сервером: стадию назначает он по совокупности ухода (КП 5.7), характер
-- считает из накопленных действий (КП 7.3), монеты начисляет сам (КП 11.1).
create policy pets_update_name on public.pets
  for update using (player_id = (select auth.uid()))
  with check (player_id = (select auth.uid()));

alter table public.pet_stats enable row level security;

create policy pet_stats_read on public.pet_stats
  for select using (
    exists (
      select 1 from public.pets p
      where p.id = pet_stats.pet_id and p.player_id = (select auth.uid())
    )
  );

-- Записи нет вовсе: показатели двигает только `record_care`. Иначе смысл
-- серверного времени теряется — клиент просто выставит себе сытость 100.

alter table public.pet_outfit enable row level security;

create policy pet_outfit_read on public.pet_outfit
  for select using (
    exists (
      select 1 from public.pets p
      where p.id = pet_outfit.pet_id and p.player_id = (select auth.uid())
    )
  );

-- Одеться можно только в то, что куплено, — это проверяет `wear_item`.

-- --- Прогресс --------------------------------------------------------------

alter table public.inventory enable row level security;

create policy inventory_read on public.inventory
  for select using (player_id = (select auth.uid()));

alter table public.room_layout enable row level security;

-- Расстановка мебели — единственное место, где клиент пишет свободно: на
-- балансе это никак не сказывается, а запросов много и гонять их через
-- функцию было бы расточительно. Владение предметом проверяет ограничение
-- внешнего ключа на инвентарь ниже.
create policy room_layout_all on public.room_layout
  for all using (player_id = (select auth.uid()))
  with check (
    player_id = (select auth.uid())
    and exists (
      select 1 from public.inventory i
      where i.player_id = room_layout.player_id and i.item_id = room_layout.item_id
    )
  );

alter table public.edu_progress enable row level security;

create policy edu_progress_read on public.edu_progress
  for select using (player_id = (select auth.uid()));

alter table public.care_events enable row level security;

create policy care_events_read on public.care_events
  for select using (
    exists (
      select 1 from public.pets p
      where p.id = care_events.pet_id and p.player_id = (select auth.uid())
    )
  );

alter table public.coin_ledger enable row level security;

create policy coin_ledger_read on public.coin_ledger
  for select using (player_id = (select auth.uid()));

alter table public.notification_prefs enable row level security;

create policy notification_prefs_all on public.notification_prefs
  for all using (player_id = (select auth.uid()))
  with check (player_id = (select auth.uid()));

-- --- Покупки ---------------------------------------------------------------

alter table public.purchases enable row level security;

create policy purchases_read on public.purchases
  for select using (player_id = (select auth.uid()));

-- Записи нет: покупка появляется только после того, как сервер проверил чек
-- у Apple или Google (КП 11.3).

-- --- Управление ------------------------------------------------------------

alter table public.game_config enable row level security;

-- Настройки читают все вошедшие: приложению нужны скорости и тайминги.
create policy game_config_read on public.game_config
  for select to authenticated using (true);

-- Меняет только панель управления, то есть service_role. Политики на запись
-- нет вовсе — service_role построчную защиту не проходит по определению.

alter table public.config_history enable row level security;
alter table public.name_moderation enable row level security;
alter table public.name_blocklist enable row level security;

-- Эти три — целиком за панелью: политик нет, значит клиенту закрыто.

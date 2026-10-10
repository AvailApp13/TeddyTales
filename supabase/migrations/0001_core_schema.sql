-- TeddyTales, основная схема.
--
-- Закрывает разделы КП 1.4 (прогресс на сервере), 2.2–2.5 (карточка
-- рождения), 6.1–6.3 (уход), 7 (характер), 9 (обучение), 10 (предметы и
-- гардероб), 11 (экономика), 13.2 (уведомления).
--
-- Главное решение схемы — в таблице `pet_stats`: показатели хранятся не
-- числом, а парой «значение и момент, на который оно верно». Текущее
-- значение всегда вычисляется сервером от этой пары, и часы телефона в
-- расчёте не участвуют вообще (КП 1.5). Тем же механизмом бесплатно
-- решается отыгрыш офлайна: вернулся через двое суток — сервер сам считает,
-- сколько утекло, и упирается в безопасный предел (КП 6.3).

-- --- Перечисления ----------------------------------------------------------
--
-- Значения совпадают с именами вариантов в Dart буква в букву. Это не
-- педантизм: любое расхождение пришлось бы переводить таблицей соответствия,
-- а такие таблицы всегда расходятся с кодом при первой же правке.

create type public.auth_provider as enum (
  'apple', 'google', 'email',
  -- Китайские способы входа. Заложены с самого начала, потому что добавить
  -- провайдера в живой базе с готовыми аккаунтами — это миграция с риском
  -- задвоить игроков, а пустое перечисление ничего не стоит.
  'wechat', 'alipay', 'qq'
);

create type public.bear_skin as enum ('boy', 'girl');

create type public.bear_stage as enum (
  'newborn', 'crawling', 'firstSteps', 'growing', 'adult'
);

create type public.bear_trait as enum (
  'active', 'curious', 'affectionate', 'calm', 'independent', 'reserved'
);

create type public.bear_zodiac as enum (
  'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
  'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces'
);

create type public.care_action as enum (
  'feed', 'wash', 'sleep', 'wake', 'play', 'pet', 'learn', 'dress', 'decorate'
);

create type public.name_status as enum ('pending', 'approved', 'rejected');

create type public.purchase_platform as enum (
  'apple', 'google', 'wechat', 'alipay', 'qq'
);

create type public.purchase_status as enum (
  'pending', 'verified', 'rejected', 'refunded'
);

-- Откуда предмет: подарен на старте, куплен за монеты или за деньги (КП 10.8).
create type public.item_source as enum ('free', 'coins', 'money');

-- --- Игрок -----------------------------------------------------------------

create table public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  locale text not null default 'ru' check (locale in ('ru', 'en', 'zh')),
  -- Возраст игрока выбирает набор контента (взрослый или детский), см.
  -- `lib/game/audience.dart`. NULL — ещё не спрашивали.
  player_age smallint check (player_age between 1 and 120),
  -- Тихие часы (КП 13.2) — одна настройка на игрока, поэтому здесь, а не
  -- строкой в notification_prefs.
  quiet_hours boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

comment on table public.players is
  'Аккаунт игрока. Вход без регистрации (КП 1.2), привязка способов — в auth_links.';

-- Способы входа. Аккаунт один, способов несколько: игрок может войти через
-- Apple, а потом привязать WeChat — и это должен быть тот же аккаунт,
-- а не второй (КП 1.3).
create table public.auth_links (
  player_id uuid not null references public.players (id) on delete cascade,
  provider public.auth_provider not null,
  external_id text not null,
  linked_at timestamptz not null default now(),
  primary key (player_id, provider),
  -- Один и тот же внешний аккаунт не может принадлежать двум игрокам.
  unique (provider, external_id)
);

-- --- Питомец ---------------------------------------------------------------

create table public.pets (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,

  -- Имя 2–15 символов (КП 2.3). Проверку на недопустимые слова проходит
  -- отдельно, поэтому рядом лежит статус модерации (КП 15.6).
  name text not null check (char_length(trim(name)) between 2 and 15),
  name_status public.name_status not null default 'pending',

  -- Рождение определяет сервер (КП 2.4, 2.5).
  birth_at timestamptz not null default now(),
  skin public.bear_skin not null,
  zodiac public.bear_zodiac,

  stage public.bear_stage not null default 'newborn',
  stage_changed_at timestamptz not null default now(),
  trait public.bear_trait not null default 'active',

  -- Баланс монет (КП 11.1). Меняется только серверными функциями.
  coins integer not null default 0 check (coins >= 0),

  created_at timestamptz not null default now()
);

create index pets_player_idx on public.pets (player_id);

-- Пять показателей ухода (КП 6.1) плюс момент, на который они верны.
create table public.pet_stats (
  pet_id uuid primary key references public.pets (id) on delete cascade,
  food real not null default 100 check (food between 0 and 100),
  hygiene real not null default 100 check (hygiene between 0 and 100),
  sleep real not null default 100 check (sleep between 0 and 100),
  play real not null default 100 check (play between 0 and 100),
  love real not null default 100 check (love between 0 and 100),

  -- Момент по серверным часам, на который значения выше верны. Всё, что
  -- прошло с тех пор, досчитывается при чтении.
  measured_at timestamptz not null default now()
);

comment on column public.pet_stats.measured_at is
  'Опора серверного времени (КП 1.5): показатели верны на этот момент, остальное считается.';

-- Гардероб, шесть слотов (КП 10.5, 10.6). Комплект и раздельные вещи
-- взаимно исключаются — то же правило, что в BearOutfit.
create table public.pet_outfit (
  pet_id uuid primary key references public.pets (id) on delete cascade,
  outfit_id smallint not null default 0 check (outfit_id between 0 and 8),
  top_id smallint not null default 0 check (top_id between 0 and 8),
  bottom_id smallint not null default 0 check (bottom_id between 0 and 8),
  headwear_id smallint not null default 0 check (headwear_id between 0 and 3),
  shoes_id smallint not null default 0 check (shoes_id between 0 and 2),
  accessory_id smallint not null default 0 check (accessory_id between 0 and 3),

  constraint outfit_excludes_separates
    check (outfit_id = 0 or (top_id = 0 and bottom_id = 0))
);

-- --- Прогресс --------------------------------------------------------------

create table public.inventory (
  player_id uuid not null references public.players (id) on delete cascade,
  item_id text not null,
  source public.item_source not null default 'coins',
  price_paid integer not null default 0 check (price_paid >= 0),
  acquired_at timestamptz not null default now(),
  primary key (player_id, item_id)
);

create table public.room_layout (
  player_id uuid not null references public.players (id) on delete cascade,
  item_id text not null,
  placed_at timestamptz not null default now(),
  primary key (player_id, item_id)
);

comment on table public.room_layout is
  'Что расставлено в комнате (КП 10.7). Отсутствие строки = предмет убран в инвентарь.';

create table public.edu_progress (
  player_id uuid not null references public.players (id) on delete cascade,
  category_id text not null,
  levels_done smallint not null default 0 check (levels_done between 0 and 10),
  stars smallint not null default 0 check (stars >= 0),
  updated_at timestamptz not null default now(),
  primary key (player_id, category_id)
);

-- История действий, из которой складывается характер (КП 7.3: характер
-- формируется из совокупности за период, а не из одного действия).
create table public.care_events (
  id bigint generated always as identity primary key,
  pet_id uuid not null references public.pets (id) on delete cascade,
  action public.care_action not null,
  happened_at timestamptz not null default now()
);

create index care_events_pet_time_idx
  on public.care_events (pet_id, happened_at desc);

-- Каждое движение монет с причиной. Нужен не столько для отчётов, сколько
-- для разбирательств: без него на вопрос «откуда у игрока столько монет»
-- ответить нечем.
create table public.coin_ledger (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  amount integer not null check (amount <> 0),
  reason text not null,
  happened_at timestamptz not null default now()
);

create index coin_ledger_player_idx
  on public.coin_ledger (player_id, happened_at desc);

create table public.notification_prefs (
  player_id uuid not null references public.players (id) on delete cascade,
  kind text not null,
  enabled boolean not null default true,
  primary key (player_id, kind)
);

-- --- Покупки ---------------------------------------------------------------
--
-- Только монеты. Физические мишки (КП 12) идут отдельным контуром: Apple
-- прямо запрещает продавать физические товары через встроенные покупки, а
-- виртуальную валюту — наоборот, только через них. Смешивать эти две вещи
-- в одной таблице значит рано или поздно провести заказ мишки как покупку
-- монет.
create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  platform public.purchase_platform not null,
  product_id text not null,
  transaction_id text not null,
  coins_granted integer not null default 0 check (coins_granted >= 0),
  status public.purchase_status not null default 'pending',
  -- Ответ проверки чека целиком: при спорах это единственное доказательство.
  receipt jsonb,
  created_at timestamptz not null default now(),
  verified_at timestamptz,

  -- Один чек нельзя провести дважды — защита от повторного начисления.
  unique (platform, transaction_id)
);

create index purchases_player_idx on public.purchases (player_id, created_at desc);

-- --- Управление (КП 15) ----------------------------------------------------

-- Все настраиваемые числа игры. Сейчас они зашиты в Dart, и поменять
-- скорость голода можно только новой сборкой приложения — КП 5.6 и 15.4
-- требуют обратного.
create table public.game_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.config_history (
  id bigint generated always as identity primary key,
  key text not null,
  old_value jsonb,
  new_value jsonb not null,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

comment on table public.config_history is
  'История изменений экономики (КП 15.4). Пишется триггером, руками не трогается.';

-- Стоп-словарь и очередь спорных имён (КП 2.3, 15.6).
create table public.name_moderation (
  id bigint generated always as identity primary key,
  pet_id uuid references public.pets (id) on delete cascade,
  name text not null,
  locale text not null check (locale in ('ru', 'en', 'zh')),
  status public.name_status not null default 'pending',
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.name_blocklist (
  id bigint generated always as identity primary key,
  pattern text not null,
  locale text not null check (locale in ('ru', 'en', 'zh')),
  unique (pattern, locale)
);

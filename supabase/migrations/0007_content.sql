-- Контент из панели управления (КП 15.5).
--
-- Реплики питомца и тексты уведомлений переезжают из кода в базу. Причина
-- в КП 15.5: их правит Заказчик, а не разработчик, и ждать новой сборки
-- приложения ради одной запятой — не дело.
--
-- В коде они при этом остаются: по КП 1.1 приложение работает без сети, и
-- без запасного набора мишка молчал бы. Правило простое — с сервера
-- приезжает главное, локальный набор служит подстраховкой.

create table public.phrases (
  id text primary key,
  context text not null,
  ru text not null,
  en text not null,
  zh text not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.phrases is
  'Реплики питомца на трёх языках (КП 13.3, 13.4).';

create table public.notification_texts (
  kind text primary key,
  title_ru text not null, body_ru text not null,
  title_en text not null, body_en text not null,
  title_zh text not null, body_zh text not null,
  updated_at timestamptz not null default now()
);

comment on table public.notification_texts is
  'Тексты восьми типов уведомлений (КП 13.1, 13.4).';

alter table public.phrases enable row level security;
alter table public.notification_texts enable row level security;

-- Читают все вошедшие: тексты нужны самому приложению. Правит только
-- администратор из панели.
create policy phrases_read on public.phrases
  for select to authenticated using (true);

create policy phrases_write on public.phrases
  for all to authenticated
  using (public.is_staff('admin')) with check (public.is_staff('admin'));

create policy notification_texts_read on public.notification_texts
  for select to authenticated using (true);

create policy notification_texts_write on public.notification_texts
  for all to authenticated
  using (public.is_staff('admin')) with check (public.is_staff('admin'));

-- Тридцать реплик из кода (КП 13.3) — стартовый набор на согласование.
insert into public.phrases (id, context, ru, en, zh) values
  ('greeting_1', 'greeting', 'Ты пришёл! Я скучал.', 'You''re back! I missed you.', '你回来啦！我好想你。'),
  ('greeting_2', 'greeting', 'Привет! Что будем делать?', 'Hi! What shall we do?', '你好！我们做点什么呢？'),
  ('greeting_3', 'greeting', 'Я тебя ждал.', 'I was waiting for you.', '我一直在等你。'),
  ('idle_1', 'idle', 'Тут так уютно.', 'It''s so cosy here.', '这里好舒服。'),
  ('idle_2', 'idle', 'Посидим вместе?', 'Shall we sit together?', '我们一起坐会儿好吗？'),
  ('idle_3', 'idle', 'Я немного мечтаю.', 'I''m daydreaming a little.', '我在发呆呢。'),
  ('happy_1', 'happy', 'Мне сегодня так хорошо!', 'I feel so good today!', '我今天好开心！'),
  ('happy_2', 'happy', 'С тобой весело!', 'It''s fun with you!', '和你在一起真开心！'),
  ('sad_1', 'sad', 'Мне немножко грустно…', 'I''m a little sad…', '我有点难过……'),
  ('sad_2', 'sad', 'Побудь со мной, пожалуйста.', 'Please stay with me.', '请陪陪我。'),
  ('hungry_1', 'hungry', 'Я немного голоден…', 'I''m a little hungry…', '我有点饿了……'),
  ('hungry_2', 'hungry', 'В животике урчит.', 'My tummy is rumbling.', '我的肚子咕咕叫。'),
  ('hungry_3', 'hungry', 'А что у нас вкусненького?', 'Is there something tasty?', '有什么好吃的吗？'),
  ('sleepy_1', 'sleepy', 'Глазки закрываются…', 'My eyes are closing…', '我的眼睛快睁不开了……'),
  ('sleepy_2', 'sleepy', 'Пора в кроватку?', 'Is it time for bed?', '该睡觉了吗？'),
  ('dirty_1', 'dirty', 'Кажется, я испачкался.', 'I think I got dirty.', '我好像弄脏了。'),
  ('dirty_2', 'dirty', 'Хочу побрызгаться водичкой!', 'I want to splash in the water!', '我想玩水！'),
  ('after_feed_1', 'afterFeed', 'Ммм, вкусно! Спасибо.', 'Mmm, yummy! Thank you.', '嗯，真好吃！谢谢你。'),
  ('after_feed_2', 'afterFeed', 'Теперь я сытый и довольный.', 'Now I''m full and happy.', '我吃饱啦，好满足。'),
  ('after_wash_1', 'afterWash', 'Я чистенький!', 'I''m all clean!', '我干干净净啦！'),
  ('after_wash_2', 'afterWash', 'Пахну свежестью.', 'I smell so fresh.', '我身上香香的。'),
  ('after_play_1', 'afterPlay', 'Ещё разок, ещё!', 'Again, one more time!', '再来一次，再来！'),
  ('after_play_2', 'afterPlay', 'Это было весело!', 'That was fun!', '太好玩了！'),
  ('after_pet_1', 'afterPet', 'Мне так приятно…', 'That feels so nice…', '好舒服呀……'),
  ('after_pet_2', 'afterPet', 'Я тебя люблю.', 'I love you.', '我爱你。'),
  ('after_wake_1', 'afterWake', 'Доброе утро! Я выспался.', 'Good morning! I slept well.', '早上好！我睡得好香。'),
  ('invite_play_1', 'invitePlay', 'Поиграем вместе?', 'Shall we play together?', '我们一起玩好吗？'),
  ('invite_play_2', 'invitePlay', 'Я нашёл новую игру!', 'I found a new game!', '我发现了一个新游戏！'),
  ('invite_learn_1', 'inviteLearn', 'Научишь меня чему-нибудь?', 'Will you teach me something?', '你能教我点什么吗？'),
  ('stage_up_1', 'stageUp', 'Смотри, я подрос!', 'Look, I''ve grown up!', '你看，我长大了！');

-- Восемь типов уведомлений (КП 13.1). Тон тот же, что у реплик: мишка
-- просит, а не упрекает — по КП 6.2 вины и наказания в игре нет.
insert into public.notification_texts
  (kind, title_ru, body_ru, title_en, body_en, title_zh, body_zh) values
  ('hungry', 'Малыш проголодался', 'Кажется, пора перекусить.', 'Your little one is hungry', 'Looks like it is time for a snack.', '宝宝饿了', '好像该吃点东西了。'),
  ('play', 'Малыш зовёт играть', 'Ему скучно одному.', 'Your little one wants to play', 'It is dull all alone.', '宝宝想玩', '一个人有点无聊。'),
  ('sleep', 'Пора спать', 'Малыш зевает и трёт глаза.', 'Time for bed', 'Your little one is yawning.', '该睡觉了', '宝宝在打哈欠。'),
  ('task', 'Новое задание', 'Загляни в раздел обучения.', 'A new task', 'Take a look at the learning section.', '有新任务', '去学习区看看吧。'),
  ('gift', 'Подарок ждёт', 'Кто-то приготовил сюрприз.', 'A gift is waiting', 'Someone left a surprise.', '有礼物', '有人给你准备了惊喜。'),
  ('stage', 'Малыш подрос', 'Открылось что-то новое.', 'Your little one grew up', 'Something new has opened.', '宝宝长大了', '有新内容解锁了。'),
  ('event', 'Сегодня особенный день', 'Заходи, расскажу.', 'Today is special', 'Come in, I will tell you.', '今天很特别', '快来，我告诉你。'),
  ('shop', 'Новинки в магазине', 'Появились новые вещи.', 'New in the shop', 'Fresh things have arrived.', '商店上新', '有新东西啦。');

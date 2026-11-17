-- 0032: место вещи в игровой (КП 10.7), модерация имён и снятие доступа
-- в панели (КП 15.6, 15.7), задания обучения в панели (КП 15.5) — проверка 17.11.
--
-- Сервер хранил только «вещь выставлена», без места: после перезапуска
-- приложение не знало, куда её ставить, и вещи снова лежали в ленте
-- обустройства. Теперь у строки есть место — id из `roomSlots`
-- (`lib/game/room_slots.dart`), например 'nursery.floor_left'.
--
-- Только добавление колонки: старые строки получают null (вещь ждёт в
-- ленте, как раньше), старые сборки колонку не знают и не трогают. Права
-- те же — политика room_layout_all (0002) покрывает всю строку. Снимок
-- функций места не несёт: приложение дочитывает его своим запросом
-- (`SupabaseStore._roomSlots`).

alter table public.room_layout add column if not exists slot text;

comment on column public.room_layout.slot is
  'Место в игровой (id из roomSlots приложения). null — вещь выставлена без места: стена, пол или старая запись.';

-- --- Модерация имён доходит до мишки (КП 15.6, проверка 17.11) --------------
--
-- «Принять» и «Отклонить» в панели меняли только строку очереди, а имя
-- мишки оставалось как было. Теперь решение модератора переносится на
-- мишку — если имя с тех пор не поменяли:
--   * принято — pets.name_status = 'approved';
--   * отклонено — имя возвращается к «Мой малыш», name_status = 'rejected'.
--     Приложение по этой пометке просит придумать другое (named_at не
--     трогаем — видео рождения второй раз не показывается).

create or replace function public.apply_name_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.pet_id is null or new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'approved' then
    update public.pets
    set name_status = 'approved'
    where id = new.pet_id and name = new.name;
  elsif new.status = 'rejected' then
    update public.pets
    set name = 'Мой малыш', name_status = 'rejected'
    where id = new.pet_id and name = new.name;
  end if;

  return new;
end;
$$;

revoke execute on function public.apply_name_decision() from public, anon, authenticated;

drop trigger if exists on_name_decision on public.name_moderation;
create trigger on_name_decision
  after update of status on public.name_moderation
  for each row execute function public.apply_name_decision();

-- --- «Убрать» в «Доступах» снимает роль (КП 15.7, проверка 17.11) -----------
--
-- Кнопка удаляла только приглашение, а выданная при регистрации роль в
-- staff оставалась: убранный сотрудник продолжал входить в панель.
-- Теперь вместе с приглашением снимается и роль этой почты. Свою роль так
-- снять нельзя — чтобы администратор не закрыл вход сам себе.

create or replace function public.revoke_staff_on_uninvite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.staff s
  using auth.users u
  where s.user_id = u.id
    and lower(u.email) = lower(old.email)
    and u.id is distinct from auth.uid();
  return old;
end;
$$;

revoke execute on function public.revoke_staff_on_uninvite() from public, anon, authenticated;

drop trigger if exists on_staff_uninvite on public.staff_invites;
create trigger on_staff_uninvite
  after delete on public.staff_invites
  for each row execute function public.revoke_staff_on_uninvite();


-- --- Задания обучения из панели (КП 9.4, 15.5, проверка 17.11) ---------------
--
-- 300 заданий были зашиты в сборку, раздела в панели не было. Теперь они в
-- таблице: администратор правит вопрос, варианты и верный ответ, приложение
-- берёт уровень с сервера, а без сети — из сборки (`learning_content.dart`).
-- Начальное наполнение — ровно те задания, что в сборке. Строк не
-- добавляют и не удаляют: 3 категории × 10 уровней × 10 заданий (КП 9.4).

create table if not exists public.edu_tasks (
  category text not null check (category in ('colors', 'count', 'world')),
  level integer not null check (level between 1 and 10),
  idx integer not null check (idx between 1 and 10),
  ru text not null check (char_length(trim(ru)) > 0),
  en text not null check (char_length(trim(en)) > 0),
  zh text not null check (char_length(trim(zh)) > 0),
  options jsonb not null check (
    jsonb_typeof(options) = 'array' and jsonb_array_length(options) = 4),
  correct integer not null check (correct between 0 and 3),
  updated_at timestamptz not null default now(),
  primary key (category, level, idx)
);

comment on table public.edu_tasks is
  'Задания обучения (КП 9.4, 15.5): 3 категории × 10 уровней × 10 заданий. Правятся в панели.';

alter table public.edu_tasks enable row level security;

drop policy if exists edu_tasks_read on public.edu_tasks;
create policy edu_tasks_read on public.edu_tasks
  for select to authenticated using (true);

drop policy if exists edu_tasks_write on public.edu_tasks;
create policy edu_tasks_write on public.edu_tasks
  for update to authenticated
  using (public.is_staff('admin')) with check (public.is_staff('admin'));

insert into public.edu_tasks (category, level, idx, ru, en, zh, options, correct) values
  ('colors', 1, 1, 'Найди красный', 'Find the red one', '找出红色的', '["🟡","⚫️","🟣","🔴"]'::jsonb, 3),
  ('colors', 1, 2, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🔴","🟤","🟣","🟢"]'::jsonb, 3),
  ('colors', 1, 3, 'Найди синий', 'Find the blue one', '找出蓝色的', '["⚪️","🟡","🔴","🔵"]'::jsonb, 3),
  ('colors', 1, 4, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟡","⚫️","🔵","🔴"]'::jsonb, 0),
  ('colors', 1, 5, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["🟣","⚫️","🟢","🟠"]'::jsonb, 3),
  ('colors', 1, 6, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟢","🔵","🟣","🟡"]'::jsonb, 2),
  ('colors', 1, 7, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["🔵","🟤","⚫️","🟡"]'::jsonb, 1),
  ('colors', 1, 8, 'Найди чёрный', 'Find the black one', '找出黑色的', '["🟠","🔵","⚫️","🔴"]'::jsonb, 2),
  ('colors', 1, 9, 'Найди белый', 'Find the white one', '找出白色的', '["🟣","🔴","🟢","⚪️"]'::jsonb, 3),
  ('colors', 1, 10, 'Какого цвета банан?', 'What colour is a banana?', '香蕉是什么颜色？', '["🔵","🔴","🟡","⚪️"]'::jsonb, 2),
  ('colors', 2, 1, 'Какого цвета помидор?', 'What colour is a tomato?', '西红柿是什么颜色？', '["🟡","🔴","⚫️","🟠"]'::jsonb, 1),
  ('colors', 2, 2, 'Какого цвета трава?', 'What colour is grass?', '青草是什么颜色？', '["🟠","⚪️","🔴","🟢"]'::jsonb, 3),
  ('colors', 2, 3, 'Какого цвета баклажан?', 'What colour is an eggplant?', '茄子是什么颜色？', '["🟠","🟢","🟤","🟣"]'::jsonb, 3),
  ('colors', 2, 4, 'Какого цвета апельсин?', 'What colour is an orange?', '橙子是什么颜色？', '["🟠","🟢","⚫️","🟣"]'::jsonb, 0),
  ('colors', 2, 5, 'Какого цвета шоколад?', 'What colour is chocolate?', '巧克力是什么颜色？', '["🟢","🟤","🟠","⚫️"]'::jsonb, 1),
  ('colors', 2, 6, 'Какого цвета море?', 'What colour is the sea?', '大海是什么颜色？', '["🔵","🟠","🟣","🟡"]'::jsonb, 0),
  ('colors', 2, 7, 'Какого цвета снег?', 'What colour is snow?', '雪是什么颜色？', '["🔵","🟣","⚪️","🟡"]'::jsonb, 2),
  ('colors', 2, 8, 'Какого цвета луна?', 'What colour is the moon?', '月亮是什么颜色？', '["🟡","🟣","🔴","🟠"]'::jsonb, 0),
  ('colors', 2, 9, 'Какого цвета клубника?', 'What colour is a strawberry?', '草莓是什么颜色？', '["🔴","🟢","🟡","⚪️"]'::jsonb, 0),
  ('colors', 2, 10, 'Какого цвета авокадо?', 'What colour is an avocado?', '牛油果是什么颜色？', '["🟢","🟣","🟡","🔴"]'::jsonb, 0),
  ('colors', 3, 1, 'Какого цвета виноград?', 'What colour is grapes?', '葡萄是什么颜色？', '["🟤","🟣","⚫️","🔴"]'::jsonb, 1),
  ('colors', 3, 2, 'Где круг?', 'Where is a circle?', '哪个是圆形？', '["⭐️","⭕️","⬛️","🔺"]'::jsonb, 1),
  ('colors', 3, 3, 'Где треугольник?', 'Where is a triangle?', '哪个是三角形？', '["⬛️","🔶","🔺","⭐️"]'::jsonb, 2),
  ('colors', 3, 4, 'Где квадрат?', 'Where is a square?', '哪个是正方形？', '["⬛️","⭕️","🔺","⭐️"]'::jsonb, 0),
  ('colors', 3, 5, 'Где звезда?', 'Where is a star?', '哪个是星形？', '["❤️","🔶","⬛️","⭐️"]'::jsonb, 3),
  ('colors', 3, 6, 'Где сердце?', 'Where is a heart?', '哪个是心形？', '["🔶","❤️","🔺","⬛️"]'::jsonb, 1),
  ('colors', 3, 7, 'Где ромб?', 'Where is a diamond?', '哪个是菱形？', '["🔶","⭕️","🔺","❤️"]'::jsonb, 0),
  ('colors', 3, 8, 'Найди белый', 'Find the white one', '找出白色的', '["🟢","🟤","⚪️","🟠"]'::jsonb, 2),
  ('colors', 3, 9, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟢","🔵","🟠","🟣"]'::jsonb, 3),
  ('colors', 3, 10, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🔵","🔴","🟣","🟢"]'::jsonb, 0),
  ('colors', 4, 1, 'Найди чёрный', 'Find the black one', '找出黑色的', '["⚫️","🟣","🟡","⚪️"]'::jsonb, 0),
  ('colors', 4, 2, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["🟢","🔵","⚫️","🟤"]'::jsonb, 3),
  ('colors', 4, 3, 'Найди чёрный', 'Find the black one', '找出黑色的', '["🟢","🟣","⚫️","🟠"]'::jsonb, 2),
  ('colors', 4, 4, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟣","🔵","🟤","🟠"]'::jsonb, 0),
  ('colors', 4, 5, 'Найди белый', 'Find the white one', '找出白色的', '["🟣","🔴","⚪️","🟡"]'::jsonb, 2),
  ('colors', 4, 6, 'Найди красный', 'Find the red one', '找出红色的', '["🟤","⚫️","🟠","🔴"]'::jsonb, 3),
  ('colors', 4, 7, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟡","🔴","🟤","⚫️"]'::jsonb, 0),
  ('colors', 4, 8, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["⚪️","🟤","🔵","🟢"]'::jsonb, 1),
  ('colors', 4, 9, 'Найди белый', 'Find the white one', '找出白色的', '["🟤","🔵","⚪️","⚫️"]'::jsonb, 2),
  ('colors', 4, 10, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🔵","🟡","⚫️","🟠"]'::jsonb, 1),
  ('colors', 5, 1, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟢","🟣","⚪️","🟤"]'::jsonb, 1),
  ('colors', 5, 2, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟡","🟠","🟤","🟣"]'::jsonb, 0),
  ('colors', 5, 3, 'Найди чёрный', 'Find the black one', '找出黑色的', '["🔵","⚫️","🟠","🟡"]'::jsonb, 1),
  ('colors', 5, 4, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🔴","🔵","🟤","⚫️"]'::jsonb, 1),
  ('colors', 5, 5, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🟤","🟢","🟣","🔵"]'::jsonb, 1),
  ('colors', 5, 6, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🟠","🔵","⚪️","🟢"]'::jsonb, 1),
  ('colors', 5, 7, 'Найди чёрный', 'Find the black one', '找出黑色的', '["⚫️","🟠","🟣","🟡"]'::jsonb, 0),
  ('colors', 5, 8, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🔴","⚫️","🟢","🟡"]'::jsonb, 2),
  ('colors', 5, 9, 'Найди белый', 'Find the white one', '找出白色的', '["⚫️","⚪️","🔴","🟡"]'::jsonb, 1),
  ('colors', 5, 10, 'Найди чёрный', 'Find the black one', '找出黑色的', '["⚫️","🟡","🟢","🔴"]'::jsonb, 0),
  ('colors', 6, 1, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🔵","🟣","🔴","🟤"]'::jsonb, 1),
  ('colors', 6, 2, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["🔵","🟢","⚫️","🟤"]'::jsonb, 3),
  ('colors', 6, 3, 'Найди чёрный', 'Find the black one', '找出黑色的', '["🔴","⚫️","⚪️","🟠"]'::jsonb, 1),
  ('colors', 6, 4, 'Найди чёрный', 'Find the black one', '找出黑色的', '["⚪️","🟠","🟣","⚫️"]'::jsonb, 3),
  ('colors', 6, 5, 'Найди белый', 'Find the white one', '找出白色的', '["🔴","🟠","🟣","⚪️"]'::jsonb, 3),
  ('colors', 6, 6, 'Найди зелёный', 'Find the green one', '找出绿色的', '["⚪️","🟢","⚫️","🟠"]'::jsonb, 1),
  ('colors', 6, 7, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟡","🟠","⚪️","🔵"]'::jsonb, 0),
  ('colors', 6, 8, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["🟤","🟢","🟣","🟠"]'::jsonb, 3),
  ('colors', 6, 9, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🔵","⚪️","🔴","⚫️"]'::jsonb, 0),
  ('colors', 6, 10, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🟣","🔴","🟢","⚪️"]'::jsonb, 2),
  ('colors', 7, 1, 'Найди белый', 'Find the white one', '找出白色的', '["⚪️","🟡","🟢","🟤"]'::jsonb, 0),
  ('colors', 7, 2, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["🟣","🔴","🟤","🟠"]'::jsonb, 2),
  ('colors', 7, 3, 'Найди красный', 'Find the red one', '找出红色的', '["🔵","🟢","🟤","🔴"]'::jsonb, 3),
  ('colors', 7, 4, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["⚫️","🟣","🟡","🟤"]'::jsonb, 1),
  ('colors', 7, 5, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🟤","⚪️","🟢","🔴"]'::jsonb, 2),
  ('colors', 7, 6, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟤","🟢","🔵","🟣"]'::jsonb, 3),
  ('colors', 7, 7, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟡","🔴","⚫️","🟠"]'::jsonb, 0),
  ('colors', 7, 8, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["🟠","⚪️","🔴","🟤"]'::jsonb, 0),
  ('colors', 7, 9, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟡","🟤","🟠","🔴"]'::jsonb, 0),
  ('colors', 7, 10, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🔵","⚪️","🟤","🟣"]'::jsonb, 3),
  ('colors', 8, 1, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟢","🟣","🔵","🟤"]'::jsonb, 1),
  ('colors', 8, 2, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟢","🔴","🟣","⚫️"]'::jsonb, 2),
  ('colors', 8, 3, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟣","🟡","🟤","🟠"]'::jsonb, 0),
  ('colors', 8, 4, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["⚪️","🟢","🔴","🟣"]'::jsonb, 3),
  ('colors', 8, 5, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟣","🔴","🟡","🔵"]'::jsonb, 0),
  ('colors', 8, 6, 'Найди белый', 'Find the white one', '找出白色的', '["🔴","⚪️","🟢","🔵"]'::jsonb, 1),
  ('colors', 8, 7, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["⚫️","🟤","🔵","🟣"]'::jsonb, 3),
  ('colors', 8, 8, 'Найди красный', 'Find the red one', '找出红色的', '["🔵","🔴","⚪️","🟠"]'::jsonb, 1),
  ('colors', 8, 9, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🟡","🟢","⚫️","🔵"]'::jsonb, 3),
  ('colors', 8, 10, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🟡","🔵","🔴","🟣"]'::jsonb, 1),
  ('colors', 9, 1, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["🟠","🟢","🔴","🟤"]'::jsonb, 3),
  ('colors', 9, 2, 'Найди белый', 'Find the white one', '找出白色的', '["🟣","🔴","⚪️","🔵"]'::jsonb, 2),
  ('colors', 9, 3, 'Найди белый', 'Find the white one', '找出白色的', '["⚪️","🟢","🟤","🟣"]'::jsonb, 0),
  ('colors', 9, 4, 'Найди фиолетовый', 'Find the purple one', '找出紫色的', '["🟣","🟡","🔵","⚪️"]'::jsonb, 0),
  ('colors', 9, 5, 'Найди красный', 'Find the red one', '找出红色的', '["🔵","🔴","🟣","🟡"]'::jsonb, 1),
  ('colors', 9, 6, 'Найди чёрный', 'Find the black one', '找出黑色的', '["🟤","🟣","⚫️","🔵"]'::jsonb, 2),
  ('colors', 9, 7, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["🔵","⚪️","🟤","🟡"]'::jsonb, 2),
  ('colors', 9, 8, 'Найди синий', 'Find the blue one', '找出蓝色的', '["🟠","🔴","🔵","🟣"]'::jsonb, 2),
  ('colors', 9, 9, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["🟠","🔴","🔵","🟢"]'::jsonb, 0),
  ('colors', 9, 10, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🟢","🔵","🟠","🟣"]'::jsonb, 0),
  ('colors', 10, 1, 'Найди белый', 'Find the white one', '找出白色的', '["🟢","⚪️","🟤","🔵"]'::jsonb, 1),
  ('colors', 10, 2, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🔴","⚫️","🟣","🟡"]'::jsonb, 3),
  ('colors', 10, 3, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["⚫️","🟤","🟢","🟡"]'::jsonb, 3),
  ('colors', 10, 4, 'Найди коричневый', 'Find the brown one', '找出棕色的', '["⚪️","🟤","🔴","🟢"]'::jsonb, 1),
  ('colors', 10, 5, 'Найди жёлтый', 'Find the yellow one', '找出黄色的', '["🟤","🟣","⚪️","🟡"]'::jsonb, 3),
  ('colors', 10, 6, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["⚫️","🟠","🟤","⚪️"]'::jsonb, 1),
  ('colors', 10, 7, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["🟠","🔵","🟡","🔴"]'::jsonb, 0),
  ('colors', 10, 8, 'Найди оранжевый', 'Find the orange one', '找出橙色的', '["🟣","🟡","🟠","🔵"]'::jsonb, 2),
  ('colors', 10, 9, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🟣","⚪️","🟢","🟡"]'::jsonb, 2),
  ('colors', 10, 10, 'Найди зелёный', 'Find the green one', '找出绿色的', '["🟢","🟤","⚪️","🔴"]'::jsonb, 0),
  ('count', 1, 1, '🌼🌼
Сколько здесь предметов?', '🌼🌼
How many are there?', '🌼🌼
这里有几个？', '["3","2","5","1"]'::jsonb, 1),
  ('count', 1, 2, '⭐️⭐️⭐️⭐️
Сколько здесь предметов?', '⭐️⭐️⭐️⭐️
How many are there?', '⭐️⭐️⭐️⭐️
这里有几个？', '["4","8","3","1"]'::jsonb, 0),
  ('count', 1, 3, '🌼🌼🌼
Сколько здесь предметов?', '🌼🌼🌼
How many are there?', '🌼🌼🌼
这里有几个？', '["2","3","5","4"]'::jsonb, 1),
  ('count', 1, 4, '🎈🎈🎈
Сколько здесь предметов?', '🎈🎈🎈
How many are there?', '🎈🎈🎈
这里有几个？', '["2","1","5","3"]'::jsonb, 3),
  ('count', 1, 5, '🐞🐞🐞🐞🐞
Сколько здесь предметов?', '🐞🐞🐞🐞🐞
How many are there?', '🐞🐞🐞🐞🐞
这里有几个？', '["3","8","5","7"]'::jsonb, 2),
  ('count', 1, 6, '🍎🍎🍎🍎
Сколько здесь предметов?', '🍎🍎🍎🍎
How many are there?', '🍎🍎🍎🍎
这里有几个？', '["2","8","3","4"]'::jsonb, 3),
  ('count', 1, 7, '🐟🐟🐟🐟
Сколько здесь предметов?', '🐟🐟🐟🐟
How many are there?', '🐟🐟🐟🐟
这里有几个？', '["3","6","4","7"]'::jsonb, 2),
  ('count', 1, 8, '🐟🐟🐟🐟🐟
Сколько здесь предметов?', '🐟🐟🐟🐟🐟
How many are there?', '🐟🐟🐟🐟🐟
这里有几个？', '["8","9","5","3"]'::jsonb, 2),
  ('count', 1, 9, '🍋🍋
Сколько здесь предметов?', '🍋🍋
How many are there?', '🍋🍋
这里有几个？', '["4","2","1","9"]'::jsonb, 1),
  ('count', 1, 10, '🎈🎈🎈🎈🎈
Сколько здесь предметов?', '🎈🎈🎈🎈🎈
How many are there?', '🎈🎈🎈🎈🎈
这里有几个？', '["5","4","7","1"]'::jsonb, 0),
  ('count', 2, 1, '🍎🍎🍎🍎
Сколько здесь предметов?', '🍎🍎🍎🍎
How many are there?', '🍎🍎🍎🍎
这里有几个？', '["6","4","8","3"]'::jsonb, 1),
  ('count', 2, 2, '🌼🌼🌼
Сколько здесь предметов?', '🌼🌼🌼
How many are there?', '🌼🌼🌼
这里有几个？', '["8","3","5","7"]'::jsonb, 1),
  ('count', 2, 3, '🐟🐟🐟🐟
Сколько здесь предметов?', '🐟🐟🐟🐟
How many are there?', '🐟🐟🐟🐟
这里有几个？', '["7","6","8","4"]'::jsonb, 3),
  ('count', 2, 4, '🍋🍋🍋🍋🍋
Сколько здесь предметов?', '🍋🍋🍋🍋🍋
How many are there?', '🍋🍋🍋🍋🍋
这里有几个？', '["3","1","6","5"]'::jsonb, 3),
  ('count', 2, 5, '🎈🎈🎈🎈
Сколько здесь предметов?', '🎈🎈🎈🎈
How many are there?', '🎈🎈🎈🎈
这里有几个？', '["8","3","5","4"]'::jsonb, 3),
  ('count', 2, 6, '🧸
Сколько здесь предметов?', '🧸
How many are there?', '🧸
这里有几个？', '["3","9","1","6"]'::jsonb, 2),
  ('count', 2, 7, '🍪🍪
Сколько здесь предметов?', '🍪🍪
How many are there?', '🍪🍪
这里有几个？', '["2","5","6","8"]'::jsonb, 0),
  ('count', 2, 8, '🧸🧸🧸🧸🧸
Сколько здесь предметов?', '🧸🧸🧸🧸🧸
How many are there?', '🧸🧸🧸🧸🧸
这里有几个？', '["2","9","5","6"]'::jsonb, 2),
  ('count', 2, 9, '🐞🐞🐞🐞🐞
Сколько здесь предметов?', '🐞🐞🐞🐞🐞
How many are there?', '🐞🐞🐞🐞🐞
这里有几个？', '["5","7","4","1"]'::jsonb, 0),
  ('count', 2, 10, '⭐️
Сколько здесь предметов?', '⭐️
How many are there?', '⭐️
这里有几个？', '["1","8","3","4"]'::jsonb, 0),
  ('count', 3, 1, '⭐️⭐️⭐️
Сколько здесь предметов?', '⭐️⭐️⭐️
How many are there?', '⭐️⭐️⭐️
这里有几个？', '["3","5","8","6"]'::jsonb, 0),
  ('count', 3, 2, '⭐️⭐️
Сколько здесь предметов?', '⭐️⭐️
How many are there?', '⭐️⭐️
这里有几个？', '["8","2","4","9"]'::jsonb, 1),
  ('count', 3, 3, '🌼🌼🌼🌼🌼
Сколько здесь предметов?', '🌼🌼🌼🌼🌼
How many are there?', '🌼🌼🌼🌼🌼
这里有几个？', '["7","4","5","3"]'::jsonb, 2),
  ('count', 3, 4, '🐟🐟🐟
Сколько здесь предметов?', '🐟🐟🐟
How many are there?', '🐟🐟🐟
这里有几个？', '["6","2","9","3"]'::jsonb, 3),
  ('count', 3, 5, '🐟🐟
Сколько здесь предметов?', '🐟🐟
How many are there?', '🐟🐟
这里有几个？', '["2","1","9","3"]'::jsonb, 0),
  ('count', 3, 6, '⭐️
Сколько здесь предметов?', '⭐️
How many are there?', '⭐️
这里有几个？', '["1","8","3","2"]'::jsonb, 0),
  ('count', 3, 7, '🍪🍪🍪
Сколько здесь предметов?', '🍪🍪🍪
How many are there?', '🍪🍪🍪
这里有几个？', '["4","9","2","3"]'::jsonb, 3),
  ('count', 3, 8, '🧸🧸🧸🧸
Сколько здесь предметов?', '🧸🧸🧸🧸
How many are there?', '🧸🧸🧸🧸
这里有几个？', '["4","1","8","9"]'::jsonb, 0),
  ('count', 3, 9, '🍪🍪🍪🍪🍪
Сколько здесь предметов?', '🍪🍪🍪🍪🍪
How many are there?', '🍪🍪🍪🍪🍪
这里有几个？', '["8","6","2","5"]'::jsonb, 3),
  ('count', 3, 10, '🧸🧸
Сколько здесь предметов?', '🧸🧸
How many are there?', '🧸🧸
这里有几个？', '["1","2","7","3"]'::jsonb, 1),
  ('count', 4, 1, '⭐️⭐️⭐️
Сколько здесь предметов?', '⭐️⭐️⭐️
How many are there?', '⭐️⭐️⭐️
这里有几个？', '["1","3","7","4"]'::jsonb, 1),
  ('count', 4, 2, '🌼🌼
Сколько здесь предметов?', '🌼🌼
How many are there?', '🌼🌼
这里有几个？', '["2","9","5","6"]'::jsonb, 0),
  ('count', 4, 3, '⭐️⭐️⭐️⭐️
Сколько здесь предметов?', '⭐️⭐️⭐️⭐️
How many are there?', '⭐️⭐️⭐️⭐️
这里有几个？', '["8","6","4","3"]'::jsonb, 2),
  ('count', 4, 4, '🍎🍎🍎🍎🍎
Сколько здесь предметов?', '🍎🍎🍎🍎🍎
How many are there?', '🍎🍎🍎🍎🍎
这里有几个？', '["3","9","5","4"]'::jsonb, 2),
  ('count', 4, 5, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🐭","🚪","🪨","🐘"]'::jsonb, 3),
  ('count', 4, 6, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🐭","🐘","🏠","🗻"]'::jsonb, 0),
  ('count', 4, 7, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🐟","🐳","🚪","🚌"]'::jsonb, 1),
  ('count', 4, 8, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🐟","🐳","🐝","🚌"]'::jsonb, 0),
  ('count', 4, 9, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🌱","🐘","🐳","🌳"]'::jsonb, 3),
  ('count', 4, 10, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🌳","🐻","🚲","🌱"]'::jsonb, 3),
  ('count', 5, 1, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🚪","🏠","🐟","🐭"]'::jsonb, 1),
  ('count', 5, 2, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🚪","🏠","🚌","🗻"]'::jsonb, 0),
  ('count', 5, 3, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🚲","🌳","🚌","🐻"]'::jsonb, 2),
  ('count', 5, 4, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🚲","🚌","🐳","🐘"]'::jsonb, 0),
  ('count', 5, 5, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🍇","🚌","🐭","🍉"]'::jsonb, 3),
  ('count', 5, 6, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🍉","🚲","🍇","🐭"]'::jsonb, 2),
  ('count', 5, 7, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🐝","🐻","🐭","🪨"]'::jsonb, 1),
  ('count', 5, 8, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🐻","🚪","🪨","🐝"]'::jsonb, 3),
  ('count', 5, 9, 'Кто больше?', 'Which one is bigger?', '哪个更大？', '["🪨","🍉","🗻","🚲"]'::jsonb, 2),
  ('count', 5, 10, 'Кто меньше?', 'Which one is smaller?', '哪个更小？', '["🗻","🌳","🍇","🪨"]'::jsonb, 3),
  ('count', 6, 1, 'Какое число идёт за 1?', 'Which number comes after 1?', '1后面是哪个数字？', '["9","2","6","1"]'::jsonb, 1),
  ('count', 6, 2, 'Какое число идёт за 2?', 'Which number comes after 2?', '2后面是哪个数字？', '["5","4","3","2"]'::jsonb, 2),
  ('count', 6, 3, 'Какое число идёт за 3?', 'Which number comes after 3?', '3后面是哪个数字？', '["4","6","5","8"]'::jsonb, 0),
  ('count', 6, 4, 'Какое число идёт за 4?', 'Which number comes after 4?', '4后面是哪个数字？', '["1","5","9","2"]'::jsonb, 1),
  ('count', 6, 5, 'Какое число идёт за 5?', 'Which number comes after 5?', '5后面是哪个数字？', '["8","6","2","5"]'::jsonb, 1),
  ('count', 6, 6, 'Какое число идёт за 6?', 'Which number comes after 6?', '6后面是哪个数字？', '["4","1","7","6"]'::jsonb, 2),
  ('count', 6, 7, 'Какое число идёт за 7?', 'Which number comes after 7?', '7后面是哪个数字？', '["1","8","5","9"]'::jsonb, 1),
  ('count', 6, 8, 'Какое число идёт за 8?', 'Which number comes after 8?', '8后面是哪个数字？', '["8","9","3","4"]'::jsonb, 1),
  ('count', 6, 9, 'Какое число идёт перед 2?', 'Which number comes before 2?', '2前面是哪个数字？', '["2","7","1","4"]'::jsonb, 2),
  ('count', 6, 10, 'Какое число идёт перед 3?', 'Which number comes before 3?', '3前面是哪个数字？', '["3","2","5","8"]'::jsonb, 1),
  ('count', 7, 1, 'Какое число идёт перед 4?', 'Which number comes before 4?', '4前面是哪个数字？', '["4","8","1","3"]'::jsonb, 3),
  ('count', 7, 2, 'Какое число идёт перед 5?', 'Which number comes before 5?', '5前面是哪个数字？', '["2","4","5","3"]'::jsonb, 1),
  ('count', 7, 3, 'Какое число идёт перед 6?', 'Which number comes before 6?', '6前面是哪个数字？', '["5","1","2","8"]'::jsonb, 0),
  ('count', 7, 4, 'Какое число идёт перед 7?', 'Which number comes before 7?', '7前面是哪个数字？', '["4","8","6","9"]'::jsonb, 2),
  ('count', 7, 5, 'Какое число идёт перед 8?', 'Which number comes before 8?', '8前面是哪个数字？', '["1","2","7","8"]'::jsonb, 2),
  ('count', 7, 6, 'Какое число идёт перед 9?', 'Which number comes before 9?', '9前面是哪个数字？', '["8","6","9","2"]'::jsonb, 0),
  ('count', 7, 7, 'Сколько будет 1 + 1?', 'How much is 1 + 1?', '1 + 1等于几？', '["1","9","4","2"]'::jsonb, 3),
  ('count', 7, 8, 'Сколько будет 4 + 2?', 'How much is 4 + 2?', '4 + 2等于几？', '["3","5","2","6"]'::jsonb, 3),
  ('count', 7, 9, 'Сколько будет 3 + 3?', 'How much is 3 + 3?', '3 + 3等于几？', '["3","4","6","5"]'::jsonb, 2),
  ('count', 7, 10, 'Сколько будет 4 + 1?', 'How much is 4 + 1?', '4 + 1等于几？', '["3","2","5","4"]'::jsonb, 2),
  ('count', 8, 1, 'Сколько будет 3 + 3?', 'How much is 3 + 3?', '3 + 3等于几？', '["6","5","9","1"]'::jsonb, 0),
  ('count', 8, 2, 'Сколько будет 2 + 1?', 'How much is 2 + 1?', '2 + 1等于几？', '["9","1","3","5"]'::jsonb, 2),
  ('count', 8, 3, 'Сколько будет 5 + 2?', 'How much is 5 + 2?', '5 + 2等于几？', '["2","3","7","6"]'::jsonb, 2),
  ('count', 8, 4, 'Сколько будет 3 + 2?', 'How much is 3 + 2?', '3 + 2等于几？', '["5","1","9","8"]'::jsonb, 0),
  ('count', 8, 5, 'Сколько будет 3 + 4?', 'How much is 3 + 4?', '3 + 4等于几？', '["7","5","3","2"]'::jsonb, 0),
  ('count', 8, 6, 'Сколько будет 3 + 3?', 'How much is 3 + 3?', '3 + 3等于几？', '["9","8","2","6"]'::jsonb, 3),
  ('count', 8, 7, 'Сколько будет 5 + 3?', 'How much is 5 + 3?', '5 + 3等于几？', '["8","3","4","6"]'::jsonb, 0),
  ('count', 8, 8, 'Сколько будет 2 + 4?', 'How much is 2 + 4?', '2 + 4等于几？', '["1","6","4","2"]'::jsonb, 1),
  ('count', 8, 9, 'Сколько будет 4 + 3?', 'How much is 4 + 3?', '4 + 3等于几？', '["8","1","7","5"]'::jsonb, 2),
  ('count', 8, 10, 'Сколько будет 2 + 3?', 'How much is 2 + 3?', '2 + 3等于几？', '["6","4","5","2"]'::jsonb, 2),
  ('count', 9, 1, 'Сколько будет 5 + 1?', 'How much is 5 + 1?', '5 + 1等于几？', '["1","6","4","2"]'::jsonb, 1),
  ('count', 9, 2, 'Сколько будет 3 + 3?', 'How much is 3 + 3?', '3 + 3等于几？', '["9","6","3","4"]'::jsonb, 1),
  ('count', 9, 3, 'Сколько будет 2 + 2?', 'How much is 2 + 2?', '2 + 2等于几？', '["8","3","2","4"]'::jsonb, 3),
  ('count', 9, 4, 'Сколько будет 3 + 4?', 'How much is 3 + 4?', '3 + 4等于几？', '["7","4","3","6"]'::jsonb, 0),
  ('count', 9, 5, 'Сколько будет 5 + 4?', 'How much is 5 + 4?', '5 + 4等于几？', '["5","4","1","9"]'::jsonb, 3),
  ('count', 9, 6, 'Сколько будет 3 + 2?', 'How much is 3 + 2?', '3 + 2等于几？', '["5","1","6","7"]'::jsonb, 0),
  ('count', 9, 7, 'Сколько будет 5 + 4?', 'How much is 5 + 4?', '5 + 4等于几？', '["9","3","7","1"]'::jsonb, 0),
  ('count', 9, 8, 'Сколько будет 4 + 3?', 'How much is 4 + 3?', '4 + 3等于几？', '["1","7","3","5"]'::jsonb, 1),
  ('count', 9, 9, 'Сколько будет 2 + 2?', 'How much is 2 + 2?', '2 + 2等于几？', '["2","1","6","4"]'::jsonb, 3),
  ('count', 9, 10, 'Сколько будет 4 + 1?', 'How much is 4 + 1?', '4 + 1等于几？', '["6","5","1","8"]'::jsonb, 1),
  ('count', 10, 1, 'Сколько будет 4 + 3?', 'How much is 4 + 3?', '4 + 3等于几？', '["7","2","9","3"]'::jsonb, 0),
  ('count', 10, 2, 'Сколько будет 1 + 4?', 'How much is 1 + 4?', '1 + 4等于几？', '["8","5","9","4"]'::jsonb, 1),
  ('count', 10, 3, 'Сколько будет 1 + 4?', 'How much is 1 + 4?', '1 + 4等于几？', '["6","5","9","4"]'::jsonb, 1),
  ('count', 10, 4, 'Сколько будет 3 + 2?', 'How much is 3 + 2?', '3 + 2等于几？', '["8","6","1","5"]'::jsonb, 3),
  ('count', 10, 5, 'Сколько будет 4 + 2?', 'How much is 4 + 2?', '4 + 2等于几？', '["6","7","3","2"]'::jsonb, 0),
  ('count', 10, 6, 'Сколько будет 2 + 3?', 'How much is 2 + 3?', '2 + 3等于几？', '["9","3","6","5"]'::jsonb, 3),
  ('count', 10, 7, 'Сколько будет 5 + 2?', 'How much is 5 + 2?', '5 + 2等于几？', '["1","2","7","5"]'::jsonb, 2),
  ('count', 10, 8, 'Сколько будет 3 + 3?', 'How much is 3 + 3?', '3 + 3等于几？', '["6","9","8","7"]'::jsonb, 0),
  ('count', 10, 9, 'Сколько будет 3 + 3?', 'How much is 3 + 3?', '3 + 3等于几？', '["6","1","5","7"]'::jsonb, 0),
  ('count', 10, 10, 'Сколько будет 2 + 4?', 'How much is 2 + 4?', '2 + 4等于几？', '["1","7","2","6"]'::jsonb, 3),
  ('world', 1, 1, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🐬","🐈","🦋","🦅"]'::jsonb, 0),
  ('world', 1, 2, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🦀","✈️","🦈","🐖"]'::jsonb, 1),
  ('world', 1, 3, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["🐕","🐟","🦋","🐬"]'::jsonb, 0),
  ('world', 1, 4, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🍎","🌽","🐖","🐇"]'::jsonb, 0),
  ('world', 1, 5, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🌽","🍐","🐝","✈️"]'::jsonb, 0),
  ('world', 1, 6, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["🔦","⭐️","☀️","🌙"]'::jsonb, 2),
  ('world', 1, 7, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["🏖","🌙","☀️","🌻"]'::jsonb, 1),
  ('world', 1, 8, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🩴","🏖","🥕","🧤"]'::jsonb, 3),
  ('world', 1, 9, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["⛄️","☀️","🧤","🎿"]'::jsonb, 1),
  ('world', 1, 10, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["🦋","🐄","🐝","✈️"]'::jsonb, 1),
  ('world', 2, 1, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🦈","🐝","🐇","🐕"]'::jsonb, 1),
  ('world', 2, 2, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🐦","🦀","🐬","🐑"]'::jsonb, 3),
  ('world', 2, 3, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🐕","🐔","🦈","🐙"]'::jsonb, 1),
  ('world', 2, 4, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🦅","🐖","✈️","🐙"]'::jsonb, 3),
  ('world', 2, 5, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🐬","🦅","🐖","🐕"]'::jsonb, 1),
  ('world', 2, 6, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["✈️","🦀","🐕","🐟"]'::jsonb, 2),
  ('world', 2, 7, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🐄","🍐","🥔","🍅"]'::jsonb, 1),
  ('world', 2, 8, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🥕","🍎","🍊","🍐"]'::jsonb, 0),
  ('world', 2, 9, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["🌙","💡","🔦","☀️"]'::jsonb, 3),
  ('world', 2, 10, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["☀️","🌻","🏖","🌙"]'::jsonb, 3),
  ('world', 3, 1, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🩴","🌽","🎿","☀️"]'::jsonb, 2),
  ('world', 3, 2, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["🧤","🧣","☀️","🛷"]'::jsonb, 2),
  ('world', 3, 3, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["🐝","🦈","🐄","🐟"]'::jsonb, 2),
  ('world', 3, 4, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🐇","🐈","🐬","🐝"]'::jsonb, 3),
  ('world', 3, 5, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🐦","🐬","🐑","✈️"]'::jsonb, 2),
  ('world', 3, 6, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🦀","🐬","🐕","🦆"]'::jsonb, 3),
  ('world', 3, 7, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🐇","🦋","🐦","🦀"]'::jsonb, 3),
  ('world', 3, 8, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["✈️","🦈","🐟","🐕"]'::jsonb, 0),
  ('world', 3, 9, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["🐕","✈️","🐬","🐟"]'::jsonb, 0),
  ('world', 3, 10, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🐕","🐈","🥔","🍎"]'::jsonb, 3),
  ('world', 4, 1, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🍒","🐦","🦅","🥔"]'::jsonb, 3),
  ('world', 4, 2, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["🔦","☀️","🕯","💡"]'::jsonb, 1),
  ('world', 4, 3, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["🏖","🌻","⭐️","☀️"]'::jsonb, 2),
  ('world', 4, 4, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🍉","🥕","🥒","⛄️"]'::jsonb, 3),
  ('world', 4, 5, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["☀️","⛄️","🎿","🧣"]'::jsonb, 0),
  ('world', 4, 6, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["✈️","🦋","🐐","🦈"]'::jsonb, 2),
  ('world', 4, 7, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🐕","🐈","🐝","🐖"]'::jsonb, 2),
  ('world', 4, 8, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🐑","🐟","🦅","🐝"]'::jsonb, 0),
  ('world', 4, 9, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🦀","🐔","🦈","🐟"]'::jsonb, 1),
  ('world', 4, 10, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🐕","🐬","🐦","🦅"]'::jsonb, 1),
  ('world', 5, 1, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🐄","✈️","🐙","🐖"]'::jsonb, 1),
  ('world', 5, 2, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["🐦","🐟","🐖","🦋"]'::jsonb, 2),
  ('world', 5, 3, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🍒","🥔","🐕","🐈"]'::jsonb, 0),
  ('world', 5, 4, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🦋","🌽","🐦","🍎"]'::jsonb, 1),
  ('world', 5, 5, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["🌙","💡","☀️","🔦"]'::jsonb, 2),
  ('world', 5, 6, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["🌙","☀️","🌻","🏖"]'::jsonb, 0),
  ('world', 5, 7, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["☀️","🥔","🎿","🌽"]'::jsonb, 2),
  ('world', 5, 8, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["🍉","🧣","❄️","🧤"]'::jsonb, 0),
  ('world', 5, 9, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["🐐","🐬","🐟","🐝"]'::jsonb, 0),
  ('world', 5, 10, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🦀","🐖","🐝","🐕"]'::jsonb, 2),
  ('world', 6, 1, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🐑","🦋","🦀","🐙"]'::jsonb, 0),
  ('world', 6, 2, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🦈","🐈","🐔","🦀"]'::jsonb, 2),
  ('world', 6, 3, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🐖","🐇","🦋","🦈"]'::jsonb, 3),
  ('world', 6, 4, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🐈","🦀","🐦","🐬"]'::jsonb, 2),
  ('world', 6, 5, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["🐝","🐕","🐙","🐟"]'::jsonb, 1),
  ('world', 6, 6, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🐈","🐖","🐇","🍎"]'::jsonb, 3),
  ('world', 6, 7, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🍐","🍊","🥒","🍎"]'::jsonb, 2),
  ('world', 6, 8, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["☀️","🕯","⭐️","💡"]'::jsonb, 0),
  ('world', 6, 9, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["🌻","⭐️","🏖","☀️"]'::jsonb, 1),
  ('world', 6, 10, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🥔","❄️","🥒","🩴"]'::jsonb, 1),
  ('world', 7, 1, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["🎿","🧤","🏖","❄️"]'::jsonb, 2),
  ('world', 7, 2, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["✈️","🦀","🦈","🐐"]'::jsonb, 3),
  ('world', 7, 3, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🐕","🐝","🦀","🐬"]'::jsonb, 1),
  ('world', 7, 4, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🦋","🐟","🐑","🦀"]'::jsonb, 2),
  ('world', 7, 5, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🐕","🦈","🐈","🦆"]'::jsonb, 3),
  ('world', 7, 6, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🐄","🦋","🦈","🦅"]'::jsonb, 2),
  ('world', 7, 7, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🦅","🐈","🦈","🦀"]'::jsonb, 0),
  ('world', 7, 8, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["🐙","🐈","🦀","🦅"]'::jsonb, 1),
  ('world', 7, 9, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🥥","🍅","🌽","🐈"]'::jsonb, 0),
  ('world', 7, 10, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🦅","🐦","🥔","🍊"]'::jsonb, 2),
  ('world', 8, 1, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["🌙","☀️","🕯","🔦"]'::jsonb, 1),
  ('world', 8, 2, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["🌻","☀️","🌙","🏖"]'::jsonb, 2),
  ('world', 8, 3, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🍅","🧤","🥒","☀️"]'::jsonb, 1),
  ('world', 8, 4, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["⛄️","🧣","❄️","🏖"]'::jsonb, 3),
  ('world', 8, 5, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["🦅","🐐","✈️","🦀"]'::jsonb, 1),
  ('world', 8, 6, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🐄","🐇","🐙","🐝"]'::jsonb, 3),
  ('world', 8, 7, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🦈","🐝","🦋","🐑"]'::jsonb, 3),
  ('world', 8, 8, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🐔","🐈","🐕","🐬"]'::jsonb, 0),
  ('world', 8, 9, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🦀","🦅","🦋","🐕"]'::jsonb, 0),
  ('world', 8, 10, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🐙","🦀","🐕","🦋"]'::jsonb, 3),
  ('world', 9, 1, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["✈️","🐈","🦈","🦀"]'::jsonb, 1),
  ('world', 9, 2, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🐖","🐈","🍊","🐕"]'::jsonb, 2),
  ('world', 9, 3, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🍐","🥔","🐦","🍎"]'::jsonb, 1),
  ('world', 9, 4, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["☀️","💡","🔦","🕯"]'::jsonb, 0),
  ('world', 9, 5, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["🌻","🌙","🏖","☀️"]'::jsonb, 1),
  ('world', 9, 6, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🧤","🍅","🩴","🏖"]'::jsonb, 0),
  ('world', 9, 7, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["🎿","🧤","🩴","⛄️"]'::jsonb, 2),
  ('world', 9, 8, 'Кто даёт молоко?', 'Who gives milk?', '谁产奶？', '["🦈","🐄","🐝","🐟"]'::jsonb, 1),
  ('world', 9, 9, 'Кто делает мёд?', 'Who makes honey?', '谁酿蜜？', '["🐬","🐕","🐝","🦈"]'::jsonb, 2),
  ('world', 9, 10, 'У кого шерсть?', 'Who has wool?', '谁有羊毛？', '["🐑","🦅","🦋","🐦"]'::jsonb, 0),
  ('world', 10, 1, 'Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？', '["🐙","🦀","🦆","🦈"]'::jsonb, 2),
  ('world', 10, 2, 'Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？', '["🦈","🦅","🐈","🐝"]'::jsonb, 0),
  ('world', 10, 3, 'Кто умеет летать?', 'Who can fly?', '谁会飞？', '["🐝","🐙","🐈","🦈"]'::jsonb, 0),
  ('world', 10, 4, 'Кто живёт рядом с домом?', 'Who lives near the house?', '谁住在家附近？', '["🐟","🐇","🦈","✈️"]'::jsonb, 1),
  ('world', 10, 5, 'Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？', '["🐇","🐕","🐄","🍎"]'::jsonb, 3),
  ('world', 10, 6, 'Что растёт на грядке?', 'What grows in the garden bed?', '什么长在菜地里？', '["🦋","🥕","🍐","🐝"]'::jsonb, 1),
  ('world', 10, 7, 'Что светит днём?', 'What shines during the day?', '白天什么在发光？', '["💡","🌙","☀️","🔦"]'::jsonb, 2),
  ('world', 10, 8, 'Что видно ночью?', 'What can you see at night?', '夜里能看到什么？', '["☀️","🏖","🌻","⭐️"]'::jsonb, 3),
  ('world', 10, 9, 'Что бывает зимой?', 'What happens in winter?', '冬天有什么？', '["🍅","🏖","⛄️","🥒"]'::jsonb, 2),
  ('world', 10, 10, 'Что бывает летом?', 'What happens in summer?', '夏天有什么？', '["🧤","🛷","❄️","🍉"]'::jsonb, 3)
on conflict (category, level, idx) do nothing;

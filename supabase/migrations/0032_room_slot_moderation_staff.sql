-- 0032: место вещи в игровой (КП 10.7), модерация имён и снятие доступа
-- в панели (КП 15.6, 15.7) — проверка 17.11.
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

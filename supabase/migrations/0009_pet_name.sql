-- Имя питомца с фильтром слов (КП 2.3, 15.6).
--
-- Проверок две, и они разные по природе. Форму имени — длину и знаки —
-- проверяет приложение, пока человек печатает: это мгновенно и работает
-- офлайн. Содержание проверяет сервер, потому что список запрещённых слов
-- правит модератор из панели (КП 15.6), и клиент со старым списком
-- пропустил бы то, что уже запретили.
--
-- Длину сервер проверяет всё равно: клиент может быть старым, чужим или
-- поддельным, и «проверено на клиенте» — не проверено.

-- Базовый список. Заведомо неполный: это стартовый набор, дальше его ведёт
-- модератор. Хранится корнями, потому что окончания и приставки всё равно
-- не перечислить.
insert into public.name_blocklist (pattern, locale) values
  ('хуй', 'ru'), ('хуе', 'ru'), ('пизд', 'ru'), ('ебан', 'ru'),
  ('ебат', 'ru'), ('бляд', 'ru'), ('сука', 'ru'), ('мудак', 'ru'),
  ('гандон', 'ru'), ('пидор', 'ru'), ('пидар', 'ru'), ('залуп', 'ru'),
  ('дрочи', 'ru'), ('нахуй', 'ru'), ('уебок', 'ru'),
  ('fuck', 'en'), ('shit', 'en'), ('bitch', 'en'), ('cunt', 'en'),
  ('dick', 'en'), ('asshole', 'en'), ('bastard', 'en'), ('whore', 'en'),
  ('slut', 'en'), ('nigger', 'en'),
  ('傻逼', 'zh'), ('操你', 'zh'), ('妈的', 'zh'), ('混蛋', 'zh'),
  ('贱人', 'zh'), ('王八蛋', 'zh'), ('去死', 'zh')
on conflict (pattern, locale) do nothing;

-- Переименование питомца.
--
-- Возвращает снимок игрока целиком, как и остальные действия: имя видно в
-- шапке, в профиле и в дневнике, и собирать его отдельным запросом значило
-- бы дать экранам разъехаться между собой.
create or replace function public.rename_pet(
  p_pet_id uuid,
  p_name text,
  p_locale text default 'ru'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_len integer;
  v_hit text;
begin
  if not exists (
    select 1 from public.pets p
    where p.id = p_pet_id and p.player_id = auth.uid()
  ) then
    raise exception 'Питомец % не принадлежит игроку', p_pet_id;
  end if;

  -- Пробелы по краям срезаются, несколько подряд схлопываются: «  Тед  ди »
  -- и «Тед ди» — одно имя.
  v_name := regexp_replace(btrim(p_name), '\s+', ' ', 'g');
  v_len := char_length(v_name);

  if v_len < 2 then
    raise exception 'Имя короче двух знаков' using errcode = 'check_violation';
  end if;
  if v_len > 15 then
    raise exception 'Имя длиннее пятнадцати знаков'
      using errcode = 'check_violation';
  end if;

  -- Ищем по всем языкам сразу, а не только по языку интерфейса: человек с
  -- русским интерфейсом прекрасно напишет брань латиницей.
  select b.pattern into v_hit
  from public.name_blocklist b
  where lower(v_name) like '%' || lower(b.pattern) || '%'
     or lower(regexp_replace(v_name, '[\s''\-]', '', 'g'))
        like '%' || lower(b.pattern) || '%'
  limit 1;

  if v_hit is not null then
    -- Отказ записываем: модератору важно видеть, что пытались назвать, и
    -- по этим записям он правит список (КП 15.6).
    insert into public.name_moderation (pet_id, name, locale, status)
    values (p_pet_id, v_name, p_locale, 'rejected');

    raise exception 'Имя содержит запрещённое слово'
      using errcode = 'check_violation';
  end if;

  update public.pets
  set name = v_name,
      -- Имя принято автоматически, но помечено как ждущее проверки: список
      -- слов не ловит всё, и последнее слово за человеком (КП 15.6).
      name_status = 'pending'
  where id = p_pet_id;

  insert into public.name_moderation (pet_id, name, locale, status)
  values (p_pet_id, v_name, p_locale, 'pending');

  return public.pet_snapshot(p_pet_id);
end;
$$;

revoke all on function public.rename_pet(uuid, text, text) from public;
grant execute on function public.rename_pet(uuid, text, text) to authenticated;

-- Игровая: стены и пол — по 10 вариантов (заказчик 09.10,
-- docs/room-surfaces-answers.md). 4 бесплатно (цена 0 — buy_item
-- записывает источник 'free'), 6 за монеты. Цены — как в каталоге
-- приложения (lib/game/shop_items.dart). ⚠ ждут согласования (КП 10.9),
-- меняются из панели.
--
-- wall_sage («Шалфей») в 10 не вошёл — в пожеланиях Ирины
-- (docs/irina-wishes.md, строка 7). Ни у кого из игроков его нет, цену
-- убираем, чтобы его нельзя было купить.

update public.game_config
set value = (value - 'wall_sage') || '{
  "wall_rose": 0,
  "wall_cream": 0,
  "wall_mint": 0,
  "wall_dots": 0,
  "wall_forest": 60,
  "wall_clouds": 60,
  "wall_sprigs": 60,
  "wall_bunnies": 60,
  "wall_lavender": 40,
  "wall_sky": 40,
  "floor_wood": 0,
  "floor_honey": 0,
  "floor_greige": 0,
  "floor_laminate": 0,
  "floor_dark_oak": 40,
  "floor_checker": 50,
  "floor_carpet": 50,
  "floor_puzzle": 50,
  "floor_powder": 40,
  "floor_light": 40
}'::jsonb
where key = 'item_prices';

-- Цены на 22 товара, которые появились в магазине приложения, а на
-- сервере цены не имели.
--
-- Найдено сверкой 24.09 (заказчик: «списания идут именно по тем суммам,
-- которые указаны в магазине»): в приложении 74 товара, в item_prices —
-- 52. Покупку товара без цены сервер отклоняет (TT404), и приложение её
-- откатывало: кресла, полки, цветы, зайцы, кукольный домик купить было
-- нельзя. Остальные 52 цены, 10 блюд и 5 рецептов совпадали до монеты.
--
-- Цены — ровно как в каталоге приложения (lib/game/shop_items.dart).
-- Существующие цены не трогаем: объединение jsonb дописывает только новые
-- ключи, а совпадающие перезаписывает теми же числами.

update public.game_config
set value = value || '{
  "shelf_house": 150,
  "shelf_moon": 130,
  "armchair_sage": 170,
  "armchair_bean": 150,
  "armchair_flower": 180,
  "armchair_wing": 190,
  "swing": 200,
  "basket_star": 70,
  "rug_cloud": 110,
  "rug_heart": 110,
  "pic_heart": 60,
  "plant_ivy": 55,
  "plant_bear": 65,
  "flowers_daisy": 50,
  "flowers_orchid": 70,
  "flowers_euc": 55,
  "teddy_cream": 110,
  "bunny": 110,
  "bunny_pink": 110,
  "pyramid": 80,
  "dollhouse": 220,
  "house_felt": 160
}'::jsonb,
    updated_at = now()
where key = 'item_prices';

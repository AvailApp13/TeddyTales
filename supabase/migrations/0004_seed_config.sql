-- Стартовые настройки игры.
--
-- Все числа здесь — перенос того, что сейчас зашито в Dart, один к одному.
-- Смысл переноса не в значениях, а в том, что теперь их можно поменять из
-- панели управления без новой сборки приложения (КП 5.6, 15.4), и каждая
-- правка попадёт в историю изменений.

insert into public.game_config (key, value) values

-- Скорость падения показателей и безопасный предел (КП 6.1, 6.3).
-- В приложении это было «полная шкала за 4 часа» и так далее — здесь то же
-- самое, только в процентах за час, потому что настройку читает человек.
('decay', '{"floor": 20.0, "food_per_hour": 25.0, "hygiene_per_hour": 12.5, "love_per_hour": 10.0, "play_per_hour": 12.5, "sleep_per_hour": 16.667}'),

-- Насколько действие поднимает свой показатель (КП 6.4).
('care_gain', '{"feed": 35, "pet": 20, "play": 30, "sleep": 50, "wash": 40}'),

-- Монеты за действие ухода. Ориентир КП 11.1 — 80–120 монет в день:
-- пятнадцать-двадцать действий по пять монет плюс обучение дают как раз
-- этот диапазон.
('care_rewards', '{"decorate": 0, "dress": 0, "feed": 5, "learn": 0, "pet": 5, "play": 5, "sleep": 5, "wake": 0, "wash": 5}'),

-- Награда за новый уровень обучения (КП 9.5).
('edu', '{"level_reward": 10}'),

-- Длительности стадий в часах (КП 5, таблица взросления). Настраиваются с
-- сервера по требованию 5.6 — здесь значения из КП.
('stage_durations', '{"crawling": 48, "firstSteps": 36, "growing": 336, "newborn": 24}'),

-- Двенадцать предметов, которые даются бесплатно (КП 10.8).
('starting_items', '["bed", "rug", "lamp", "basket", "wall_rose", "floor_wood", "pillow_heart", "plant", "ball", "duck", "cubes", "out_yellow"]'),

-- Цены каталога (КП 10.9, 15.3). Значения предварительные — те же, что
-- сейчас в приложении; утверждаются отдельно.
('item_prices', '{"acc_bow": 60, "armchair": 130, "ball": 40, "basket": 50, "bed": 120, "bot_blue": 120, "bot_skirt": 125, "bot_yellow": 110, "cactus": 45, "car": 70, "chair": 70, "clock": 70, "cubes": 60, "dresser": 150, "drum": 80, "duck": 35, "floor_carpet": 35, "floor_light": 35, "floor_wood": 35, "garland": 65, "hat_cap": 90, "kite": 55, "lamp": 60, "out_bear": 200, "out_bee": 240, "out_berry": 220, "out_glasses": 100, "out_sailor": 180, "out_sport": 150, "out_winter": 190, "out_yellow": 160, "pic_bear": 55, "pic_forest": 55, "pic_moon": 55, "pillow_heart": 30, "pillow_star": 30, "plant": 45, "poster": 50, "puzzle": 65, "rocket": 85, "rug": 80, "shelf": 110, "table": 90, "teddy": 90, "top_blue": 140, "top_rose": 120, "top_sage": 130, "train": 95, "wall_rose": 40, "wall_sage": 40, "wall_sky": 40, "wardrobe": 140}');

# Кухня — что осталось (записано 01.10.2026)

## Задача на 02.10: 9 картинок в Higgsfield

Заказчик 01.10 дал «да» на генерацию (кредиты подтверждены). 01.10 сделано
5 из 14: рыба, курица (один вариант), паста с грибами — уже в приложении.
Остальное не прошло: аккаунт Higgsfield (тариф Max) в льготном периоде
подписки — «daily generation limit for your grace period». Кредиты (216,05)
на это не влияют, ограничение — от подписки. За 01.10 прошло 5 генераций,
дальше отказ; повтор того же дня — 0 из 9, ничего не списано.

**Перед запуском:** `balance`, затем отправить. Если снова отказ — не
повторять, сказать заказчику (подписка не продлена). Если лимит ~5 в день —
сначала продукты по порядку ниже, курицу-блюдо последней.

| № | Файл | Что | Промт (хвост после общего начала) |
|---|---|---|---|
| 1 | `ingredients/egg.webp` | яйцо (печенье) | one whole chicken egg, light brown shell. |
| 2 | `ingredients/chicken.webp` | курица (курица с овощами) | one raw chicken breast fillet, appetizing soft pink, clean and neat, not gory. |
| 3 | `ingredients/broccoli.webp` | брокколи | one fresh green broccoli head. |
| 4 | `ingredients/sauce.webp` | соус | a small cream-colored ceramic gravy boat filled with golden creamy sauce. |
| 5 | `ingredients/pasta.webp` | паста (паста с грибами) | a small neat pile of dry uncooked penne pasta, golden yellow. |
| 6 | `ingredients/mushrooms.webp` | грибы | two fresh white champignon mushrooms, one whole and one cut in half. |
| 7 | `ingredients/sour_cream.webp` | сметана | a small pastel ceramic pot of thick white sour cream with a soft swirl on top. |
| 8 | `ingredients/spoon.webp` | ложка «Перемешать» | (вместо «ingredient» — «kitchen tool») one light wooden cooking spoon for stirring, lying diagonally. |
| 9 | `dishes/chicken.webp` — второй вариант на выбор | курица на тарелке | см. ниже |

Общее начало продуктов (1–8), `gpt_image_2_5`, `aspect_ratio 1:1`,
`background transparent`, две картинки-образца `image_references` — сыр и
помидор:

> Single cooking ingredient for a cozy pastel teddy-bear game, exactly the
> same style, size, lighting and camera angle as the reference ingredients
> (cheese and tomato): soft 3D cute illustration, slight three-quarter view,
> light from the left, isolated on transparent background, no plate, no
> text. Ingredient: …

Курица-блюдо (9), `aspect_ratio 3:2`, образец — омлет:

> Ready-to-eat dish for a cozy pastel teddy-bear game, same style, camera
> angle, lighting and size as the reference plate: soft 3D cute
> illustration, seen slightly from above at a three-quarter angle, light
> from the left, isolated on transparent background, no table, no text.
> Dish: golden roasted chicken (a juicy chicken breast fillet and a small
> drumstick) with roasted potato wedges and broccoli florets, a little
> sauce, on the same round ceramic plate shape as the reference but the
> plate is soft pastel periwinkle color #CFD3F0.

Образцы (media id от 01.10; если устарели — заново `media_import_url` с
gh-pages, загрузка файлов напрямую закрыта прокси):

- сыр `c148d814-3d50-4398-9db0-b98928f65547` —
  `https://availapp13.github.io/TeddyTales/assets/assets/rooms/kitchen/ingredients/cheese.webp`
- помидор `9a0f9289-a038-45a0-b76f-c212b8bf4051` — `…/ingredients/tomato.webp`
- омлет `ab8db44b-000a-491e-88c0-807e832d8afa` — `…/dishes/omelette.webp`

**Дальше по шагам:**

1. Скачать: ссылки в `tool/fetch-media.json` → workflow
   `.github/workflows/fetch-media.yml` → ветка `claude/media-cache`
   (CDN Higgsfield прокси не пускает).
2. Продукты: обрезать прозрачные поля, длинная сторона 200 px, webp — как
   остальные в `assets/rooms/kitchen/ingredients/`. Имя файла = id продукта
   в `lib/game/food.dart`.
3. Курица: показать заказчику оба варианта, выбранный — 360 px по ширине в
   `assets/rooms/kitchen/dishes/chicken.webp`, затем
   `python3 tool/check_dish_paws.py` (блюдо не должно заходить на лапы).
4. `flutter analyze`, `flutter test`, коммит, пуш, пересобрать и
   опубликовать артефакт.

Эмодзи-заглушку в `kitchen_cooking.dart` (`errorBuilder`) не убирать — она
страхует от пропавшей картинки.

## Что ещё не закрыто на кухне (без мишки)

Сверка с ТЗ 01.10 (заказчику доложено, правки — только по его команде):

- **8.1 «подсказка от характера»** есть только в старом листе кормления
  (`feed_screen.dart`, `_HintBar`), в самой кухне её нет. Там же нет
  метки любимого блюда (7.4) на блюдах стола.
- **15.3 / 15.4 цены блюд и награды рецептов** в панели не правятся
  (`admin/index.html` показывает только числа верхнего уровня), а
  приложение показывает цены из кода (`food.dart`), не с сервера.
- **5, таблица стадий**: у новорождённого бутылочка — сделано; «все
  механики» открываются с «Подрастающего», а сейчас блюда и готовка
  открыты уже с «Ползающего» — ⚠ ждёт решения заказчика.

- **Решение заказчика: меню по стадиям после новорождённого.** Сейчас на
  всех стадиях, кроме новорождённого, доступны все 10 блюд
  (`docs/irina-wishes.md`, «Вопросы заказчику»).
- ~~«5 мини-игр» (КП 8.4)~~ — решено 01.10: строго по ТЗ, 5 рецептов на
  механике 8.4 = 5 мини-игр. Разные механики — в `docs/irina-wishes.md`.
- **Перед публикацией** (заглушки испытаний, `CLAUDE.md`): `kTestFood`,
  `kTestDishReturn`, `refuse_at` на сервере; плюс решить, как заполняется
  шкала «Еда» и сколько раз в день мишка просит есть.

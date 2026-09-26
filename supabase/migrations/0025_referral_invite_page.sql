-- 0025: ссылка приглашения ведёт на страницу приглашения (заказчик 26.09).
-- Страница копирует код друга и ведёт в приложение; после выхода в
-- App Store / Google Play адреса магазинов прописываются в web/invite.html.

update public.game_config
set value = value || jsonb_build_object(
  'link', 'https://availapp13.github.io/TeddyTales/invite.html')
where key = 'referral';

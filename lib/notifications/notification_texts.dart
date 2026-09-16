import '../bear/bear_phrases.dart' show BearLanguage;

/// Тексты уведомлений на трёх языках (КП 13.1, 13.4).
///
/// Те же восемь, что лежат в базе и правятся из панели (КП 15.5). Здесь —
/// запасной набор: уведомление планируется на устройстве заранее, иногда за
/// часы вперёд, и к моменту показа сети может не быть. Без локальной копии
/// в шторке появилось бы пустое место.
///
/// Тон выбран под КП 6.2: в игре нет ни болезней, ни наказания, поэтому
/// мишка просит, а не упрекает. «Малыш проголодался» вместо «Вы не кормили
/// питомца 6 часов» — второе читается как счёт к оплате.
class NotificationText {
  const NotificationText(this.kind, this._titles, this._bodies);

  final String kind;
  final Map<BearLanguage, String> _titles;
  final Map<BearLanguage, String> _bodies;

  String title(BearLanguage language) =>
      _titles[language] ?? _titles.values.first;
  String body(BearLanguage language) =>
      _bodies[language] ?? _bodies.values.first;
}

const Map<String, NotificationText> notificationTexts = {
  'hungry': NotificationText(
    'hungry',
    {
      BearLanguage.ru: 'Малыш проголодался',
      BearLanguage.en: 'Your little one is hungry',
      BearLanguage.zh: '宝宝饿了',
    },
    {
      BearLanguage.ru: 'Кажется, пора перекусить.',
      BearLanguage.en: 'Looks like it is time for a snack.',
      BearLanguage.zh: '好像该吃点东西了。',
    },
  ),
  'play': NotificationText(
    'play',
    {
      BearLanguage.ru: 'Малыш зовёт играть',
      BearLanguage.en: 'Your little one wants to play',
      BearLanguage.zh: '宝宝想玩',
    },
    {
      BearLanguage.ru: 'Ему скучно одному.',
      BearLanguage.en: 'It is dull all alone.',
      BearLanguage.zh: '一个人有点无聊。',
    },
  ),
  'sleep': NotificationText(
    'sleep',
    {
      BearLanguage.ru: 'Пора спать',
      BearLanguage.en: 'Time for bed',
      BearLanguage.zh: '该睡觉了',
    },
    {
      BearLanguage.ru: 'Малыш зевает и трёт глаза.',
      BearLanguage.en: 'Your little one is yawning.',
      BearLanguage.zh: '宝宝在打哈欠。',
    },
  ),
  'task': NotificationText(
    'task',
    {
      BearLanguage.ru: 'Новое задание',
      BearLanguage.en: 'A new task',
      BearLanguage.zh: '有新任务',
    },
    {
      BearLanguage.ru: 'Загляни в раздел обучения.',
      BearLanguage.en: 'Take a look at the learning section.',
      BearLanguage.zh: '去学习区看看吧。',
    },
  ),
  'gift': NotificationText(
    'gift',
    {
      BearLanguage.ru: 'Подарок ждёт',
      BearLanguage.en: 'A gift is waiting',
      BearLanguage.zh: '有礼物',
    },
    {
      BearLanguage.ru: 'Кто-то приготовил сюрприз.',
      BearLanguage.en: 'Someone left a surprise.',
      BearLanguage.zh: '有人给你准备了惊喜。',
    },
  ),
  'stage': NotificationText(
    'stage',
    {
      BearLanguage.ru: 'Малыш подрос',
      BearLanguage.en: 'Your little one grew up',
      BearLanguage.zh: '宝宝长大了',
    },
    {
      BearLanguage.ru: 'Открылось что-то новое.',
      BearLanguage.en: 'Something new has opened.',
      BearLanguage.zh: '有新内容解锁了。',
    },
  ),
  'event': NotificationText(
    'event',
    {
      BearLanguage.ru: 'Сегодня особенный день',
      BearLanguage.en: 'Today is special',
      BearLanguage.zh: '今天很特别',
    },
    {
      BearLanguage.ru: 'Заходи, расскажу.',
      BearLanguage.en: 'Come in, I will tell you.',
      BearLanguage.zh: '快来，我告诉你。',
    },
  ),
  'shop': NotificationText(
    'shop',
    {
      BearLanguage.ru: 'Новинки в магазине',
      BearLanguage.en: 'New in the shop',
      BearLanguage.zh: '商店上新',
    },
    {
      BearLanguage.ru: 'Появились новые вещи.',
      BearLanguage.en: 'Fresh things have arrived.',
      BearLanguage.zh: '有新东西啦。',
    },
  ),
};

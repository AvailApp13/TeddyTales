import '../bear/bear_phrases.dart' show BearLanguage;
import '../bear/bear_rig_spec.dart' show BearTrait;

/// Живые тексты уведомлений (заказчик 25.09, первый этап игровой логики;
/// КП 13.1, 13.3, 13.4): с именем мишки, по его характеру, с чередованием —
/// одно и то же «Малыш проголодался» каждый день быстро перестают читать.
///
/// Несколько причин сразу — одно уведомление: «Тедди проголодался и хочет
/// спать» вместо двух звонков подряд.
///
/// Виды сверх восьми типов КП — нарастание при долгом отсутствии; они
/// идут под переключателями ближайшего типа (см. [switchOf]):
///   * `miss` — сутки не заходил: скучает (переключатель «Хочет играть»);
///   * `away` — трое суток: гостит у бабушки, ждёт с подарком («Подарок»);
///   * `week` — неделя: одно тёплое письмо и тишина («Подарок»).
///
/// «Мишка заботится о тебе» (сверх ТЗ, заказчик 25.09) — свои
/// переключатели: `water` — выпить воды, `rest` — хозяину пора спать.
class SmartCopy {
  const SmartCopy(this.title, this.body);

  final String title;
  final String body;
}

/// Какой переключатель настроек (КП 13.2) управляет видом.
String switchOf(String kind) => switch (kind) {
  'miss' => 'play',
  'away' || 'week' => 'gift',
  _ => kind,
};

/// Имя в тексте: своё — как есть, имя по умолчанию — «малыш» на языке.
String notificationName(String name, BearLanguage lang, String defaultName) {
  if (name.trim().isNotEmpty && name != defaultName) return name;
  return switch (lang) {
    BearLanguage.ru => 'Малыш',
    BearLanguage.en => 'Your little one',
    BearLanguage.zh => '宝宝',
  };
}

/// Текст уведомления для одного вида или нескольких сразу ([kinds] через
/// «+», как их отдаёт расписание). [seed] выбирает вариант — например,
/// номер дня, чтобы тексты чередовались.
SmartCopy composeNotification(
  String kinds, {
  required String name,
  required BearLanguage lang,
  BearTrait trait = BearTrait.active,
  int seed = 0,
}) {
  final list = kinds.split('+');
  if (list.length > 1) {
    final needs = [for (final k in list) _need[lang]![k] ?? k];
    final joined = switch (lang) {
      BearLanguage.ru =>
        '${needs.sublist(0, needs.length - 1).join(', ')} и ${needs.last}',
      BearLanguage.en =>
        '${needs.sublist(0, needs.length - 1).join(', ')} and ${needs.last}',
      BearLanguage.zh => needs.join('，还'),
    };
    return SmartCopy(
      _fill(_bundleTitle[lang]!, name),
      _fill(_bundleBody[lang]!, name).replaceFirst('{needs}', joined),
    );
  }
  final kind = list.single;
  final byTrait = kind == 'miss' ? _missByTrait[lang]![trait] : null;
  final variants = _variants[lang]![kind] ?? _variants[lang]!['event']!;
  final pick = variants[seed.abs() % variants.length];
  return SmartCopy(_fill(pick.$1, name), _fill(byTrait ?? pick.$2, name));
}

String _fill(String text, String name) => text.replaceAll('{name}', name);

const _bundleTitle = {
  BearLanguage.ru: '{name} зовёт тебя',
  BearLanguage.en: '{name} is calling you',
  BearLanguage.zh: '{name}在叫你',
};

const _bundleBody = {
  BearLanguage.ru: '{name} {needs}.',
  BearLanguage.en: '{name} {needs}.',
  BearLanguage.zh: '{name}{needs}。',
};

/// Короткие «нужды» для общего уведомления.
const _need = {
  BearLanguage.ru: {
    'hungry': 'проголодался',
    'play': 'хочет играть',
    'sleep': 'хочет спать',
    'task': 'ждёт задание',
    'gift': 'нашёл подарок',
    'stage': 'подрос',
  },
  BearLanguage.en: {
    'hungry': 'is hungry',
    'play': 'wants to play',
    'sleep': 'is sleepy',
    'task': 'has a task for you',
    'gift': 'found a gift',
    'stage': 'has grown',
  },
  BearLanguage.zh: {
    'hungry': '饿了',
    'play': '想玩',
    'sleep': '困了',
    'task': '有任务',
    'gift': '找到了礼物',
    'stage': '长大了',
  },
};

/// Варианты (заголовок, текст) по видам. {name} — имя мишки.
const Map<BearLanguage, Map<String, List<(String, String)>>> _variants = {
  BearLanguage.ru: {
    'hungry': [
      ('{name} проголодался', 'Кажется, пора перекусить.'),
      ('Животик урчит', '{name} заглядывает на кухню.'),
      ('Время еды', '{name} ждёт тебя за столом.'),
    ],
    'play': [
      ('{name} зовёт играть', 'Одному скучно.'),
      ('Поиграем?', '{name} принёс игрушку.'),
      ('{name} заскучал', 'Хочет повеселиться с тобой.'),
    ],
    'sleep': [
      ('Пора спать', '{name} зевает и трёт глазки.'),
      ('{name} клюёт носом', 'Уложишь в кроватку?'),
    ],
    'task': [
      ('Задания дня', '{name} приготовил для тебя три задания.'),
      ('Новый урок', '{name} хочет узнать что-то новое.'),
    ],
    'gift': [
      ('Подарок ждёт', '{name} нашёл сегодняшний подарок — открой его.'),
      ('Сюрприз дня', 'Загляни: для тебя подарок от {name}.'),
    ],
    'stage': [('{name} подрос!', 'Посмотри, каким он стал.')],
    'miss': [('{name} скучает', 'Загляни хоть на минутку.')],
    'away': [('{name} ждёт тебя', 'Гостит у бабушки и приготовил подарок.')],
    'week': [
      ('{name} очень скучает', 'Возвращайся — у бабушки для тебя подарок.'),
    ],
    'water': [
      ('{name} пьёт водичку', 'И тебе пора — стакан воды?'),
      ('Глоток воды?', '{name} заботится: попей немного воды.'),
      ('Водный перерыв', '{name} напоминает: не забудь про воду.'),
    ],
    'rest': [
      ('{name} уже в кроватке', 'И тебе пора отдыхать. Спокойной ночи!'),
      ('Пора спать', '{name} зевает: давай отдыхать вместе.'),
    ],
    'event': [('Сегодня особенный день', 'Заходи, {name} расскажет.')],
  },
  BearLanguage.en: {
    'hungry': [
      ('{name} is hungry', 'Looks like snack time.'),
      ('A rumbling tummy', '{name} is peeking into the kitchen.'),
      ('Mealtime', '{name} is waiting at the table.'),
    ],
    'play': [
      ('{name} wants to play', 'It is dull all alone.'),
      ('Let\'s play?', '{name} brought a toy.'),
      ('{name} is bored', 'Wants to have fun with you.'),
    ],
    'sleep': [
      ('Time for bed', '{name} is yawning and rubbing their eyes.'),
      ('{name} is nodding off', 'Tuck them in?'),
    ],
    'task': [
      ('Today\'s tasks', '{name} has three tasks for you.'),
      ('A new lesson', '{name} wants to learn something new.'),
    ],
    'gift': [
      ('A gift is waiting', '{name} found today\'s gift — open it.'),
      ('Surprise of the day', 'Come see: a gift from {name}.'),
    ],
    'stage': [('{name} has grown!', 'Come see how big they are now.')],
    'miss': [('{name} misses you', 'Drop by for a minute.')],
    'away': [
      ('{name} is waiting for you', 'Staying with grandma and saved a gift.'),
    ],
    'week': [
      ('{name} misses you a lot', 'Come back — grandma has a gift for you.'),
    ],
    'water': [
      ('{name} is having some water', 'Your turn — a glass of water?'),
      ('Sip of water?', '{name} cares: drink a little water.'),
      ('Water break', '{name} reminds you: don\'t forget to drink water.'),
    ],
    'rest': [
      ('{name} is already in bed', 'Time for you to rest too. Good night!'),
      ('Bedtime', '{name} yawns: let\'s rest together.'),
    ],
    'event': [('Today is special', 'Come in, {name} will tell you.')],
  },
  BearLanguage.zh: {
    'hungry': [
      ('{name}饿了', '好像该吃点东西了。'),
      ('肚子咕咕叫', '{name}在厨房张望。'),
      ('开饭啦', '{name}在餐桌边等你。'),
    ],
    'play': [
      ('{name}想玩', '一个人有点无聊。'),
      ('一起玩吗？', '{name}拿来了玩具。'),
      ('{name}无聊了', '想和你一起玩。'),
    ],
    'sleep': [('该睡觉了', '{name}在打哈欠、揉眼睛。'), ('{name}困得直点头', '哄它上床吧？')],
    'task': [('今日任务', '{name}为你准备了三个任务。'), ('新课程', '{name}想学点新东西。')],
    'gift': [('礼物在等你', '{name}找到了今天的礼物，快打开吧。'), ('今日惊喜', '来看看：{name}送你的礼物。')],
    'stage': [('{name}长大了！', '快来看看它的新样子。')],
    'miss': [('{name}想你了', '来看看它吧，哪怕一分钟。')],
    'away': [('{name}在等你', '它在奶奶家，还给你留了礼物。')],
    'week': [('{name}非常想你', '回来吧——奶奶给你准备了礼物。')],
    'water': [
      ('{name}在喝水', '你也来一杯水吧？'),
      ('喝口水吧？', '{name}关心你：喝点水。'),
      ('喝水时间', '{name}提醒你：别忘了喝水。'),
    ],
    'rest': [('{name}已经上床了', '你也该休息了。晚安！'), ('该睡觉了', '{name}打了个哈欠：一起休息吧。')],
    'event': [('今天很特别', '快来，{name}告诉你。')],
  },
};

/// «Скучает» по характеру (КП 7.4: характер влияет на подсказки).
const Map<BearLanguage, Map<BearTrait, String>> _missByTrait = {
  BearLanguage.ru: {
    BearTrait.active: '{name} уже всё перебегал без тебя. Поиграем?',
    BearTrait.curious: '{name} нашёл что-то интересное и ждёт, чтобы показать.',
    BearTrait.affectionate: '{name} очень скучает и хочет обнимашек.',
    BearTrait.calm: '{name} тихонько ждёт тебя у окошка.',
    BearTrait.independent: '{name} справляется сам, но с тобой веселее.',
    BearTrait.reserved: '{name} ничего не говорит, но ждёт тебя.',
  },
  BearLanguage.en: {
    BearTrait.active: '{name} has run all around without you. Let\'s play?',
    BearTrait.curious: '{name} found something interesting to show you.',
    BearTrait.affectionate: '{name} misses you and wants a hug.',
    BearTrait.calm: '{name} is quietly waiting by the window.',
    BearTrait.independent: '{name} is doing fine, but it is more fun with you.',
    BearTrait.reserved: '{name} says nothing, but is waiting for you.',
  },
  BearLanguage.zh: {
    BearTrait.active: '{name}自己跑了一圈又一圈，一起玩吧？',
    BearTrait.curious: '{name}发现了有趣的东西，等着给你看。',
    BearTrait.affectionate: '{name}很想你，想要抱抱。',
    BearTrait.calm: '{name}在窗边静静地等你。',
    BearTrait.independent: '{name}自己也行，但和你一起更开心。',
    BearTrait.reserved: '{name}什么也没说，但一直在等你。',
  },
};

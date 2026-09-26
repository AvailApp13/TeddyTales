import 'dart:math';

import 'bear_rig_spec.dart';

/// Языки интерфейса (КП 16.1).
enum BearLanguage { ru, en, zh }

/// Когда реплика уместна.
enum BearPhraseContext {
  /// Вход в игру.
  greeting,

  /// Спокойное состояние, мишка просто живёт.
  idle,

  happy,
  sad,
  hungry,
  sleepy,
  dirty,

  afterFeed,
  afterWash,
  afterPlay,
  afterPet,
  afterWake,

  /// Пузырь инициативы (КП 3.4).
  invitePlay,
  inviteLearn,

  /// Взросление (КП 5.6).
  stageUp,
}

/// Реплика питомца на трёх языках (КП 13.3, 13.4).
class BearPhrase {
  const BearPhrase(this.id, this.context, this.ru, this.en, this.zh);

  final String id;
  final BearPhraseContext context;
  final String ru;
  final String en;
  final String zh;

  String text(BearLanguage language) => switch (language) {
    BearLanguage.ru => ru,
    BearLanguage.en => en,
    BearLanguage.zh => zh,
  };

  @override
  String toString() => 'BearPhrase($id)';
}

/// Каталог реплик питомца.
///
/// КП 13.3: «Реплики питомца — 30 на старте — пишет Исполнитель, стиль
/// согласуется с Заказчиком». Ниже — **черновик на согласование**: ровно 30
/// реплик, каждая на русском, английском и китайском (КП 13.4).
///
/// Тон выбран под аудиторию тамагочи: короткие фразы от первого лица, без
/// сложных конструкций, чтобы их можно было читать ребёнку вслух и чтобы они
/// влезали в пузырь на главном экране. Ни одна реплика не давит на пользователя
/// чувством вины — по КП 6.2 в игре нет болезней и смерти, мишка только грустит
/// и просит.
///
/// Когда стиль утвердят, тексты должны переехать в панель управления
/// (КП 15.5: загрузка реплик и текстов уведомлений) — здесь они лежат как
/// стартовый набор и как фолбэк на случай, если сервер недоступен (КП 1.1,
/// офлайн-режим).
abstract final class BearPhrases {
  static const List<BearPhrase> all = <BearPhrase>[
    // --- Приветствие ------------------------------------------------------
    BearPhrase(
      'greeting_1',
      BearPhraseContext.greeting,
      'Ты пришёл! Я скучал.',
      "You're back! I missed you.",
      '你回来啦！我好想你。',
    ),
    BearPhrase(
      'greeting_2',
      BearPhraseContext.greeting,
      'Привет! Что будем делать?',
      'Hi! What shall we do?',
      '你好！我们做点什么呢？',
    ),
    BearPhrase(
      'greeting_3',
      BearPhraseContext.greeting,
      'Я тебя ждал.',
      'I was waiting for you.',
      '我一直在等你。',
    ),

    // --- Спокойное состояние ---------------------------------------------
    BearPhrase(
      'idle_1',
      BearPhraseContext.idle,
      'Тут так уютно.',
      "It's so cosy here.",
      '这里好舒服。',
    ),
    BearPhrase(
      'idle_2',
      BearPhraseContext.idle,
      'Посидим вместе?',
      'Shall we sit together?',
      '我们一起坐会儿好吗？',
    ),
    BearPhrase(
      'idle_3',
      BearPhraseContext.idle,
      'Я немного мечтаю.',
      "I'm daydreaming a little.",
      '我在发呆呢。',
    ),

    // --- Радость и грусть -------------------------------------------------
    BearPhrase(
      'happy_1',
      BearPhraseContext.happy,
      'Мне сегодня так хорошо!',
      'I feel so good today!',
      '我今天好开心！',
    ),
    BearPhrase(
      'happy_2',
      BearPhraseContext.happy,
      'С тобой весело!',
      "It's fun with you!",
      '和你在一起真开心！',
    ),
    BearPhrase(
      'sad_1',
      BearPhraseContext.sad,
      'Мне немножко грустно…',
      "I'm a little sad…",
      '我有点难过……',
    ),
    BearPhrase(
      'sad_2',
      BearPhraseContext.sad,
      'Побудь со мной, пожалуйста.',
      'Please stay with me.',
      '请陪陪我。',
    ),

    // --- Нужды ------------------------------------------------------------
    BearPhrase(
      'hungry_1',
      BearPhraseContext.hungry,
      'Я немного голоден…',
      "I'm a little hungry…",
      '我有点饿了……',
    ),
    BearPhrase(
      'hungry_2',
      BearPhraseContext.hungry,
      'В животике урчит.',
      'My tummy is rumbling.',
      '我的肚子咕咕叫。',
    ),
    BearPhrase(
      'hungry_3',
      BearPhraseContext.hungry,
      'А что у нас вкусненького?',
      'Is there something tasty?',
      '有什么好吃的吗？',
    ),
    BearPhrase(
      'sleepy_1',
      BearPhraseContext.sleepy,
      'Глазки закрываются…',
      'My eyes are closing…',
      '我的眼睛快睁不开了……',
    ),
    BearPhrase(
      'sleepy_2',
      BearPhraseContext.sleepy,
      'Пора в кроватку?',
      'Is it time for bed?',
      '该睡觉了吗？',
    ),
    BearPhrase(
      'dirty_1',
      BearPhraseContext.dirty,
      'Кажется, я испачкался.',
      'I think I got dirty.',
      '我好像弄脏了。',
    ),
    BearPhrase(
      'dirty_2',
      BearPhraseContext.dirty,
      'Хочу побрызгаться водичкой!',
      'I want to splash in the water!',
      '我想玩水！',
    ),

    // --- Реакции на действия ----------------------------------------------
    BearPhrase(
      'after_feed_1',
      BearPhraseContext.afterFeed,
      'Ммм, вкусно! Спасибо.',
      'Mmm, yummy! Thank you.',
      '嗯，真好吃！谢谢你。',
    ),
    BearPhrase(
      'after_feed_2',
      BearPhraseContext.afterFeed,
      'Теперь я сытый и довольный.',
      "Now I'm full and happy.",
      '我吃饱啦，好满足。',
    ),
    BearPhrase(
      'after_wash_1',
      BearPhraseContext.afterWash,
      'Я чистенький!',
      "I'm all clean!",
      '我干干净净啦！',
    ),
    BearPhrase(
      'after_wash_2',
      BearPhraseContext.afterWash,
      'Пахну свежестью.',
      'I smell so fresh.',
      '我身上香香的。',
    ),
    BearPhrase(
      'after_play_1',
      BearPhraseContext.afterPlay,
      'Ещё разок, ещё!',
      'Again, one more time!',
      '再来一次，再来！',
    ),
    BearPhrase(
      'after_play_2',
      BearPhraseContext.afterPlay,
      'Это было весело!',
      'That was fun!',
      '太好玩了！',
    ),
    BearPhrase(
      'after_pet_1',
      BearPhraseContext.afterPet,
      'Мне так приятно…',
      'That feels so nice…',
      '好舒服呀……',
    ),
    BearPhrase(
      'after_pet_2',
      BearPhraseContext.afterPet,
      'Я тебя люблю.',
      'I love you.',
      '我爱你。',
    ),
    BearPhrase(
      'after_wake_1',
      BearPhraseContext.afterWake,
      'Доброе утро! Я выспался.',
      'Good morning! I slept well.',
      '早上好！我睡得好香。',
    ),

    // --- Инициатива -------------------------------------------------------
    BearPhrase(
      'invite_play_1',
      BearPhraseContext.invitePlay,
      'Поиграем вместе?',
      'Shall we play together?',
      '我们一起玩好吗？',
    ),
    BearPhrase(
      'invite_play_2',
      BearPhraseContext.invitePlay,
      'Я нашёл новую игру!',
      'I found a new game!',
      '我发现了一个新游戏！',
    ),
    BearPhrase(
      'invite_learn_1',
      BearPhraseContext.inviteLearn,
      'Научишь меня чему-нибудь?',
      'Will you teach me something?',
      '你能教我点什么吗？',
    ),

    // --- Взросление -------------------------------------------------------
    BearPhrase(
      'stage_up_1',
      BearPhraseContext.stageUp,
      'Смотри, я подрос!',
      "Look, I've grown up!",
      '你看，我长大了！',
    ),
  ];

  /// Реплики для контекста.
  static List<BearPhrase> forContext(BearPhraseContext context) =>
      all.where((phrase) => phrase.context == context).toList();

  /// Случайная реплика для контекста или `null`, если реплик нет.
  static BearPhrase? random(BearPhraseContext context, {Random? random}) {
    final candidates = forContext(context);
    if (candidates.isEmpty) return null;
    return candidates[(random ?? Random()).nextInt(candidates.length)];
  }

  /// Контекст, соответствующий состоянию покоя.
  static BearPhraseContext contextForMood(BearMood mood) => switch (mood) {
    BearMood.normal => BearPhraseContext.idle,
    BearMood.happy => BearPhraseContext.happy,
    BearMood.sad => BearPhraseContext.sad,
    BearMood.hungry => BearPhraseContext.hungry,
    BearMood.sleepy => BearPhraseContext.sleepy,
    BearMood.dirty => BearPhraseContext.dirty,
  };
}

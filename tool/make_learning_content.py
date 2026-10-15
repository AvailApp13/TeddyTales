#!/usr/bin/env python3
"""Собирает контент обучения: 300 заданий по КП 9.4.

Почему генератор, а не написанный от руки файл. Триста заданий на трёх
языках — это девятьсот строк, и написанные по одной они неизбежно разъедутся:
где-то забудется перевод, где-то верный ответ окажется не на своём месте,
где-то среди вариантов встретится второй правильный. Здесь задание задаётся
данными — набором предметов с переводами и шаблоном вопроса, — а связность
проверяется на выходе.

## Что проверяется

* у каждого задания ровно четыре варианта и ни одного повтора среди них;
* верный ответ действительно среди вариантов;
* ни один неверный вариант не может считаться верным (для заданий на цвет и
  на счёт это проверяется по самим данным);
* вопрос переведён на все три языка;
* заданий ровно 300, поровну по категориям.

## Про варианты ответа

Варианты — эмодзи и цифры, они одинаковы на всех языках, поэтому переводится
только вопрос. Это не экономия, а требование КП 9.1: до чтения ребёнок ещё не
дорос, ответ выбирается по картинке.

    python3 tool/make_learning_content.py lib/game/learning_content.dart
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

LANGS = ('ru', 'en', 'zh')

# --- Словарь предметов -----------------------------------------------------
#
# Кортеж: эмодзи, название на трёх языках. Названия нужны в вопросах вида
# «какого цвета банан».

COLOURS = [
    ('🔴', 'красный', 'red', '红色'),
    ('🟢', 'зелёный', 'green', '绿色'),
    ('🔵', 'синий', 'blue', '蓝色'),
    ('🟡', 'жёлтый', 'yellow', '黄色'),
    ('🟠', 'оранжевый', 'orange', '橙色'),
    ('🟣', 'фиолетовый', 'purple', '紫色'),
    ('🟤', 'коричневый', 'brown', '棕色'),
    ('⚫️', 'чёрный', 'black', '黑色'),
    ('⚪️', 'белый', 'white', '白色'),
]

SHAPES = [
    # Круг — именно ⭕️, а не ⚫️: чёрным кружком в соседней категории
    # обозначен цвет, и одна картинка на два разных понятия сбивает.
    ('⭕️', 'круг', 'a circle', '圆形'),
    ('🔺', 'треугольник', 'a triangle', '三角形'),
    ('⬛️', 'квадрат', 'a square', '正方形'),
    ('⭐️', 'звезда', 'a star', '星形'),
    ('❤️', 'сердце', 'a heart', '心形'),
    ('🔶', 'ромб', 'a diamond', '菱形'),
]

# Предмет и его настоящий цвет: индекс в COLOURS.
COLOURED_THINGS = [
    ('🍌', 3, 'банан', 'a banana', '香蕉'),
    ('🍅', 0, 'помидор', 'a tomato', '西红柿'),
    ('🌿', 1, 'трава', 'grass', '青草'),
    ('🍆', 5, 'баклажан', 'an eggplant', '茄子'),
    ('🍊', 4, 'апельсин', 'an orange', '橙子'),
    ('🍫', 6, 'шоколад', 'chocolate', '巧克力'),
    ('🌊', 2, 'море', 'the sea', '大海'),
    ('❄️', 8, 'снег', 'snow', '雪'),
    ('🌙', 3, 'луна', 'the moon', '月亮'),
    ('🍓', 0, 'клубника', 'a strawberry', '草莓'),
    ('🥑', 1, 'авокадо', 'an avocado', '牛油果'),
    ('🍇', 5, 'виноград', 'grapes', '葡萄'),
]

# Счётные предметы: эмодзи, которым удобно набирать ряд.
COUNTABLE = ['🍎', '⭐️', '🐟', '🌼', '🍪', '🎈', '🐞', '🍋', '🐣', '🧸']

# Пары «больше — меньше»: первый крупнее второго.
SIZE_PAIRS = [
    ('🐘', '🐭'), ('🐳', '🐟'), ('🌳', '🌱'), ('🏠', '🚪'),
    ('🚌', '🚲'), ('🍉', '🍇'), ('🐻', '🐝'), ('🗻', '🪨'),
]

# Мир вокруг: вопрос задаётся типом, верный ответ — первый в наборе.
WATER = ['🐟', '🐙', '🦈', '🐬', '🦀']
SKY = ['🐦', '🦋', '🐝', '✈️', '🦅']
GROUND = ['🐕', '🐈', '🐄', '🐖', '🐇']
TREES = ['🍎', '🍐', '🍒', '🥥', '🍊']
GARDEN = ['🥕', '🥔', '🍅', '🥒', '🌽']
DAY = ['☀️']
NIGHT = ['🌙', '⭐️']
WINTER = ['❄️', '⛄️', '🧤', '🎿']
SUMMER = ['🏖', '🍉', '☀️', '🩴']
MILK = ['🐄', '🐐']
HONEY = ['🐝']
WOOL = ['🐑']
EGGS = ['🐔', '🦆']

# Вопросы: ключ -> тексты на трёх языках. Собраны здесь, а не рядом с
# генератором, чтобы переводчику был виден весь список сразу.
Q = {
    'find_colour': ('Найди {thing}', 'Find the {thing} one', '找出{thing}的'),
    'thing_colour': ('Какого цвета {thing}?', 'What colour is {thing}?',
                     '{thing}是什么颜色？'),
    'find_shape': ('Где {thing}?', 'Where is {thing}?', '哪个是{thing}？'),
    'count': ('Сколько здесь предметов?', 'How many are there?', '这里有几个？'),
    'bigger': ('Кто больше?', 'Which one is bigger?', '哪个更大？'),
    'smaller': ('Кто меньше?', 'Which one is smaller?', '哪个更小？'),
    'next': ('Какое число идёт за {thing}?', 'Which number comes after {thing}?',
             '{thing}后面是哪个数字？'),
    'before': ('Какое число идёт перед {thing}?',
               'Which number comes before {thing}?', '{thing}前面是哪个数字？'),
    'plus': ('Сколько будет {thing}?', 'How much is {thing}?', '{thing}等于几？'),
    'water': ('Кто живёт в воде?', 'Who lives in the water?', '谁住在水里？'),
    'sky': ('Кто умеет летать?', 'Who can fly?', '谁会飞？'),
    'ground': ('Кто живёт рядом с домом?', 'Who lives near the house?',
               '谁住在家附近？'),
    'tree': ('Что растёт на дереве?', 'What grows on a tree?', '什么长在树上？'),
    'garden': ('Что растёт на грядке?', 'What grows in the garden bed?',
               '什么长在菜地里？'),
    'day': ('Что светит днём?', 'What shines during the day?', '白天什么在发光？'),
    'night': ('Что видно ночью?', 'What can you see at night?', '夜里能看到什么？'),
    'winter': ('Что бывает зимой?', 'What happens in winter?', '冬天有什么？'),
    'summer': ('Что бывает летом?', 'What happens in summer?', '夏天有什么？'),
    'milk': ('Кто даёт молоко?', 'Who gives milk?', '谁产奶？'),
    'honey': ('Кто делает мёд?', 'Who makes honey?', '谁酿蜜？'),
    'wool': ('У кого шерсть?', 'Who has wool?', '谁有羊毛？'),
    'eggs': ('Кто несёт яйца?', 'Who lays eggs?', '谁下蛋？'),
}


class Task:
    """Одно задание: вопрос на трёх языках, четыре варианта, верный индекс."""

    def __init__(self, question_key: str, options: list[str], correct: int,
                 thing: tuple[str, str, str] | None = None) -> None:
        self.options = options
        self.correct = correct
        ru, en, zh = Q[question_key]
        if thing is None:
            self.question = (ru, en, zh)
        else:
            self.question = (ru.format(thing=thing[0]),
                             en.format(thing=thing[1]),
                             zh.format(thing=thing[2]))

    def check(self) -> None:
        if len(self.options) != 4:
            raise SystemExit(f'Не четыре варианта: {self.options}')
        if len(set(self.options)) != 4:
            raise SystemExit(f'Повтор среди вариантов: {self.options}')
        if not 0 <= self.correct < 4:
            raise SystemExit(f'Верный ответ вне набора: {self.correct}')
        if any(not text.strip() for text in self.question):
            raise SystemExit(f'Пустой перевод: {self.question}')


def shuffled(rng: random.Random, right: str, wrong: list[str]) -> tuple[list, int]:
    """Ставит верный ответ на случайное место среди трёх неверных."""
    options = wrong[:3]
    slot = rng.randrange(4)
    options.insert(slot, right)
    return options, slot


def colours_tasks(rng: random.Random) -> list[Task]:
    """Цвета и формы (КП 9.1)."""
    tasks: list[Task] = []

    # Найди цвет по названию.
    for index, (emoji, ru, en, zh) in enumerate(COLOURS):
        others = [c[0] for i, c in enumerate(COLOURS) if i != index]
        rng.shuffle(others)
        options, slot = shuffled(rng, emoji, others)
        tasks.append(Task('find_colour', options, slot, (ru, en, zh)))

    # Какого цвета предмет.
    for emoji, colour_index, ru, en, zh in COLOURED_THINGS:
        right = COLOURS[colour_index][0]
        others = [c[0] for i, c in enumerate(COLOURS) if i != colour_index]
        rng.shuffle(others)
        options, slot = shuffled(rng, right, others)
        tasks.append(Task('thing_colour', options, slot, (ru, en, zh)))

    # Где фигура.
    for index, (emoji, ru, en, zh) in enumerate(SHAPES):
        others = [s[0] for i, s in enumerate(SHAPES) if i != index]
        rng.shuffle(others)
        options, slot = shuffled(rng, emoji, others)
        tasks.append(Task('find_shape', options, slot, (ru, en, zh)))

    # Добираем до сотни: те же цвета, но другие наборы неверных вариантов —
    # ребёнок видит цвет в новом окружении, а не заученную картинку.
    while len(tasks) < 100:
        index = rng.randrange(len(COLOURS))
        emoji, ru, en, zh = COLOURS[index]
        others = [c[0] for i, c in enumerate(COLOURS) if i != index]
        rng.shuffle(others)
        options, slot = shuffled(rng, emoji, others)
        tasks.append(Task('find_colour', options, slot, (ru, en, zh)))

    return tasks[:100]


def count_tasks(rng: random.Random) -> list[Task]:
    """Счёт и простая логика (КП 9.1)."""
    tasks: list[Task] = []

    # Сосчитай предметы.
    for _ in range(34):
        amount = rng.randint(1, 5)
        emoji = rng.choice(COUNTABLE)
        wrong = [str(n) for n in range(1, 10) if n != amount]
        rng.shuffle(wrong)
        options, slot = shuffled(rng, str(amount), wrong)
        task = Task('count', options, slot)
        # Вопрос без подстановки, но сам ряд предметов показывается в нём же.
        row = emoji * amount
        task.question = tuple(f'{row}\n{text}' for text in task.question)
        tasks.append(task)

    # Кто больше, кто меньше.
    for big, small in SIZE_PAIRS:
        rest = [e for pair in SIZE_PAIRS for e in pair if e not in (big, small)]
        rng.shuffle(rest)
        options, slot = shuffled(rng, big, [small] + rest[:2])
        tasks.append(Task('bigger', options, slot))

        rng.shuffle(rest)
        options, slot = shuffled(rng, small, [big] + rest[:2])
        tasks.append(Task('smaller', options, slot))

    # Следующее и предыдущее число.
    for number in range(1, 9):
        wrong = [str(n) for n in range(1, 10) if n != number + 1]
        rng.shuffle(wrong)
        options, slot = shuffled(rng, str(number + 1), wrong)
        tasks.append(Task('next', options, slot,
                          (str(number), str(number), str(number))))

    for number in range(2, 10):
        wrong = [str(n) for n in range(1, 10) if n != number - 1]
        rng.shuffle(wrong)
        options, slot = shuffled(rng, str(number - 1), wrong)
        tasks.append(Task('before', options, slot,
                          (str(number), str(number), str(number))))

    # Сложение в пределах девяти.
    while len(tasks) < 100:
        left = rng.randint(1, 5)
        right = rng.randint(1, 4)
        total = left + right
        wrong = [str(n) for n in range(1, 10) if n != total]
        rng.shuffle(wrong)
        options, slot = shuffled(rng, str(total), wrong)
        label = f'{left} + {right}'
        tasks.append(Task('plus', options, slot, (label, label, label)))

    return tasks[:100]


def world_tasks(rng: random.Random) -> list[Task]:
    """Окружающий мир (КП 9.1)."""
    groups = [
        ('water', WATER, SKY + GROUND),
        ('sky', SKY, WATER + GROUND),
        ('ground', GROUND, WATER + SKY),
        ('tree', TREES, GARDEN + GROUND),
        ('garden', GARDEN, TREES + SKY),
        ('day', DAY, NIGHT + ['💡', '🔦', '🕯']),
        ('night', NIGHT, DAY + ['🌻', '🏖']),
        ('winter', WINTER, SUMMER + GARDEN),
        ('summer', SUMMER, WINTER + ['🧣', '🛷']),
        ('milk', MILK, SKY + WATER),
        ('honey', HONEY, WATER + GROUND),
        ('wool', WOOL, WATER + SKY),
        ('eggs', EGGS, WATER + ['🐕', '🐈']),
    ]

    tasks: list[Task] = []
    while len(tasks) < 100:
        key, right_pool, wrong_pool = groups[len(tasks) % len(groups)]
        right = rng.choice(right_pool)
        wrong = [e for e in wrong_pool if e not in right_pool]
        rng.shuffle(wrong)
        options, slot = shuffled(rng, right, wrong)
        tasks.append(Task(key, options, slot))
    return tasks[:100]


CATEGORIES = [
    ('colors', '🎨', colours_tasks),
    ('count', '🔢', count_tasks),
    ('world', '🌍', world_tasks),
]

TASKS_PER_LEVEL = 10
LEVELS = 10


def dart_string(text: str) -> str:
    escaped = text.replace('\\', r'\\').replace("'", r"\'").replace('\n', r'\n')
    return f"'{escaped}'"


def build(out: Path) -> int:
    # Порядок заданий обязан быть одинаковым в каждой сборке: иначе игрок,
    # прошедший третий уровень, после обновления увидит там другие вопросы.
    rng = random.Random(20260916)

    lines = [
        '// СГЕНЕРИРОВАННЫЙ ФАЙЛ. Правится не он, а `tool/make_learning_content.py`.',
        '//',
        '// Контент обучения: 300 заданий, по сто на категорию, по десять на',
        '// уровень (КП 9.2, 9.4). Варианты ответа — эмодзи и цифры, они',
        '// одинаковы на всех языках: по КП 9.1 ответ выбирается по картинке,',
        '// потому что читать ребёнок ещё не умеет. Переводится только вопрос.',
        '//',
        '// По КП 9.4 контент даёт Заказчик через панель управления. Когда',
        '// появится загрузка с сервера, этот файл станет запасным набором на',
        '// случай отсутствия сети (КП 1.1).',
        '',
        "import '../bear/bear_phrases.dart' show BearLanguage;",
        '',
        '/// Задание: вопрос на трёх языках и четыре варианта ответа.',
        'class EduTask {',
        '  const EduTask(this._ru, this._en, this._zh, this.options, this.correct);',
        '',
        '  final String _ru;',
        '  final String _en;',
        '  final String _zh;',
        '',
        '  /// Четыре варианта. Не переводятся — это картинки и цифры.',
        '  final List<String> options;',
        '',
        '  /// Индекс верного варианта.',
        '  final int correct;',
        '',
        '  String question(BearLanguage language) => switch (language) {',
        '    BearLanguage.ru => _ru,',
        '    BearLanguage.en => _en,',
        '    BearLanguage.zh => _zh,',
        '  };',
        '}',
        '',
        '/// Сколько заданий в одном уровне (КП 9.4: 30 уровней × 10 = 300).',
        f'const int eduTasksPerLevel = {TASKS_PER_LEVEL};',
        '',
        '/// Сколько уровней в категории (КП 9.2).',
        f'const int eduLevelsPerCategory = {LEVELS};',
        '',
    ]

    total = 0
    catalogue: list[str] = []
    for cat_id, emoji, builder in CATEGORIES:
        tasks = builder(rng)
        if len(tasks) != TASKS_PER_LEVEL * LEVELS:
            raise SystemExit(f'{cat_id}: заданий {len(tasks)}, нужно 100')
        for task in tasks:
            task.check()
        total += len(tasks)

        name = f'_{cat_id}Tasks'
        catalogue.append(f"  '{cat_id}': {name},")
        lines.append(f'const List<List<EduTask>> {name} = [')
        for level in range(LEVELS):
            chunk = tasks[level * TASKS_PER_LEVEL:(level + 1) * TASKS_PER_LEVEL]
            lines.append(f'  // Уровень {level + 1}')
            lines.append('  [')
            for task in chunk:
                ru, en, zh = (dart_string(t) for t in task.question)
                options = ', '.join(dart_string(o) for o in task.options)
                lines.append(
                    f'    EduTask({ru}, {en}, {zh}, [{options}], {task.correct}),')
            lines.append('  ],')
        lines.append('];')
        lines.append('')

    lines += [
        '/// Задания по категориям: ключ — тот же, что в `edu_progress`.',
        'const Map<String, List<List<EduTask>>> eduContent = {',
        *catalogue,
        '};',
        '',
    ]

    out.write_text('\n'.join(lines))
    print(f'{out}: {total} заданий, '
          f'{len(CATEGORIES)} категории по {LEVELS} уровней')
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    return build(Path(sys.argv[1]))


if __name__ == '__main__':
    sys.exit(main())

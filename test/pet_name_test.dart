import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/pet_name.dart';

/// Имя питомца (КП 2.3).
///
/// Проверяется форма — то, что решает устройство. Запрещённые слова ловит
/// сервер по списку модератора, и его проверка живёт в базе, а не здесь.
void main() {
  group('Что принимается', () {
    test('обычные имена на трёх языках', () {
      for (final name in ['Тедди', 'Teddy', '泰迪', 'Мишка-Топтыжка', "O'Ted"]) {
        expect(checkPetName(name), isNull, reason: name);
      }
    });

    test('два знака — уже имя', () {
      expect(checkPetName('Ло'), isNull);
      expect(checkPetName('泰迪'), isNull);
    });

    test('пробелы по краям не мешают', () {
      expect(checkPetName('  Тедди  '), isNull);
    });
  });

  group('Что отклоняется', () {
    test('пусто и одни пробелы', () {
      expect(checkPetName(''), PetNameError.empty);
      expect(checkPetName('   '), PetNameError.empty);
    });

    test('один знак', () {
      expect(checkPetName('Т'), PetNameError.tooShort);
    });

    test('длиннее пятнадцати знаков', () {
      expect(checkPetName('А' * 16), PetNameError.tooLong);
      expect(checkPetName('А' * 15), isNull);
    });

    test('цифры и знаки препинания', () {
      for (final name in ['Тедди2000', 'Ted@home', 'Мишка!', '#топ']) {
        expect(checkPetName(name), PetNameError.badCharacters, reason: name);
      }
    });

    test('эмодзи не имя', () {
      // Считаем по символам: у эмодзи две кодовые единицы, и по `length`
      // «🐻🐻» прошло бы как четыре знака.
      expect(checkPetName('🐻🐻'), PetNameError.badCharacters);
    });

    test('очевидная брань — до сервера', () {
      expect(checkPetName('сукаМишка'), PetNameError.blocked);
      expect(checkPetName('FuckTed'), PetNameError.blocked);
    });

    test('разрядкой и дефисами сито не обойти', () {
      // Первое, что пробуют, когда фильтр ругается.
      expect(checkPetName('с у к а'), PetNameError.blocked);
      expect(checkPetName('f-u-c-k'), PetNameError.blocked);
    });
  });

  group('Нормализация', () {
    test('пробелы по краям срезаются, внутренние схлопываются', () {
      expect(normalizePetName('  Тед   ди  '), 'Тед ди');
    });

    test('уже нормальное имя не меняется', () {
      expect(normalizePetName('Тедди'), 'Тедди');
    });

    test('«Тед ди» и «  Тед   ди » — одно имя', () {
      // Иначе в базе завелись бы два «одинаковых» мишки с разными записями.
      expect(normalizePetName('Тед ди'), normalizePetName('  Тед   ди '));
    });
  });
}

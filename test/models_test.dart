import 'package:arabic_connections/levels.dart';
import 'package:arabic_connections/models.dart';
import 'package:arabic_connections/services/daily_challenge_service.dart';
import 'package:arabic_connections/services/hint_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Level data integrity', () {
    for (final level in sampleLevels) {
      test('Level ${level.number} has 4 words per category', () {
        expect(level.categories.length, greaterThanOrEqualTo(2));
        expect(level.words.length, level.categories.length * 4);
        for (final category in level.categories) {
          final count =
              level.words.where((w) => w.categoryId == category.id).length;
          expect(count, 4, reason: 'category ${category.id}');
        }
      });
    }
  });

  group('LevelParser', () {
    test('parses wrapped JSON payload', () {
      const body = '''
      {"levels":[{"number":99,"title":"Test","categories":[
        {"id":"a","name":"A","color":"#58CC02"},
        {"id":"b","name":"B","color":"#1CB0F6"},
        {"id":"c","name":"C","color":"#FF9600"},
        {"id":"d","name":"D","color":"#CE82FF"}
      ],"words":[
        {"id":"1","text":"1","categoryId":"a"},{"id":"2","text":"2","categoryId":"a"},
        {"id":"3","text":"3","categoryId":"a"},{"id":"4","text":"4","categoryId":"a"},
        {"id":"5","text":"5","categoryId":"b"},{"id":"6","text":"6","categoryId":"b"},
        {"id":"7","text":"7","categoryId":"b"},{"id":"8","text":"8","categoryId":"b"},
        {"id":"9","text":"9","categoryId":"c"},{"id":"10","text":"10","categoryId":"c"},
        {"id":"11","text":"11","categoryId":"c"},{"id":"12","text":"12","categoryId":"c"},
        {"id":"13","text":"13","categoryId":"d"},{"id":"14","text":"14","categoryId":"d"},
        {"id":"15","text":"15","categoryId":"d"},{"id":"16","text":"16","categoryId":"d"}
      ]}]}
      ''';
      final levels = LevelParser.parseLevelsResponse(body);
      expect(levels.length, 1);
      expect(levels.first.number, 99);
      expect(levels.first.title, 'Test');
    });
  });

  group('DailyChallengeService', () {
    final service = DailyChallengeService();

    test('same date picks same level index', () {
      final date = DateTime(2026, 6, 16);
      final a = service.levelIndexForDate(sampleLevels, date);
      final b = service.levelIndexForDate(sampleLevels, date);
      expect(a, b);
    });
  });

  group('HintService', () {
    final service = HintService();
    final level = sampleLevels.first;

    test('category hint returns unsolved category', () {
      final hint = service.categoryHint(level, {'fruits'});
      expect(hint, isNotNull);
      expect(hint!.categoryId, isNot('fruits'));
      expect(hint.categoryName, isNotEmpty);
    });

    test('word hint returns remaining word', () {
      final remaining = level.words.where((w) => w.categoryId != 'fruits').toList();
      final hint = service.wordHint(level, {'fruits'}, {}, remaining);
      expect(hint, isNotNull);
      expect(hint!.wordId, isNotNull);
    });
  });
}

import '../models.dart';

/// Picks the daily challenge level deterministically from the date.
class DailyChallengeService {
  /// Returns the level index for [date] across [levels].
  int levelIndexForDate(List<Level> levels, DateTime date) {
    if (levels.isEmpty) return 0;
    final seed = date.year * 10000 + date.month * 100 + date.day;
    return seed % levels.length;
  }

  Level dailyLevelForDate(List<Level> levels, DateTime date) {
    return levels[levelIndexForDate(levels, date)];
  }

  String formattedDate(DateTime date) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

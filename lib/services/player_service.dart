import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../solitaire/difficulty.dart';

/// Persists and manages player coins, daily challenge progress, and the
/// adaptive difficulty [skill] rating that drives dynamic round generation.
class PlayerService extends ChangeNotifier {
  static const _coinsKey = 'player_coins';
  static const _dailyCompletedKey = 'daily_completed_date';
  static const _skillKey = 'player_skill';
  static const _streakKey = 'player_streak';
  static const _roundKey = 'player_round';
  static const _tutorialKey = 'tutorial_seen';

  int _coins = GameEconomy.startingCoins;
  String? _dailyCompletedDate;
  double _skill = DifficultyDirector.startingSkill;
  int _cleanStreak = 0;
  int _round = 1;
  bool _tutorialSeen = false;
  bool _loaded = false;

  int get coins => _coins;
  bool get isLoaded => _loaded;

  /// Rolling difficulty rating in `[0, 100]`; higher deals harder boards.
  double get skill => _skill;

  /// Consecutive perfect (no mistakes, no hints) round wins.
  int get cleanStreak => _cleanStreak;

  /// The continuous game's current round, so players resume where they left
  /// off across sessions.
  int get round => _round;

  /// Whether the first-time gameplay tutorial has been shown.
  bool get tutorialSeen => _tutorialSeen;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _coins = prefs.getInt(_coinsKey) ?? GameEconomy.startingCoins;
    _dailyCompletedDate = prefs.getString(_dailyCompletedKey);
    _skill = prefs.getDouble(_skillKey) ?? DifficultyDirector.startingSkill;
    _cleanStreak = prefs.getInt(_streakKey) ?? 0;
    _round = prefs.getInt(_roundKey) ?? 1;
    _tutorialSeen = prefs.getBool(_tutorialKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// Records that the player has seen the first-time tutorial.
  Future<void> markTutorialSeen() async {
    if (_tutorialSeen) return;
    _tutorialSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialKey, true);
    notifyListeners();
  }

  /// Persists the continuous game's current round.
  Future<void> saveRound(int value) async {
    _round = value < 1 ? 1 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_roundKey, _round);
    notifyListeners();
  }

  /// Persists an updated adaptive difficulty rating.
  Future<void> saveSkill(double value) async {
    _skill = value.clamp(DifficultyDirector.minSkill, DifficultyDirector.maxSkill);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_skillKey, _skill);
    notifyListeners();
  }

  /// Persists the current clean-win streak.
  Future<void> saveCleanStreak(int value) async {
    _cleanStreak = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_streakKey, _cleanStreak);
    notifyListeners();
  }

  bool isDailyCompletedToday([DateTime? now]) {
    final today = _dateKey(now ?? DateTime.now());
    return _dailyCompletedDate == today;
  }

  Future<void> markDailyCompleted([DateTime? now]) async {
    _dailyCompletedDate = _dateKey(now ?? DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyCompletedKey, _dailyCompletedDate!);
    notifyListeners();
  }

  Future<bool> spendCoins(int amount) async {
    if (_coins < amount) return false;
    _coins -= amount;
    await _persistCoins();
    notifyListeners();
    return true;
  }

  Future<void> addCoins(int amount) async {
    _coins += amount;
    await _persistCoins();
    notifyListeners();
  }

  Future<void> _persistCoins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_coinsKey, _coins);
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

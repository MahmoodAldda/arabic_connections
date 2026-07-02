import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Persists and manages player coins and daily challenge progress.
class PlayerService extends ChangeNotifier {
  static const _coinsKey = 'player_coins';
  static const _dailyCompletedKey = 'daily_completed_date';

  int _coins = GameEconomy.startingCoins;
  String? _dailyCompletedDate;
  bool _loaded = false;

  int get coins => _coins;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _coins = prefs.getInt(_coinsKey) ?? GameEconomy.startingCoins;
    _dailyCompletedDate = prefs.getString(_dailyCompletedKey);
    _loaded = true;
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

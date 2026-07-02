import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../levels.dart';
import '../models.dart';

/// Fetches levels from a JSON API with bundled asset and cache fallback.
class LevelApiService {
  static const _cacheKey = 'levels_api_cache_v1';

  /// Loads levels: remote API → cached JSON → bundled asset → hardcoded fallback.
  Future<List<Level>> fetchLevels() async {
    try {
      final remote = await _fetchRemote();
      if (remote.isNotEmpty) {
        await _cacheLevels(remote);
        return _mergeWithLocal(remote);
      }
    } catch (_) {
      // Fall through to cache / asset
    }

    final cached = await _loadCached();
    if (cached.isNotEmpty) return _mergeWithLocal(cached);

    final bundled = await _loadBundled();
    if (bundled.isNotEmpty) return _mergeWithLocal(bundled);

    return List<Level>.from(sampleLevels);
  }

  Future<List<Level>> _fetchRemote() async {
    const url = AppConfig.levelsApiUrl;
    if (url.isEmpty) return [];

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) return [];
    return LevelParser.parseLevelsResponse(response.body);
  }

  Future<List<Level>> _loadBundled() async {
    try {
      final body = await rootBundle.loadString(AppConfig.bundledLevelsAsset);
      return LevelParser.parseLevelsResponse(body);
    } catch (_) {
      return [];
    }
  }

  Future<List<Level>> _loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return [];
    try {
      return LevelParser.parseLevelsResponse(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> _cacheLevels(List<Level> levels) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'levels': levels.map((l) => l.toJson()).toList(),
    });
    await prefs.setString(_cacheKey, payload);
  }

  List<Level> _mergeWithLocal(List<Level> remote) {
    final merged = <int, Level>{
      for (final level in sampleLevels) level.number: level,
      for (final level in remote) level.number: level,
    };
    return merged.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }
}

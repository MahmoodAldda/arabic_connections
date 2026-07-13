import 'dart:convert';

import 'package:flutter/material.dart';

import 'config/app_config.dart';

/// Game play mode.
enum GameMode { classic, daily }

/// Types of purchasable hints.
enum HintType { category, word }

/// A single Arabic word belonging to one category.
class WordItem {
  const WordItem({
    required this.id,
    required this.text,
    required this.categoryId,
    this.emoji,
  });

  final String id;
  final String text;
  final String categoryId;

  /// Optional picture for the card, shown above the word (e.g. "🍎"). When null
  /// the card is text-only.
  final String? emoji;

  factory WordItem.fromJson(Map<String, dynamic> json) {
    final emoji = json['emoji'] as String?;
    return WordItem(
      id: json['id'] as String,
      text: json['text'] as String,
      categoryId: json['categoryId'] as String,
      emoji: (emoji != null && emoji.isNotEmpty) ? emoji : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'categoryId': categoryId,
        if (emoji != null) 'emoji': emoji,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A category that groups exactly four words.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      color: _parseColor(json['color'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': _colorToHex(color),
      };

  static Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  static String _colorToHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

/// A complete puzzle level: a set of categories, each with four words.
///
/// The number of categories is variable (3–6) so difficulty can scale with more
/// categories per level. Every category is expected to have four words.
class Level {
  const Level({
    required this.number,
    required this.title,
    required this.categories,
    required this.words,
    this.story,
  })  : assert(categories.length >= 2, 'A level needs at least 2 categories'),
        assert(words.length == categories.length * 4,
            'Each category must have exactly 4 words');

  final int number;
  final String title;

  /// Optional short narrative shown on the level-intro screen to set the theme
  /// and make progression feel like a journey.
  final String? story;
  final List<Category> categories;
  final List<WordItem> words;

  factory Level.fromJson(Map<String, dynamic> json) {
    return Level(
      number: json['number'] as int,
      title: json['title'] as String,
      story: json['story'] as String?,
      categories: (json['categories'] as List<dynamic>)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList(),
      words: (json['words'] as List<dynamic>)
          .map((e) => WordItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'title': title,
        if (story != null) 'story': story,
        'categories': categories.map((c) => c.toJson()).toList(),
        'words': words.map((w) => w.toJson()).toList(),
      };

  Category categoryById(String id) =>
      categories.firstWhere((c) => c.id == id);

  List<WordItem> shuffledWords() {
    final copy = List<WordItem>.from(words);
    copy.shuffle();
    return copy;
  }
}

/// Parses a levels JSON payload from API or assets.
class LevelParser {
  static List<Level> parseLevelsResponse(String body) {
    final decoded = jsonDecode(body);
    final levelsJson = decoded is List<dynamic>
        ? decoded
        : (decoded as Map<String, dynamic>)['levels'] as List<dynamic>;
    return levelsJson
        .map((e) => Level.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Active game session configuration.
class GameSession {
  const GameSession({
    required this.mode,
    required this.levels,
    this.levelIndex = 0,
    this.dailyLevel,
  }) : assert(
          mode != GameMode.daily || dailyLevel != null,
          'Daily mode requires dailyLevel',
        );

  final GameMode mode;
  final List<Level> levels;
  final int levelIndex;
  final Level? dailyLevel;

  Level get activeLevel =>
      mode == GameMode.daily ? dailyLevel! : levels[levelIndex];

  int get coinReward => mode == GameMode.daily
      ? GameEconomy.dailyChallengeReward
      : GameEconomy.levelCompleteReward;

  bool get isDaily => mode == GameMode.daily;
}

/// Result of a hint purchase.
class HintResult {
  const HintResult({
    required this.type,
    required this.categoryId,
    this.categoryName,
    this.wordId,
    this.wordText,
  });

  final HintType type;
  final String categoryId;
  final String? categoryName;
  final String? wordId;
  final String? wordText;
}

/// Result of submitting a group of four selected words.
enum GroupCheckResult {
  correct,
  wrongSelection,
  wrongGroup,
}

/// Outcome of validating a submitted group.
class GroupValidation {
  const GroupValidation({
    required this.result,
    this.matchedCategory,
  });

  final GroupCheckResult result;
  final Category? matchedCategory;

  bool get isCorrect => result == GroupCheckResult.correct;
}

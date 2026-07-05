/// Adaptive difficulty model for the word-solitaire board.
///
/// This is pure Dart (no Flutter) so it can be unit-tested in isolation. The
/// [DifficultyDirector] keeps no state of its own: it turns a persisted player
/// *skill* rating into a [RoundSpec] (the parameters of the next board) and,
/// after a round, folds the [RoundResult] back into an updated skill rating.
///
/// Phase 1 drives the *structural* board dials that need no new content:
/// column depth (how many hidden cards pile up), whether category cards are
/// buried, the number of free hints, and a par time used for scoring/rewards.
/// Content-based dials (category count, word tiers) arrive in later phases.
library;

/// The tunable parameters of a single dealt round.
class RoundSpec {
  const RoundSpec({
    required this.columnDepth,
    required this.buryCategoryCards,
    required this.freeHints,
    required this.parTimeSec,
    required this.difficulty,
  });

  /// Cards dealt per tableau column (top face-up, rest hidden). Higher = harder.
  final int columnDepth;

  /// When false, category cards are biased toward face-up column tops (gentler).
  /// When true, they may be buried and must be revealed first.
  final bool buryCategoryCards;

  /// Hints granted for free this round before coins are charged.
  final int freeHints;

  /// Target completion time in seconds (for speed bonuses / UI; never fails).
  final int parTimeSec;

  /// Overall difficulty in `[0, 1]`, used to scale rewards.
  final double difficulty;

  /// Backward-compatible mapping that mirrors the original level-number tiers,
  /// so an engine created without an explicit spec behaves exactly as before.
  factory RoundSpec.forLevelNumber(int number, {int categoryCount = 4}) {
    final depth = number <= 2 ? 2 : 3;
    final bury = number > 2;
    final difficulty = number <= 2 ? 0.15 : (number <= 4 ? 0.4 : 0.65);
    return RoundSpec(
      columnDepth: depth,
      buryCategoryCards: bury,
      freeHints: number <= 2 ? 2 : 1,
      parTimeSec: estimateParTime(categoryCount, difficulty),
      difficulty: difficulty,
    );
  }

  RoundSpec copyWith({
    int? columnDepth,
    bool? buryCategoryCards,
    int? freeHints,
    int? parTimeSec,
    double? difficulty,
  }) {
    return RoundSpec(
      columnDepth: columnDepth ?? this.columnDepth,
      buryCategoryCards: buryCategoryCards ?? this.buryCategoryCards,
      freeHints: freeHints ?? this.freeHints,
      parTimeSec: parTimeSec ?? this.parTimeSec,
      difficulty: difficulty ?? this.difficulty,
    );
  }
}

/// The measured outcome of a finished round, fed back into the skill rating.
class RoundResult {
  const RoundResult({
    required this.timeSec,
    required this.mistakes,
    required this.hintsUsed,
    required this.bestCombo,
    required this.categoryCount,
    required this.won,
  });

  final int timeSec;
  final int mistakes;
  final int hintsUsed;
  final int bestCombo;
  final int categoryCount;
  final bool won;
}

/// A par time (seconds) that tightens as difficulty rises.
int estimateParTime(int categoryCount, double difficulty) {
  final perCategory = 28 - 12 * difficulty.clamp(0.0, 1.0);
  return (categoryCount.clamp(1, 12) * perCategory).round();
}

/// Turns a rolling skill rating into round parameters and back.
class DifficultyDirector {
  const DifficultyDirector();

  static const double minSkill = 0;
  static const double maxSkill = 100;

  /// New players start low so the first rounds are easy and attractive.
  static const double startingSkill = 8;

  /// Builds the next round's parameters for a player at [skill].
  RoundSpec specFor(double skill, {required int categoryCount}) {
    final r = skill.clamp(minSkill, maxSkill).toDouble();

    final int depth;
    if (r < 25) {
      depth = 2;
    } else if (r < 70) {
      depth = 3;
    } else {
      depth = 4;
    }

    final bury = r >= 25;
    final freeHints = r < 25 ? 2 : (r < 65 ? 1 : 0);
    final difficulty = (r / 100).clamp(0.0, 1.0);

    return RoundSpec(
      columnDepth: depth,
      buryCategoryCards: bury,
      freeHints: freeHints,
      parTimeSec: estimateParTime(categoryCount, difficulty),
      difficulty: difficulty,
    );
  }

  /// A `[0, 1]` performance score blending speed, cleanliness, hint reliance
  /// and combo flow. 0.5 is roughly "matched the round's expectations".
  double roundScore(RoundResult r, RoundSpec spec) {
    final t = r.timeSec < 1 ? 1 : r.timeSec;
    final speed = (spec.parTimeSec / t).clamp(0.3, 1.6);
    final clean = 1 - (r.mistakes * 0.12).clamp(0.0, 0.6);
    final unaided = 1 - (r.hintsUsed * 0.15).clamp(0.0, 0.6);
    final denom = r.categoryCount <= 0 ? 1 : r.categoryCount;
    final flow = (r.bestCombo / denom).clamp(0.0, 1.0);
    final raw = 0.4 * speed + 0.3 * clean + 0.2 * unaided + 0.1 * flow;
    return raw.clamp(0.0, 1.0);
  }

  /// Folds a finished round into the skill rating with a smooth EWMA step.
  /// Skill rises faster on mastery than it falls on a struggle (anti-frustration),
  /// and an abandoned/lost round eases difficulty gently.
  double updatedSkill(double skill, RoundResult r, RoundSpec spec) {
    if (!r.won) {
      return (skill - 3).clamp(minSkill, maxSkill);
    }
    final p = roundScore(r, spec);
    final target = p * 100;
    final rate = p >= 0.5 ? 0.4 : 0.2;
    final next = skill + rate * (target - skill);
    return next.clamp(minSkill, maxSkill);
  }
}

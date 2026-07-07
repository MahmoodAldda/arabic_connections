import 'dart:math';

/// Content selection for a continuous, level-less game.
///
/// The game no longer has a level picker: one endless game grows harder as the
/// player's skill rises. This chooses which level's *content* (its categories
/// and words) to deal for the next round. As [skill] climbs, the target number
/// of categories grows (3 → 6), pulling in bigger boards; among the levels
/// nearest that target one is picked at random (seeded by [round]) so
/// consecutive rounds feel fresh instead of repeating the same content.
int pickRoundLevelIndex({
  required List<int> categoryCounts,
  required double skill,
  required int round,
  Random? rng,
}) {
  if (categoryCounts.isEmpty) return 0;
  final target = (3 + (skill / 25).floor()).clamp(3, 6);

  var bestDist = 1 << 30;
  for (final c in categoryCounts) {
    final d = (c - target).abs();
    if (d < bestDist) bestDist = d;
  }
  final candidates = <int>[
    for (var i = 0; i < categoryCounts.length; i++)
      if ((categoryCounts[i] - target).abs() == bestDist) i,
  ];
  final r = rng ?? Random(round);
  return candidates[r.nextInt(candidates.length)];
}

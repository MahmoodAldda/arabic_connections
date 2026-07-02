import 'package:flutter/foundation.dart';

/// Catalog of game sound effects.
enum SoundFx {
  cardTap,
  cardMove,
  correct,
  wrong,
  shuffle,
  victory,
  coins,
  button,
}

/// Central sound manager.
///
/// This is intentionally SILENT for now: it validates the call sites and holds
/// the settings toggles so gameplay code can call [play] freely. To enable real
/// audio later:
///   1. `flutter pub add audioplayers`
///   2. Drop the files listed in [assetFor] into `assets/sounds/` and declare
///      the folder in `pubspec.yaml`.
///   3. Implement [play] using an AudioPlayer pool.
///
/// Nothing else in the game needs to change.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool soundEnabled = true;
  bool hapticsEnabled = true;

  /// Expected asset path for each effect (used when audio is wired up later).
  static String assetFor(SoundFx fx) {
    switch (fx) {
      case SoundFx.cardTap:
        return 'assets/sounds/card_tap.mp3';
      case SoundFx.cardMove:
        return 'assets/sounds/card_move.mp3';
      case SoundFx.correct:
        return 'assets/sounds/correct.mp3';
      case SoundFx.wrong:
        return 'assets/sounds/wrong.mp3';
      case SoundFx.shuffle:
        return 'assets/sounds/shuffle.mp3';
      case SoundFx.victory:
        return 'assets/sounds/victory.mp3';
      case SoundFx.coins:
        return 'assets/sounds/coins.mp3';
      case SoundFx.button:
        return 'assets/sounds/button.mp3';
    }
  }

  /// Plays an effect. Currently a no-op (silent) — see class docs.
  Future<void> play(SoundFx fx) async {
    if (!soundEnabled) return;
    // Silent placeholder. Real playback is wired in once assets are added.
    if (kDebugMode) {
      // Helps confirm sound events fire during development.
      // ignore: avoid_print
      // print('SoundFx: ${fx.name}');
    }
  }
}

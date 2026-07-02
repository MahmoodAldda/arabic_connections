/// App-wide configuration constants.
abstract final class AppConfig {
  /// Remote levels API URL. Leave empty to load from bundled [assets/levels.json].
  static const levelsApiUrl = String.fromEnvironment(
    'LEVELS_API_URL',
    defaultValue: '',
  );

  static const bundledLevelsAsset = 'assets/levels.json';
}

/// Coin economy values.
abstract final class GameEconomy {
  static const startingCoins = 50;
  static const levelCompleteReward = 20;
  static const dailyChallengeReward = 50;
  static const rewardedAdCoins = 30;
  static const categoryHintCost = 25;
  static const wordHintCost = 15;
}

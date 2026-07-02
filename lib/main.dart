import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'services/ad_service.dart';
import 'services/daily_challenge_service.dart';
import 'services/level_api_service.dart';
import 'services/player_service.dart';
import 'theme/game_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final playerService = PlayerService();
  final levelApiService = LevelApiService();
  final adService = StubAdService();
  final dailyChallengeService = DailyChallengeService();

  await playerService.load();
  await adService.initialize();

  runApp(ArabicConnectionsApp(
    playerService: playerService,
    levelApiService: levelApiService,
    adService: adService,
    dailyChallengeService: dailyChallengeService,
  ));
}

class ArabicConnectionsApp extends StatelessWidget {
  const ArabicConnectionsApp({
    super.key,
    required this.playerService,
    required this.levelApiService,
    required this.adService,
    required this.dailyChallengeService,
  });

  final PlayerService playerService;
  final LevelApiService levelApiService;
  final AdService adService;
  final DailyChallengeService dailyChallengeService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arabic Connections',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: GameColors.background,
        colorScheme: const ColorScheme.light(
          primary: GameColors.green,
          secondary: GameColors.blue,
          surface: GameColors.surface,
          onSurface: GameColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: GameColors.red,
        ),
      ),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        playerService: playerService,
        levelApiService: levelApiService,
        adService: adService,
        dailyChallengeService: dailyChallengeService,
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'menu_screen.dart';
import 'onboarding_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'config/pnle_theme.dart';
import 'services/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System config BEFORE UI
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  // Pre-load all sound effects into memory for zero-latency playback
  SoundService().init();

  // 🚀 DO NOT await Firebase here
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: PnleTheme.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: PnleTheme.accent,
      secondary: PnleTheme.accentDeep,
      surface: PnleTheme.bgTop,
      onPrimary: Colors.black,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(),
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: PnleTheme.bgBottom,
        appBarTheme: const AppBarTheme(
          backgroundColor: PnleTheme.bgTop,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.08),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/* =======================
   SCREEN 1: SPLASH SCREEN
   ======================= */
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAndProceed();
  }

  Future<void> _initializeAndProceed() async {
    try {
      // ✅ Initialize Firebase in background
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('Firebase init error: $e');
      // Continue without Firebase
    }

    try {
      // Initialize AdMob before any ad objects are created.
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdMob init error: $e');
      // Continue app flow even if ads fail to initialize.
    }

    // Show splash screen for 5 seconds
    await Future.delayed(const Duration(seconds: 5));

    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

    if (!onboardingComplete) {
      final nickname = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
      if (!mounted) return;
      if (nickname == null || nickname.trim().isEmpty) {
        return;
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MenuScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // INTRO IMAGE (FULL SCREEN)
          Positioned.fill(
            child: Image.asset(
              'assets/images/IntroLogo.png',
              fit: BoxFit.cover,
            ),
          ),

          // DARK + GRADIENT OVERLAY
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.55),
                  ],
                ),
              ),
            ),
          ),

          // LOADING STATUS
          Positioned(
            bottom: 32.0,
            left: 32.0,
            right: 32.0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Preparing your review dashboard...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: const LinearProgressIndicator(
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* =======================
   SCREEN 2: MAIN MENU
   (Moved to menu_screen.dart)
   ======================= */

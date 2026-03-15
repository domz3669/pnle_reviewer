import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'menu_screen.dart';
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(),
        useMaterial3: true,
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
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

    // Check internet connection
    bool hasInternet = await _hasInternetConnection();

    if (!mounted) return;

    if (hasInternet) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MenuScreen()),
      );
    } else {
      _showNoInternetDialog();
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _showNoInternetDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                PnleTheme.bgTop,
                PnleTheme.bgBottom,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: PnleTheme.accent.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PnleTheme.accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_off,
                  size: 60,
                  color: PnleTheme.accent,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Internet Connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This app requires an internet connection to start.\n\n'
                'Please check your Wi-Fi or mobile data, then restart the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PnleTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    exit(0);
                  },
                  child: const Text(
                    'EXIT APP',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
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
                    'Checking internet connection...',
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
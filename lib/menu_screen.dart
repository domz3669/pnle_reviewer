import 'dart:math';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/device_service.dart';

import 'question_screen.dart';
import 'models/question.dart';
import 'models/pnle_key_areas.dart';
import 'services/question_generation_service.dart';
import 'services/deepseek_service.dart';
import 'config/secrets.dart';
import 'config/admob_ids.dart';
import 'config/pnle_theme.dart';
import 'generating_dialog.dart';
import 'subscription_dialog.dart';
import 'settings_screen.dart';
import 'onboarding_screen.dart';

class _SavedSession {
  final String title;
  final List<Question> questions;
  final DateTime savedAt;

  _SavedSession({
    required this.title,
    required this.questions,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();
}

class _QuizActivityRecord {
  final DateTime date;
  final int questionCount;

  const _QuizActivityRecord({
    required this.date,
    required this.questionCount,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'questionCount': questionCount,
  };

  static _QuizActivityRecord? fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'] ?? json['d'];
    final questionRaw = json['questionCount'] ?? json['q'];
    if (dateRaw is! String || questionRaw is! num) return null;

    final parsedDate = DateTime.tryParse(dateRaw);
    if (parsedDate == null) return null;

    return _QuizActivityRecord(
      date: parsedDate,
      questionCount: questionRaw.toInt(),
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  // =========================
  // STATE
  // =========================
  int currentScreen = 0; // 0=Home, 1=Daily, 2=Quiz, 3=History, 4=Settings
  String eligibility = 'UPCAT Reviewer';
  bool isPremiumUser = false;
  bool isTrialActive = false;
  DateTime? trialEndDate;
  // Daily tracking
  int completedSessions = 0; // Out of 4 per day
  int remainingFreeTests = 4; // Firebase-synced daily counter
  int rewardedAdsWatchedToday = 0; // Track for daily limit
  DateTime? lastRewardedAdDay; // Track which day ads were watched
  int _zeroAdSessionsRemaining = 4; // First 4 sessions are ad-free
  
  // Accumulated stats (never reset, shows lifetime totals)
  int accumulatedQuizzesCompleted = 0;
  int accumulatedQuestionsAnswered = 0;
  
  // Services
  final DeviceService _deviceService = DeviceService();
  String? _deviceId;

  /// Get the Realtime DB instance with the explicit URL.
  /// Required because our RTDB is in asia-southeast1, not the default US region.
  FirebaseDatabase get _rtdb => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://upcat-ios-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );
  
  // UPCAT category scoring targets across 4 daily sessions.
  Map<String, Map<String, dynamic>> categoryScores = {
    'Language Proficiency': {'correct': 0, 'total': 8, 'weight': 0.20},
    'Reading Comprehension': {'correct': 0, 'total': 20, 'weight': 0.30},
    'Mathematics': {'correct': 0, 'total': 16, 'weight': 0.25},
    'Science': {'correct': 0, 'total': 16, 'weight': 0.25},
  };

  late List<Question> _generatedQuestions;
  Map<String, String>? _currentTestCoverage; // Stores selected key areas
  final List<_SavedSession> _savedSessions = [];
  final List<_QuizActivityRecord> _quizActivityRecords = [];
  static const int _maxQuizActivityRecords = 120;
  static const int _quizActivityRetentionDays = 45;
  
  // Daily generation limits (premium only)
  int _dailyGenerationSessionsUsed = 0;
  int _dailyGenerationQuestionsUsed = 0;
  String? _lastGenerationResetDate; // Format: yyyy-MM-dd
  static const int _maxDailyGenerationSessions = 20;
  static const int _maxDailyGenerationQuestions = 300;
  
  // Focus mode state
  bool _isFocusMode = false;
  String? _focusCategory;
  bool _isPrimingFreeDeepSeekCache = false;
  List<Question>? _cachedQuickPracticeQuestions;
  String? _cachedQuickPracticeCategory;
  final Map<String, List<Question>> _cachedFocusQuestions = {};
  static const bool _premiumTestMode = false;
  // bool _hasChosenEligibility = false; // Removed - not currently used
  bool _showFirstTimeFlow = false;
  bool _hasShownSpecializationDialog = false;


  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  InterstitialAd? _menuInterstitialAd;
  bool _isMenuInterstitialLoaded = false;

  BannerAd? _bannerAd;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _premiumProductDetails;
  bool _isStoreAvailable = false;
  bool _isPurchasePending = false;
  VoidCallback? _onPremiumPurchaseSuccess;
  static const String _androidPremiumProductId = 'premium';
  static const String _iosPremiumProductId = 'upcat_m_199';

  String get _premiumProductId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosPremiumProductId;
    }
    return _androidPremiumProductId;
  }

  Map<String, List<String>> get keyAreas => pnleKeyAreas;

  int _dailyTargetTotalForCategory(String category) {
    switch (category) {
      case 'Language Proficiency':
        return 8;
      case 'Reading Comprehension':
        return 20;
      case 'Mathematics':
      case 'Science':
        return 16;
      default:
        return 16;
    }
  }

  double _defaultWeightForCategory(String category) {
    switch (category) {
      case 'Language Proficiency':
        return 0.20;
      case 'Reading Comprehension':
        return 0.30;
      case 'Mathematics':
      case 'Science':
        return 0.25;
      default:
        return 0.25;
    }
  }

  void _ensurePnleCategoryScores() {
    for (final category in pnleCategories) {
      categoryScores[category] ??= {
        'correct': 0,
        'total': _dailyTargetTotalForCategory(category),
        'weight': _defaultWeightForCategory(category),
      };
    }
  }

  // Motivational quotes for daily encouragement
  final List<String> motivationalQuotes = [
    'Every question you answer correctly brings you closer to success.',
    'Consistency beats perfection. Keep practicing!',
    'Your effort today is your achievement tomorrow.',
    'Success is the sum of small efforts repeated day in and day out.',
    'You are stronger than you think. Keep going!',
    'Every mistake is a lesson in disguise for growth.',
    'The best time to plant a tree was 20 years ago. The second best is now.',
    "You've got this! Stay focused and believe in yourself.",
    "One day or day one. You're choosing day one today.",
    'Progress, not perfection. Every step counts!',
  ];

  // Daily Streak & Gamification
  int currentStreak = 0;
  DateTime? lastQuizDate;
  bool showOnboarding = false;

  // Scroll Controllers for fade indicator
  late ScrollController _homeScrollController;
  late ScrollController _dailyScrollController;
  late ScrollController _quizScrollController;
  late ScrollController _historyScrollController;

  // =========================
  // LIFECYCLE
  // =========================
  @override
  void initState() {
    super.initState();
    _ensurePnleCategoryScores();
    WidgetsBinding.instance.addObserver(this);
    _homeScrollController = ScrollController();
    _dailyScrollController = ScrollController();
    _quizScrollController = ScrollController();
    _historyScrollController = ScrollController();
    _loadRewardedAd();
    _loadMenuInterstitialAd();
    _loadBannerAd();
    _initSubscriptionBilling();
    _checkOnboarding();
    // Restore from RTDB first (survives reinstall), then local loads fill in gaps
    _restoreAllProgressFromRtdb().then((_) {
      _loadStreak();
      _loadAccumulatedStats();
      _loadQuizActivityRecords();
      _loadDailyGenerationUsage();
      _loadDailyFreeTestsFromRealtimeDb();
      _loadDailyCompletedSessions();
      _loadCategoryScores();
      _loadZeroAdSessions();
      _resetDailyCategoryScoresIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rewardedAd?.dispose();
    _menuInterstitialAd?.dispose();
    _bannerAd?.dispose();
    _purchaseSubscription?.cancel();
    _homeScrollController.dispose();
    _dailyScrollController.dispose();
    _quizScrollController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  // =========================
  // APP LIFECYCLE — SYNC ON BACKGROUND
  // =========================
  /// Fires when user presses Home button (paused) or app is being killed (detached).
  /// We flush all progress to RTDB immediately so nothing is lost
  /// even if the user clears recent apps right after.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      debugPrint('📱 App going to background ($state) — flushing data...');
      _syncAllProgressToRtdb();
    }
  }

  // =========================
  // ONBOARDING & STREAK
  // =========================
  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final isComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!isComplete) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (context) => OnboardingScreen(
          onComplete: () async {
            Navigator.pop(context);
            if (mounted) {
              setState(() {
                showOnboarding = false;
              });
            }
          },
        ),
      );
      setState(() => showOnboarding = true);
    }
  }

  Future<void> _loadStreak() async {
    final prefs = await SharedPreferences.getInstance();
    
    final lastRewardedDay = prefs.getString('lastRewardedAdDay');
    if (lastRewardedDay != null) {
      final lastDay = DateTime.parse(lastRewardedDay);
      final now = DateTime.now();
      
      // Reset counter if it's a new day
      if (now.year != lastDay.year || now.month != lastDay.month || now.day != lastDay.day) {
        rewardedAdsWatchedToday = 0;
      } else {
        final localAdsWatched = prefs.getInt('rewardedAdsWatchedToday') ?? 0;
        rewardedAdsWatchedToday = max(rewardedAdsWatchedToday, localAdsWatched);
        lastRewardedAdDay = lastDay;
      }
    }
    final lastDate = prefs.getString('lastQuizDate');
    final streak = prefs.getInt('currentStreak') ?? 0;

    if (lastDate != null) {
      final lastQuizDateTime = DateTime.parse(lastDate);
      final now = DateTime.now();
      final difference = now.difference(lastQuizDateTime).inDays;

      if (difference == 0) {
        // Same day, keep higher streak
        setState(() => currentStreak = max(currentStreak, streak));
      } else if (difference == 1) {
        // Next day, increment streak
        setState(() => currentStreak = max(currentStreak, streak + 1));
      } else {
        // Missed a day, reset streak (but only if RTDB/Firestore didn't restore higher)
        if (currentStreak == 0) {
          setState(() => currentStreak = 0);
        }
      }
    }
    setState(() {
      if (lastDate != null) {
        final parsedDate = DateTime.parse(lastDate);
        if (lastQuizDate == null || parsedDate.isAfter(lastQuizDate!)) {
          lastQuizDate = parsedDate;
        }
      }
    });
  }

  Future<void> _loadAccumulatedStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localQuizzes = prefs.getInt('accumulatedQuizzesCompleted') ?? 0;
      final localQuestions = prefs.getInt('accumulatedQuestionsAnswered') ?? 0;
      
      // Merge with current values (max wins - never overwrite higher values
      // that may have been restored from RTDB or Firestore already)
      setState(() {
        accumulatedQuizzesCompleted = max(accumulatedQuizzesCompleted, localQuizzes);
        accumulatedQuestionsAnswered = max(accumulatedQuestionsAnswered, localQuestions);
      });
    } catch (e) {
      print('Error loading accumulated stats: $e');
    }
  }

  Future<void> _persistAccumulatedStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('accumulatedQuizzesCompleted', accumulatedQuizzesCompleted);
      await prefs.setInt('accumulatedQuestionsAnswered', accumulatedQuestionsAnswered);
      
      // Also sync to RTDB (survives reinstall without sign-in)
      _syncAllProgressToRtdb();
    } catch (e) {
      print('Error persisting stats: $e');
    }
  }

  Future<void> _loadQuizActivityRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('quizActivityRecords');
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final loaded = <_QuizActivityRecord>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = _QuizActivityRecord.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) {
          loaded.add(parsed);
        }
      }

      if (!mounted) return;
      setState(() {
        _quizActivityRecords
          ..clear()
          ..addAll(loaded);
        _pruneQuizActivityRecords();
      });

      await _persistQuizActivityRecords();
    } catch (e) {
      debugPrint('Error loading quiz activity records: $e');
    }
  }

  Future<void> _persistQuizActivityRecords() async {
    try {
      _pruneQuizActivityRecords();
      final prefs = await SharedPreferences.getInstance();
      final payload = _quizActivityRecords.map((e) => e.toJson()).toList();
      await prefs.setString('quizActivityRecords', jsonEncode(payload));
    } catch (e) {
      debugPrint('Error persisting quiz activity records: $e');
    }
  }

  void _pruneQuizActivityRecords() {
    final cutoff = _dateOnly(
      DateTime.now().subtract(const Duration(days: _quizActivityRetentionDays)),
    );

    _quizActivityRecords.removeWhere(
      (record) => _dateOnly(record.date).isBefore(cutoff),
    );

    _quizActivityRecords.sort((a, b) => b.date.compareTo(a.date));

    if (_quizActivityRecords.length > _maxQuizActivityRecords) {
      _quizActivityRecords.removeRange(
        _maxQuizActivityRecords,
        _quizActivityRecords.length,
      );
    }
  }

  // =========================================================================
  // DAILY GENERATION USAGE TRACKING (Premium Rate Limiting)
  // =========================================================================

  Future<void> _loadDailyGenerationUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDate = prefs.getString('dailyGenerationResetDate');
      final sessions = prefs.getInt('dailyGenerationSessions') ?? 0;
      final questions = prefs.getInt('dailyGenerationQuestions') ?? 0;

      final today = _getTodayDateString();
      
      if (!mounted) return;
      setState(() {
        if (lastDate == today) {
          // Same day, restore counters
          _dailyGenerationSessionsUsed = sessions;
          _dailyGenerationQuestionsUsed = questions;
          _lastGenerationResetDate = lastDate;
        } else {
          // New day, reset counters
          _dailyGenerationSessionsUsed = 0;
          _dailyGenerationQuestionsUsed = 0;
          _lastGenerationResetDate = today;
        }
      });

      // Persist the reset if it happened
      if (lastDate != today) {
        await _persistDailyGenerationUsage();
      }
    } catch (e) {
      debugPrint('Error loading daily generation usage: $e');
    }
  }

  Future<void> _persistDailyGenerationUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dailyGenerationResetDate', _lastGenerationResetDate ?? _getTodayDateString());
      await prefs.setInt('dailyGenerationSessions', _dailyGenerationSessionsUsed);
      await prefs.setInt('dailyGenerationQuestions', _dailyGenerationQuestionsUsed);
    } catch (e) {
      debugPrint('Error persisting daily generation usage: $e');
    }
  }

  void _checkAndResetDailyGenerationUsage() {
    final today = _getTodayDateString();
    if (_lastGenerationResetDate != today) {
      setState(() {
        _dailyGenerationSessionsUsed = 0;
        _dailyGenerationQuestionsUsed = 0;
        _lastGenerationResetDate = today;
      });
      _persistDailyGenerationUsage();
    }
  }

  bool _canGenerateMoreQuestions(int questionCount) {
    _checkAndResetDailyGenerationUsage();
    return _dailyGenerationSessionsUsed < _maxDailyGenerationSessions &&
           (_dailyGenerationQuestionsUsed + questionCount) <= _maxDailyGenerationQuestions;
  }

  void _incrementGenerationUsage(int questionCount) {
    setState(() {
      _dailyGenerationSessionsUsed++;
      _dailyGenerationQuestionsUsed += questionCount;
    });
    _persistDailyGenerationUsage();
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // =========================================================================
  // RTDB COMPREHENSIVE STATE SYNC (survives reinstall / data clear)
  // =========================================================================

  /// Save ALL critical app state to Realtime DB under devices/{deviceId}/progress.
  /// Called after every meaningful state change so nothing is lost on reinstall.
  Future<void> _syncAllProgressToRtdb() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final today = DateTime.now();
      final todayStr = DateTime(today.year, today.month, today.day).toIso8601String();

      final progressData = <String, dynamic>{
        // Category scores
        'categoryScores': categoryScores.map((key, value) => MapEntry(key, {
          'correct': value['correct'],
          'total': value['total'],
          'weight': value['weight'],
        })),
        // Accumulated lifetime stats
        'accumulatedQuizzesCompleted': accumulatedQuizzesCompleted,
        'accumulatedQuestionsAnswered': accumulatedQuestionsAnswered,
        // Daily sessions
        'completedSessions': completedSessions,
        'lastSessionDate': todayStr,
        // Streak
        'currentStreak': currentStreak,
        'lastQuizDate': lastQuizDate?.toIso8601String(),
        // Eligibility
        'selectedEligibility': eligibility,
        'hasChosenEligibility': !_showFirstTimeFlow,
        // Free tests (also saved separately, but include here for completeness)
        'remainingFreeTests': remainingFreeTests,
        'lastFreeTestResetDate': todayStr,
        // Rewarded ads tracking
        'rewardedAdsWatchedToday': rewardedAdsWatchedToday,
        'lastRewardedAdDay': lastRewardedAdDay?.toIso8601String() ?? todayStr,
        // Zero-ad sessions (lifetime counter)
        'zeroAdSessionsRemaining': _zeroAdSessionsRemaining,
        // Compact quiz activity history for 10-day screen (capped + pruned)
        'quizActivityRecords': _quizActivityRecords
          .map((record) => {
              'd': record.date.toIso8601String(),
              'q': record.questionCount,
            })
          .toList(),
        // Daily reset tracking (prevents re-reset after app data clear)
        'lastCategoryScoreResetDate': todayStr,
        // Sync timestamp
        'lastSyncTime': DateTime.now().toIso8601String(),
      };

      await _rtdb.ref('devices/$_deviceId/progress').set(progressData)
          .timeout(const Duration(seconds: 8));

      debugPrint('✓ Synced all progress to RTDB (device)');
    } catch (e) {
      debugPrint('Could not sync progress to RTDB: $e');
    }
  }

  /// Shared merge logic used by both device-RTDB and user-RTDB restore.
  /// Applies max-wins strategy for all fields.
  void _mergeRtdbProgressData(Map<dynamic, dynamic> data) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    // --- Category scores (merge: take higher correct) ---
    final remoteCatScores = data['categoryScores'] as Map<dynamic, dynamic>?;
    if (remoteCatScores != null) {
      for (final entry in remoteCatScores.entries) {
        final key = entry.key.toString();
        final remote = entry.value as Map<dynamic, dynamic>;
        final remoteCorrect = (remote['correct'] as num?)?.toInt() ?? 0;
        final remoteTotal = (remote['total'] as num?)?.toInt() ?? 0;
        final remoteWeight = (remote['weight'] as num?)?.toDouble() ?? 0.0;

        if (categoryScores.containsKey(key)) {
          final localCorrect = categoryScores[key]!['correct'] as int;
          categoryScores[key] = {
            'correct': max(localCorrect, remoteCorrect),
            'total': max(
              _dailyTargetTotalForCategory(key),
              remoteTotal > 0 ? remoteTotal : (categoryScores[key]!['total'] as int),
            ),
            'weight': remoteWeight > 0 ? remoteWeight : categoryScores[key]!['weight'],
          };
        }
      }
    }

    // --- Accumulated stats (max wins) ---
    final remoteQuizzes = (data['accumulatedQuizzesCompleted'] as num?)?.toInt() ?? 0;
    final remoteQuestions = (data['accumulatedQuestionsAnswered'] as num?)?.toInt() ?? 0;
    accumulatedQuizzesCompleted = max(accumulatedQuizzesCompleted, remoteQuizzes);
    accumulatedQuestionsAnswered = max(accumulatedQuestionsAnswered, remoteQuestions);

    // --- Completed sessions (only restore if same day) ---
    final remoteCompletedSessions = (data['completedSessions'] as num?)?.toInt() ?? 0;
    final remoteLastSessionDate = data['lastSessionDate'] as String?;
    if (remoteLastSessionDate != null) {
      final remoteDate = DateTime.tryParse(remoteLastSessionDate);
      if (remoteDate != null) {
        final remoteDateOnly = DateTime(remoteDate.year, remoteDate.month, remoteDate.day);
        if (todayOnly.isAtSameMomentAs(remoteDateOnly)) {
          completedSessions = max(completedSessions, remoteCompletedSessions);
        }
      }
    }

    // --- Streak ---
    final remoteStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
    currentStreak = max(currentStreak, remoteStreak);

    final remoteLastQuizDateStr = data['lastQuizDate'] as String?;
    if (remoteLastQuizDateStr != null) {
      final remoteLastQuizDate = DateTime.tryParse(remoteLastQuizDateStr);
      if (remoteLastQuizDate != null) {
        if (lastQuizDate == null || remoteLastQuizDate.isAfter(lastQuizDate!)) {
          lastQuizDate = remoteLastQuizDate;
        }
      }
    }

    // --- Eligibility ---
    final remoteEligibility = data['selectedEligibility'] as String?;
    final remoteHasChosen = data['hasChosenEligibility'] as bool? ?? false;
    if (remoteHasChosen && _showFirstTimeFlow) {
      if (remoteEligibility != null) {
        eligibility = _normalizeSpecialization(remoteEligibility);
      }
      _showFirstTimeFlow = false;
    }
    _ensurePnleCategoryScores();

    // --- Zero-ad sessions (lifetime counter: min wins, preserves most progress) ---
    final remoteZeroAdSessions = (data['zeroAdSessionsRemaining'] as num?)?.toInt();
    if (remoteZeroAdSessions != null) {
      _zeroAdSessionsRemaining = min(_zeroAdSessionsRemaining, remoteZeroAdSessions);
    }

    // --- Quiz activity records (merge local + remote, dedupe, prune/cap) ---
    final remoteActivityRaw = data['quizActivityRecords'];
    final combined = <_QuizActivityRecord>[
      ..._quizActivityRecords,
    ];

    if (remoteActivityRaw is List) {
      for (final item in remoteActivityRaw) {
        if (item is! Map) continue;
        final parsed = _QuizActivityRecord.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) {
          combined.add(parsed);
        }
      }
    }

    final deduped = <String, _QuizActivityRecord>{};
    for (final record in combined) {
      final key = '${record.date.toIso8601String()}|${record.questionCount}';
      deduped[key] = record;
    }

    _quizActivityRecords
      ..clear()
      ..addAll(deduped.values);
    _pruneQuizActivityRecords();

    // --- Free tests (same day only) ---
    final remoteRemaining = (data['remainingFreeTests'] as num?)?.toInt() ?? 4;
    final remoteResetDate = data['lastFreeTestResetDate'] as String?;
    if (remoteResetDate != null) {
      final resetDate = DateTime.tryParse(remoteResetDate);
      if (resetDate != null) {
        final resetDayOnly = DateTime(resetDate.year, resetDate.month, resetDate.day);
        if (todayOnly.isAtSameMomentAs(resetDayOnly)) {
          remainingFreeTests = min(remainingFreeTests, remoteRemaining);
        } else {
          remainingFreeTests = 4;
        }
      }
    }

    // --- Rewarded ads (same day only) ---
    final remoteAdsWatched = (data['rewardedAdsWatchedToday'] as num?)?.toInt() ?? 0;
    final remoteAdDayStr = data['lastRewardedAdDay'] as String?;
    if (remoteAdDayStr != null) {
      final remoteAdDay = DateTime.tryParse(remoteAdDayStr);
      if (remoteAdDay != null) {
        final adDayOnly = DateTime(remoteAdDay.year, remoteAdDay.month, remoteAdDay.day);
        if (todayOnly.isAtSameMomentAs(adDayOnly)) {
          rewardedAdsWatchedToday = max(rewardedAdsWatchedToday, remoteAdsWatched);
          lastRewardedAdDay = remoteAdDay;
        }
      }
    }
  }

  /// Restore ALL app state from Realtime DB. Called on app startup
  /// BEFORE SharedPreferences load so RTDB data wins when prefs are empty.
  Future<void> _restoreAllProgressFromRtdb() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final snapshot = await _rtdb.ref('devices/$_deviceId/progress').get()
          .timeout(const Duration(seconds: 8));

      if (!snapshot.exists) {
        debugPrint('No RTDB progress data found for device');
        return;
      }

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;
      if (!mounted) return;

      // Use shared merge logic
      _mergeRtdbProgressData(data);

      setState(() {});

      // Persist merged data to SharedPreferences so subsequent local loads work
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('accumulatedQuizzesCompleted', accumulatedQuizzesCompleted);
      await prefs.setInt('accumulatedQuestionsAnswered', accumulatedQuestionsAnswered);
      await prefs.setString('categoryScores', jsonEncode(categoryScores));
      await prefs.setInt('currentStreak', currentStreak);
      if (lastQuizDate != null) {
        await prefs.setString('lastQuizDate', lastQuizDate!.toIso8601String());
      }
      await prefs.setString('selected_eligibility', eligibility);
      await prefs.setBool('has_chosen_eligibility', !_showFirstTimeFlow);
      await prefs.setInt('completedSessions', completedSessions);
      final now = DateTime.now();
      await prefs.setString('lastSessionDate', DateTime(now.year, now.month, now.day).toIso8601String());
      await prefs.setInt('remainingFreeTests', remainingFreeTests);
      await prefs.setInt('rewardedAdsWatchedToday', rewardedAdsWatchedToday);
      await prefs.setInt('zeroAdSessionsRemaining', _zeroAdSessionsRemaining);
      await prefs.setString(
        'quizActivityRecords',
        jsonEncode(_quizActivityRecords.map((e) => e.toJson()).toList()),
      );
      
      // Save daily reset date from RTDB so _resetDailyCategoryScoresIfNeeded()
      // doesn't wipe the scores we just restored
      final remoteResetDate = data['lastCategoryScoreResetDate'] as String?;
      if (remoteResetDate != null) {
        await prefs.setString('lastCategoryScoreResetDate', remoteResetDate);
      } else {
        // If RTDB doesn't have it, set today so the daily reset doesn't fire
        await prefs.setString('lastCategoryScoreResetDate',
            DateTime(now.year, now.month, now.day).toIso8601String());
      }

      debugPrint('✓ Restored all progress from RTDB');
    } catch (e) {
      debugPrint('Could not restore progress from RTDB: $e');
    }
  }

  /// Load daily free tests from Realtime DB (server source of truth)
  /// Falls back to local storage if offline
  Future<void> _loadDailyFreeTestsFromRealtimeDb() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final db = _rtdb;
      final ref = db.ref('devices/$_deviceId/freeTests');
      
      try {
        final snapshot = await ref.get().timeout(const Duration(seconds: 8));
        
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>?;
          if (data == null) return;
          
          final lastResetDateStr = data['lastResetDate'] as String?;
          final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          
          if (lastResetDateStr != null) {
            final lastResetDate = DateTime.parse(lastResetDateStr);
            final lastResetDay = DateTime(lastResetDate.year, lastResetDate.month, lastResetDate.day);
            
            if (!mounted) return;
            setState(() {
              if (today.isAfter(lastResetDay)) {
                // New day - reset to 4
                remainingFreeTests = 4;
              } else {
                // Same day - restore from server
                remainingFreeTests = (data['remaining'] as int?) ?? 4;
              }
            });
            
            // Update server date if new day
            if (today.isAfter(lastResetDay)) {
              await ref.update({'lastResetDate': today.toIso8601String()});
            }
          }
          
          debugPrint('✓ Loaded free tests from Realtime DB');
        } else {
          // First time - initialize in Realtime DB
          await _initializeRealtimeDbFreeTests();
        }
      } catch (e) {
        // Offline or error - fall back to local storage
        debugPrint('Realtime DB unavailable, using local cache: $e');
        await _loadDailyFreeTestsLocal();
      }
    } catch (e) {
      print('Error loading free tests from Realtime DB: $e');
      await _loadDailyFreeTestsLocal();
    }
  }

  /// Initialize free tests in Realtime DB (first time)
  Future<void> _initializeRealtimeDbFreeTests() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final db = _rtdb;
      final ref = db.ref('devices/$_deviceId/freeTests');
      
      await ref.set({
        'remaining': 4,
        'lastResetDate': today.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      
      if (!mounted) return;
      setState(() => remainingFreeTests = 4);
      
      debugPrint('✓ Initialized free tests in Realtime DB');
    } catch (e) {
      print('Error initializing Realtime DB: $e');
    }
  }

  /// Load daily free tests from local storage (fallback)
  Future<void> _loadDailyFreeTestsLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastResetDateStr = prefs.getString('lastFreeTestResetDate');
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      
      if (lastResetDateStr == null) {
        await prefs.setString('lastFreeTestResetDate', today.toIso8601String());
        if (!mounted) return;
        setState(() => remainingFreeTests = 4);
        return;
      }
      
      final lastResetDate = DateTime.parse(lastResetDateStr);
      final lastResetDay = DateTime(lastResetDate.year, lastResetDate.month, lastResetDate.day);
      
      if (!mounted) return;
      setState(() {
        if (today.isAfter(lastResetDay)) {
          remainingFreeTests = 4;
        } else {
          remainingFreeTests = prefs.getInt('remainingFreeTests') ?? 4;
        }
      });
      
      if (today.isAfter(lastResetDay)) {
        await prefs.setString('lastFreeTestResetDate', today.toIso8601String());
      }
    } catch (e) {
      print('Error loading daily free tests locally: $e');
    }
  }

  /// Save remaining free tests to both local and Realtime DB
  Future<void> _persistDailyFreeTests() async {
    // Save locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('remainingFreeTests', remainingFreeTests);
    } catch (e) {
      print('Error persisting free tests locally: $e');
    }

    // Save to Realtime DB
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final db = _rtdb;
      await db.ref('devices/$_deviceId/freeTests/remaining').set(remainingFreeTests);
      
      debugPrint('✓ Synced free tests to Realtime DB');
    } catch (e) {
      debugPrint('Could not sync to Realtime DB: $e');
      // This is OK - local is backed up
    }
  }

  /// Load category scores from SharedPreferences (merge, never overwrite higher values)
  Future<void> _loadCategoryScores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scoresJson = prefs.getString('categoryScores');
      
      if (scoresJson == null) return;
      
      final Map<String, dynamic> decoded = jsonDecode(scoresJson);
      if (!mounted) return;
      
      // Default weights (must match initial state)
      const defaultWeights = {
        'Language Proficiency': 0.20,
        'Reading Comprehension': 0.30,
        'Mathematics': 0.25,
        'Science': 0.25,
      };
      
      setState(() {
        for (final entry in decoded.entries) {
          final key = entry.key;
          final value = entry.value as Map<String, dynamic>;
          final localCorrect = value['correct'] as int;
          final localTotal = value['total'] as int;
          final localWeight = (value['weight'] as num?)?.toDouble() ?? defaultWeights[key] ?? 0.0;
          
          if (categoryScores.containsKey(key)) {
            final currentCorrect = categoryScores[key]!['correct'] as int;
            // Max merge: never overwrite higher values from RTDB/Firestore restore
            categoryScores[key] = {
              'correct': max(currentCorrect, localCorrect),
              'total': max(
                _dailyTargetTotalForCategory(key),
                localTotal > 0 ? localTotal : (categoryScores[key]!['total'] as int),
              ),
              'weight': localWeight > 0 ? localWeight : categoryScores[key]!['weight'],
            };
          } else {
            categoryScores[key] = {
              'correct': localCorrect,
              'total': localTotal,
              'weight': localWeight,
            };
          }
        }
      });
      
      debugPrint('✓ Loaded category scores from local storage (merged)');
    } catch (e) {
      print('Error loading category scores: $e');
    }
  }

  /// Save category scores to SharedPreferences + RTDB
  Future<void> _persistCategoryScores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scoresJson = jsonEncode(categoryScores);
      await prefs.setString('categoryScores', scoresJson);
      // Sync to RTDB (survives reinstall)
      _syncAllProgressToRtdb();
    } catch (e) {
      print('Error persisting category scores: $e');
    }
  }

  /// Load daily completed sessions with reset at midnight (merge, never overwrite higher)
  Future<void> _loadDailyCompletedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSessionDateStr = prefs.getString('lastSessionDate');
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      
      if (lastSessionDateStr == null) {
        // First time — only set date, don't reset completedSessions
        // (may already be restored from RTDB/Firestore)
        await prefs.setString('lastSessionDate', today.toIso8601String());
        return;
      }
      
      final lastSessionDate = DateTime.parse(lastSessionDateStr);
      final lastSessionDay = DateTime(lastSessionDate.year, lastSessionDate.month, lastSessionDate.day);
      
      if (!mounted) return;
      setState(() {
        if (today.isAfter(lastSessionDay)) {
          // New day - reset to 0
          completedSessions = 0;
        } else {
          // Same day - merge with higher value
          final localSessions = prefs.getInt('completedSessions') ?? 0;
          completedSessions = max(completedSessions, localSessions);
        }
      });
      
      // Update the session date if it's a new day
      if (today.isAfter(lastSessionDay)) {
        await prefs.setString('lastSessionDate', today.toIso8601String());
      }
    } catch (e) {
      print('Error loading completed sessions: $e');
    }
  }

  /// Save completed sessions to SharedPreferences + RTDB
  Future<void> _persistCompletedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('completedSessions', completedSessions);
      // Sync to RTDB (survives reinstall)
      _syncAllProgressToRtdb();
    } catch (e) {
      print('Error persisting completed sessions: $e');
    }
  }

  Future<void> _updateStreakAfterQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await prefs.setString('lastQuizDate', today.toIso8601String());
    await prefs.setInt('currentStreak', currentStreak + 1);

    setState(() {
      lastQuizDate = today;
      currentStreak = (prefs.getInt('currentStreak') ?? 0);
    });

    // Sync to RTDB (survives reinstall)
    _syncAllProgressToRtdb();
  }

  Future<void> _loadEligibilityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('selected_eligibility');
    final hasChosen = prefs.getBool('has_chosen_eligibility') ?? false;
    
    setState(() {
      // Only update eligibility from local if it wasn't already restored from RTDB/Firestore
      if (hasChosen && _showFirstTimeFlow) {
        _showFirstTimeFlow = false;
        if (selected != null) {
          eligibility = _normalizeSpecialization(selected);
        }
      } else if (hasChosen) {
        // Already had a value from RTDB/Firestore, just ensure local preference is applied
        if (selected != null) {
          eligibility = _normalizeSpecialization(selected);
        }
      }
      _ensurePnleCategoryScores();
    });
  }

  Future<void> _saveEligibilityPreference(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeSpecialization(value);
    await prefs.setString('selected_eligibility', normalized);
    await prefs.setBool('has_chosen_eligibility', true);
    
    setState(() {
      eligibility = normalized;
      _showFirstTimeFlow = false;
      _ensurePnleCategoryScores();
    });

    // Sync to RTDB (survives reinstall)
    _syncAllProgressToRtdb();
  }

  Future<void> _handleSpecializationSelection(String value) async {
    String resolved = value;
    if (value == 'Elementary Majors') {
      final picked = await showDialog<String>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => AlertDialog(
          title: Text(
            'Choose Elementary Track',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Select which Elementary Majors sub-category to focus on.',
            style: GoogleFonts.outfit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                'Elementary Majors - Early Childhood Education',
              ),
              child: const Text('Early Childhood Education'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                'Elementary Majors - Special Needs Education',
              ),
              child: const Text('Special Needs Education'),
            ),
          ],
        ),
      );

      if (picked == null) return;
      resolved = picked;
    }

    await _saveEligibilityPreference(resolved);
  }

  String _specializationDisplayLabel() {
    if (eligibility == 'Elementary Majors - Early Childhood Education') {
      return 'Elementary Majors (ECE)';
    }
    if (eligibility == 'Elementary Majors - Special Needs Education') {
      return 'Elementary Majors (SPED)';
    }
    return eligibility;
  }

  IconData _getSpecializationIcon(String spec) {
    switch (spec) {
      case 'Elementary Majors':
      case 'Elementary Majors - Early Childhood Education':
      case 'Elementary Majors - Special Needs Education':
        return Icons.school_rounded;
      case 'English Major':
        return Icons.language_rounded;
      case 'Filipino Major':
        return Icons.abc_rounded;
      case 'Mathematics Major':
        return Icons.calculate_rounded;
      case 'Science Major':
        return Icons.science_rounded;
      case 'Social Studies Major':
        return Icons.public_rounded;
      case 'Values Education Major':
        return Icons.favorite_rounded;
      case 'TLE Major':
        return Icons.build_rounded;
      case 'TVTEd Major':
        return Icons.engineering_rounded;
      case 'Physical Education Major':
        return Icons.fitness_center_rounded;
      case 'Culture and Arts Education Major':
        return Icons.palette_rounded;
      default:
        return Icons.book_rounded;
    }
  }

  String _normalizeSpecialization(String? value) {
    if (value == null || value.isEmpty) return 'English Major';
    if (value == 'Professional Eligibility' || value == 'Sub-Professional Eligibility') {
      return 'English Major';
    }

    const elementaryTracks = {
      'Elementary Majors - Early Childhood Education',
      'Elementary Majors - Special Needs Education',
    };
    if (elementaryTracks.contains(value)) return value;
    if (getAllSpecializations().contains(value)) return value;
    return 'English Major';
  }

  // =========================
  // ADMOB
  // =========================
  String get _rewardedAdUnitId {
    return AdMobIds.rewarded;
  }

  String get _bannerAdUnitId {
    return AdMobIds.banner;
  }

  String get _menuInterstitialAdUnitId {
    return AdMobIds.interstitial;
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
        },
        onAdFailedToLoad: (_) {
          _isAdLoaded = false;
        },
      ),
    );
  }

  void _loadMenuInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _menuInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _menuInterstitialAd = ad;
          _isMenuInterstitialLoaded = true;
        },
        onAdFailedToLoad: (_) {
          _isMenuInterstitialLoaded = false;
        },
      ),
    );
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  Future<bool> _showRewardedAd() async {
    if (!_isAdLoaded || _rewardedAd == null) return false;

    final completer = Completer<bool>();

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        completer.complete(true);
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (_, __) {
        completer.complete(false);
        _loadRewardedAd();
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (_, __) {});
    return completer.future;
  }

  Future<void> _initSubscriptionBilling() async {
    // Start with premium as false - only activate if purchase is verified
    await _clearPremiumStatus();

    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () {
        _purchaseSubscription?.cancel();
      },
    );

    final available = await _inAppPurchase.isAvailable();
    if (!mounted) return;

    setState(() {
      _isStoreAvailable = available;
    });

    if (!available) return;

    await _querySubscriptionProduct();
    // This will trigger _handlePurchaseUpdates with any active purchases
    try {
      await _inAppPurchase.restorePurchases();
    } on PlatformException catch (e) {
      debugPrint('restorePurchases failed: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('restorePurchases failed: $e');
    }
  }

  Future<void> _clearPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isPremiumUser');

    if (!mounted) return;
    setState(() {
      isPremiumUser = false;
      isTrialActive = false;
      trialEndDate = null;
      remainingFreeTests = 4;
    });
  }

  Future<bool> _querySubscriptionProduct() async {
    try {
      final response = await _inAppPurchase.queryProductDetails(
        {_premiumProductId},
      );

      if (!mounted) return false;

      if (response.error != null) {
        debugPrint(
          'queryProductDetails error: ${response.error!.code} ${response.error!.message}',
        );
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('queryProductDetails not found: ${response.notFoundIDs}');
      }

      if (response.productDetails.isNotEmpty) {
        ProductDetails? matchedProduct;
        for (final product in response.productDetails) {
          if (product.id == _premiumProductId) {
            matchedProduct = product;
            break;
          }
        }
        matchedProduct ??= response.productDetails.first;

        setState(() {
          _premiumProductDetails = matchedProduct;
        });
        return true;
      }

      setState(() {
        _premiumProductDetails = null;
      });
      return false;
    } on PlatformException catch (e) {
      debugPrint('queryProductDetails exception: ${e.code} ${e.message}');
      if (mounted) {
        setState(() {
          _premiumProductDetails = null;
        });
      }
      return false;
    } catch (e) {
      debugPrint('queryProductDetails exception: $e');
      if (mounted) {
        setState(() {
          _premiumProductDetails = null;
        });
      }
      return false;
    }
  }

  bool _looksLikeUserCancelled({String? code, String? message}) {
    final normalizedCode = code?.toLowerCase() ?? '';
    final normalizedMessage = message?.toLowerCase() ?? '';
    return normalizedCode.contains('cancel') ||
        normalizedMessage.contains('cancelled') ||
        normalizedMessage.contains('canceled');
  }

  bool _looksLikeAlreadySubscribed({String? code, String? message}) {
    final normalizedCode = code?.toLowerCase() ?? '';
    final normalizedMessage = message?.toLowerCase() ?? '';
    return normalizedCode.contains('duplicate') ||
        normalizedCode.contains('already') ||
        normalizedCode.contains('owned') ||
        normalizedMessage.contains('already') ||
        normalizedMessage.contains('active subscription') ||
        normalizedMessage.contains('already subscribed') ||
        normalizedMessage.contains('already purchased') ||
        normalizedMessage.contains('already own');
  }

  String _friendlyPurchaseFailureMessage({String? code, String? message}) {
    if (_looksLikeAlreadySubscribed(code: code, message: message)) {
      return 'You already have this subscription. Restoring purchases...';
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Unable to complete purchase right now. Please try again in a moment.';
    }

    return 'Unable to complete purchase right now. Please try again.';
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.productID != _premiumProductId) {
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() {
            _isPurchasePending = true;
          });
        }
      } else {
        if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          await _activatePremiumAccess();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✓ Premium subscription activated!'),
                duration: Duration(seconds: 2),
              ),
            );
          }

          final onSuccess = _onPremiumPurchaseSuccess;
          _onPremiumPurchaseSuccess = null;
          onSuccess?.call();
        } else if (purchaseDetails.status == PurchaseStatus.error) {
          final errorCode = purchaseDetails.error?.code;
          final errorMessage = purchaseDetails.error?.message;

          if (_looksLikeUserCancelled(code: errorCode, message: errorMessage)) {
            debugPrint('Purchase cancelled by user.');
          } else if (_looksLikeAlreadySubscribed(
            code: errorCode,
            message: errorMessage,
          )) {
            try {
              await _inAppPurchase.restorePurchases();
            } catch (_) {}

            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You already have this subscription. Restoring purchases...'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _friendlyPurchaseFailureMessage(
                    code: errorCode,
                    message: errorMessage,
                  ),
                ),
              ),
            );
          }

          debugPrint(
            'Purchase error: code=${purchaseDetails.error?.code} message=${purchaseDetails.error?.message}',
          );
        }

        if (mounted) {
          setState(() {
            _isPurchasePending = false;
          });
        }
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _startSubscriptionPurchase({VoidCallback? onSuccess}) async {
    if (_isPurchasePending) return;

    if (!mounted) return;

    if (!_isStoreAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store is not available right now. Please try again.'),
        ),
      );
      return;
    }

    if (_premiumProductDetails == null) {
      await _querySubscriptionProduct();
    }

    if (_premiumProductDetails == null) {
      final platformStoreName = defaultTargetPlatform == TargetPlatform.iOS
          ? 'App Store Connect'
          : 'Play Console';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Subscription product not found. Check your $platformStoreName product ID status.',
          ),
        ),
      );
      return;
    }

    _onPremiumPurchaseSuccess = onSuccess;

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      setState(() {
        _isPurchasePending = true;
      });
    }

    final purchaseParam = PurchaseParam(productDetails: _premiumProductDetails!);

    try {
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _isPurchasePending = false;
        });
      }
      _onPremiumPurchaseSuccess = null;

      if (_looksLikeUserCancelled(code: e.code, message: e.message)) {
        debugPrint('Purchase cancelled before confirmation.');
        return;
      }

      if (_looksLikeAlreadySubscribed(code: e.code, message: e.message)) {
        try {
          await _inAppPurchase.restorePurchases();
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You already have this subscription. Restoring purchases...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _friendlyPurchaseFailureMessage(code: e.code, message: e.message),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPurchasePending = false;
        });
      }
      _onPremiumPurchaseSuccess = null;

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to start purchase. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _restorePurchasesManually() async {
    if (_isPurchasePending) return;

    if (!_isStoreAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store is not available right now. Please try again.'),
        ),
      );
      return;
    }

    setState(() {
      _isPurchasePending = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking existing purchases...'),
        duration: Duration(seconds: 2),
      ),
    );

    await _inAppPurchase.restorePurchases();
  }

  Future<void> _activatePremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremiumUser', true);

    if (!mounted) return;
    setState(() {
      isPremiumUser = true;
      isTrialActive = false;
      trialEndDate = null;
      remainingFreeTests = 999;
    });
  }

  /// Load zero-ad sessions remaining from SharedPreferences
  Future<void> _loadZeroAdSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final remaining = prefs.getInt('zeroAdSessionsRemaining');
    if (remaining != null && mounted) {
      setState(() {
        _zeroAdSessionsRemaining = remaining;
      });
    }
  }

  /// Persist zero-ad sessions remaining to SharedPreferences and RTDB
  Future<void> _persistZeroAdSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zeroAdSessionsRemaining', _zeroAdSessionsRemaining);
    // Also sync to RTDB for cross-device/reinstall persistence
    _syncAllProgressToRtdb();
  }

  /// Reset daily category scores if it's a new day
  Future<void> _resetDailyCategoryScoresIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastResetStr = prefs.getString('lastCategoryScoreResetDate');
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    if (lastResetStr != null) {
      final lastReset = DateTime.parse(lastResetStr);
      final lastResetOnly = DateTime(lastReset.year, lastReset.month, lastReset.day);
      if (todayOnly.isAtSameMomentAs(lastResetOnly)) return; // Already reset today
    }

    // New day — reset category scores
    if (mounted) {
      setState(() {
        for (final key in categoryScores.keys) {
          categoryScores[key] = {
            'correct': 0,
            'total': categoryScores[key]!['total'],
            'weight': categoryScores[key]!['weight'],
          };
        }
      });
    }
    await prefs.setString('lastCategoryScoreResetDate', todayOnly.toIso8601String());
    await prefs.setString('categoryScores', jsonEncode(categoryScores));
  }

  /// Check if ads should be skipped due to zero-ad bonus
  /// Only applies to Random Quiz and Focus Mode (NOT Quick Practice)
  Future<bool> _shouldSkipAds(String testMode) async {
    // Zero-ads bonus ONLY for Random Quiz and Focus Mode
    if (testMode == 'quickPractice') {
      return false;
    }
    // Check if user has zero-ad sessions remaining
    return _zeroAdSessionsRemaining > 0;
  }

  Future<void> _watchRewardedAdForExtraQuiz() async {
    // Check if user has already watched max ads today (limit 2 per day)
    if (rewardedAdsWatchedToday >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only earn 2 extra quizzes per day')),
      );
      return;
    }
    
    // Show rewarded ad
    final adWatched = await _showRewardedAd();
    
    if (adWatched && mounted) {
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        remainingFreeTests++; // Grant 1 extra quiz
        rewardedAdsWatchedToday++;
        lastRewardedAdDay = DateTime.now();
      });
      
      // Save tracking
      await prefs.setInt('rewardedAdsWatchedToday', rewardedAdsWatchedToday);
      await prefs.setString('lastRewardedAdDay', DateTime.now().toIso8601String());
      
      // Persist free tests + ad count to RTDB immediately
      _persistDailyFreeTests();
      _syncAllProgressToRtdb();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ You earned 1 extra quiz! Keep it up! 🎯'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<bool> _showMenuInterstitialAd() async {
    if (!_isMenuInterstitialLoaded || _menuInterstitialAd == null) {
      _loadMenuInterstitialAd();
      return false;
    }

    final completer = Completer<bool>();
    _menuInterstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _menuInterstitialAd = null;
        _isMenuInterstitialLoaded = false;
        _loadMenuInterstitialAd();
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _menuInterstitialAd = null;
        _isMenuInterstitialLoaded = false;
        _loadMenuInterstitialAd();
        completer.complete(false);
      },
    );

    _menuInterstitialAd!.show();
    return completer.future;
  }

  List<Question> _quickPracticeFromSavedPool(String focusCategory) {
    final pooled = _savedSessions
        .expand((session) => session.questions)
        .where((question) => question.category == focusCategory)
        .map((question) => question.shuffled())
        .toList();
    pooled.shuffle(Random());
    return pooled.take(5).toList();
  }

  DeepSeekService _buildDeepSeekService({required bool fastMode, int? tokenCap}) {
    return DeepSeekService(
      apiKey: DEEPSEEK_API_KEY,
      requestTimeout: fastMode ? const Duration(seconds: 100) : const Duration(seconds: 90),
      maxRetries: fastMode ? 1 : 3,
      temperature: fastMode ? 0.2 : 0.3,
      maxTokens: tokenCap,
    );
  }

  Future<void> _primeFreeDeepSeekCaches() async {
    if (isPremiumUser || isTrialActive || _isPrimingFreeDeepSeekCache) return;

    final weakestCategory = _getWeakestCategory();
    if (weakestCategory.isEmpty) return;

    final hasQuickCache =
        _cachedQuickPracticeCategory == weakestCategory &&
        (_cachedQuickPracticeQuestions?.length ?? 0) >= 5;
    final hasFocusCache = (_cachedFocusQuestions[weakestCategory]?.length ?? 0) >= 15;
    if (hasQuickCache && hasFocusCache) return;

    _isPrimingFreeDeepSeekCache = true;
    try {
      final quickService = _buildDeepSeekService(fastMode: true, tokenCap: 1800);
      final focusService = _buildDeepSeekService(fastMode: true, tokenCap: 3200);

      if (!hasQuickCache) {
        final quickCategoryMap = {
          1: weakestCategory,
          2: weakestCategory,
          3: weakestCategory,
          4: weakestCategory,
          5: weakestCategory,
        };
        final quickQuestions = await quickService.generateQuestions(
          _buildFastQuickPracticePrompt(weakestCategory),
          eligibility,
          categoryMap: quickCategoryMap,
        );
        _cachedQuickPracticeCategory = weakestCategory;
        _cachedQuickPracticeQuestions = quickQuestions;
      }

      if (!hasFocusCache) {
        final focusQuestions = await focusService.generateQuestions(
          _buildFastFocusPrompt(weakestCategory),
          eligibility,
          categoryMap: _buildFocusCategoryMap(weakestCategory),
        );
        _cachedFocusQuestions[weakestCategory] = focusQuestions;
      }
    } catch (e) {
      debugPrint('Free DeepSeek cache warmup skipped: $e');
    } finally {
      _isPrimingFreeDeepSeekCache = false;
    }
  }

  // =========================
  // TEST GENERATION
  // =========================
  Future<bool> _generateTest({bool isFocusMode = false, String? focusCategory}) async {
    // Premium/Trial/Intro (first 4 sessions) → Gemini Flash Lite (fast), otherwise DeepSeek
    final useGemini =
      isPremiumUser || isTrialActive || _zeroAdSessionsRemaining > 0;
    
    // Use state variables if not passed as parameters
    final useFocusMode = isFocusMode || _isFocusMode;
    final category = focusCategory ?? _focusCategory;
    
    final prompt = useFocusMode && category != null
        ? _buildFocusPrompt(category)
        : _buildPrompt();
    final deepSeekPrompt = useFocusMode && category != null
      ? _buildFastFocusPrompt(category)
      : _buildFastPrompt();
    
    // Build category map for Focus Mode if applicable
    Map<int, String>? categoryMap;
    if (useFocusMode && category != null) {
      categoryMap = _buildFocusCategoryMap(category);
    }
    
    if (useGemini) {
      if (GEMINI_API_KEY.trim().isEmpty) {
        throw Exception('Gemini API key missing. Re-run with --dart-define=GEMINI_API_KEY=...');
      }
      try {
        final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
        _generatedQuestions = await service.generateQuestions(
          prompt, eligibility, categoryMap: categoryMap,
        );
      } catch (e) {
        final shouldFallbackToDeepSeek =
            _zeroAdSessionsRemaining > 0 && !isPremiumUser && !isTrialActive;
        if (!shouldFallbackToDeepSeek) rethrow;

        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          throw Exception('DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
        }

        final service = _buildDeepSeekService(fastMode: false);
        _generatedQuestions = await service.generateQuestions(
          prompt, eligibility, categoryMap: categoryMap,
        );
      }
    } else {
      if (DEEPSEEK_API_KEY.trim().isEmpty) {
        throw Exception('DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
      }
      if (useFocusMode && category != null) {
        final cached = _cachedFocusQuestions[category];
        if (cached != null && cached.length >= 15) {
          _generatedQuestions = cached.take(15).toList();
          _cachedFocusQuestions.remove(category);
          unawaited(_primeFreeDeepSeekCaches());
        } else {
          final service = _buildDeepSeekService(fastMode: true);
          _generatedQuestions = await service.generateQuestions(
            deepSeekPrompt, eligibility, categoryMap: categoryMap,
          );
        }
      } else {
        final service = _buildDeepSeekService(fastMode: true);
        _generatedQuestions = await service.generateQuestions(
          deepSeekPrompt, eligibility, categoryMap: categoryMap,
        );
      }
    }
    
    // Shuffle choices to avoid patterns in correct answers
    _generatedQuestions = _generatedQuestions.map((q) => q.shuffled()).toList();
    
    // Increment daily usage counter for premium users
    if ((isPremiumUser || isTrialActive) && _generatedQuestions.isNotEmpty) {
      _incrementGenerationUsage(_generatedQuestions.length);
    }
    
    // Clear focus mode state after generation
    _isFocusMode = false;
    _focusCategory = null;
    
    return _generatedQuestions.isNotEmpty;
  }

  /// Build category map for Focus Mode (10 focus + 5 mixed)
  Map<int, String> _buildFocusCategoryMap(String focusCategory) {
    final categoryMap = <int, String>{};
    final categories = _categoriesForEligibility();
    final otherCategories = categories.where((cat) => cat != focusCategory).toList();
    
    // Questions 1-10: Focus category
    for (int q = 1; q <= 10; q++) {
      categoryMap[q] = focusCategory;
    }
    
    // Questions 11-15: Other categories (mixed)
    int questionNum = 11;
    for (int i = 0; i < otherCategories.length && questionNum <= 15; i++) {
      final cat = otherCategories[i];
      final questionsInCat = (15 - questionNum + 1) ~/ (otherCategories.length - i);
      for (int j = 0; j < questionsInCat && questionNum <= 15; j++) {
        categoryMap[questionNum] = cat;
        questionNum++;
      }
    }
    
    return categoryMap;
  }

  Map<String, String> _generateTestCoverage() {
    final random = Random();
    final Map<String, String> selected = {};

    final categories = _categoriesForEligibility();

    for (final category in categories) {
      // Get topics from keyAreas for each UPCAT category
      final topics = keyAreas[category];
      if (topics == null || topics.isEmpty) {
        debugPrint('⚠️ No topics found for category: $category');
        selected[category] = 'General topics';
      } else {
        selected[category] = topics[random.nextInt(topics.length)];
      }
    }

    return selected;
  }

  Map<String, String> _generateFocusModeCoverage(String focusCategory) {
    final random = Random();
    final Map<String, String> selected = {};
    final categories = _categoriesForEligibility();

    // Generate topics for all categories (for the 5 mixed questions in focus mode)
    for (final category in categories) {
      final topics = keyAreas[category];
      if (topics == null || topics.isEmpty) {
        debugPrint('⚠️ No topics found for category: $category');
        selected[category] = 'General topics';
      } else {
        selected[category] = topics[random.nextInt(topics.length)];
      }
    }

    return selected;
  }

  // Quick Practice Mode (5 questions - free users get 1/day, premium unlimited)
  Future<void> _startQuickPractice() async {
    final weakestCategory = _getWeakestCategory();
    
    if (weakestCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete at least one quiz first to unlock Quick Practice'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!isPremiumUser &&
        !isTrialActive &&
        _cachedQuickPracticeCategory == weakestCategory &&
        (_cachedQuickPracticeQuestions?.length ?? 0) >= 5) {
      final cachedQuestions = _cachedQuickPracticeQuestions!.take(5).toList();
      _cachedQuickPracticeQuestions = null;
      _cachedQuickPracticeCategory = null;
      unawaited(_primeFreeDeepSeekCaches());

      final results = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionScreen(
            questions: cachedQuestions,
            isPremium: false,
            recordResults: false,
            testMode: 'quickPractice',
            zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
          ),
        ),
      );

      if (results != null && mounted) {
        _updateTestResults(results);
      }
      return;
    }

    final pooledQuestions = _quickPracticeFromSavedPool(weakestCategory);

    if (pooledQuestions.length >= 5) {
      final results = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionScreen(
            questions: pooledQuestions,
            isPremium: isPremiumUser || isTrialActive,
            recordResults: false,
            testMode: 'quickPractice',
            zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
          ),
        ),
      );

      if (results != null && mounted) {
        _updateTestResults(results);
      }
      return;
    }

    _showQuickPracticeDialog();

    try {
        final shouldSkipAds = await _shouldSkipAds('quickPractice');
        final adFuture = (!isPremiumUser && !isTrialActive && !shouldSkipAds)
          ? _showMenuInterstitialAd()
          : Future.value(true);

        // Premium/Trial/Intro (first 4 sessions) → Gemini Flash Lite (fast), otherwise DeepSeek
        final useGemini =
          isPremiumUser || isTrialActive || _zeroAdSessionsRemaining > 0;
        final prompt = useGemini
          ? _buildQuickPracticePrompt(weakestCategory)
          : _buildFastQuickPracticePrompt(weakestCategory);
      
      // Build category map for Quick Practice (all 5 questions from weakest category)
      final categoryMap = <int, String>{
        1: weakestCategory,
        2: weakestCategory,
        3: weakestCategory,
        4: weakestCategory,
        5: weakestCategory,
      };
      
      late final List<Question> questions;
      if (useGemini) {
        if (GEMINI_API_KEY.trim().isEmpty) {
          throw Exception('Gemini API key missing. Re-run with --dart-define=GEMINI_API_KEY=...');
        }
        try {
          final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
          questions = await service.generateQuestions(prompt, eligibility, categoryMap: categoryMap);
        } catch (e) {
          final shouldFallbackToDeepSeek =
              _zeroAdSessionsRemaining > 0 && !isPremiumUser && !isTrialActive;
          if (!shouldFallbackToDeepSeek) rethrow;

          if (DEEPSEEK_API_KEY.trim().isEmpty) {
            throw Exception('DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
          }

          final service = _buildDeepSeekService(fastMode: false);
          questions = await service.generateQuestions(prompt, eligibility, categoryMap: categoryMap);
        }
      } else {
        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          throw Exception('DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
        }
        final service = _buildDeepSeekService(fastMode: true, tokenCap: 1800);
        questions = await service.generateQuestions(prompt, eligibility, categoryMap: categoryMap);
      }
        await adFuture;
      
      if (!mounted) return;
      Navigator.pop(context); // Close generation dialog

      if (questions.isNotEmpty) {
        final results = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuestionScreen(
              questions: questions.take(5).toList(),
              isPremium: isPremiumUser || isTrialActive,
              recordResults: false, // Quick Practice doesn't count toward objective
              testMode: 'quickPractice',
              zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
            ),
          ),
        );
        
        if (results != null && mounted) {
          _updateTestResults(results);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating questions: ${e.toString()}')),
        );
      }
    }
  }

  // Challenge Mode (10 advanced questions - premium only)
  Future<void> _startChallengeMode() async {
    if (!isPremiumUser && !isTrialActive) {
      // Show subscription dialog for Challenge Mode
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (context) => SubscriptionDialog(
          onStartTrial: () async {
            Navigator.pop(context);
            await _startTrialFlow(onPremiumActivated: _launchChallengeMode);
          },
          onRestorePurchases: () async {
            Navigator.pop(context);
            await _restorePurchasesManually();
          },
          onClose: () {
            Navigator.pop(context);
          },
          triggerSource: 'challenge_mode',
        ),
      );
      return;
    }

    _launchChallengeMode();
  }

  Future<void> _launchChallengeMode() async {
    // Check daily generation limit
    if (!_canGenerateMoreQuestions(10)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Daily limit reached: $_dailyGenerationSessionsUsed/$_maxDailyGenerationSessions sessions used today',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: PnleTheme.bgTop,
        ),
      );
      return;
    }

    // Show simple loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                PnleTheme.bgTop.withOpacity(0.95),
                PnleTheme.bgBottom.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amber.withOpacity(0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_rounded, color: Colors.amber.shade200, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'CHALLENGE MODE',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.amber.shade200),
              ),
              const SizedBox(height: 14),
              Text(
                'Generating advanced questions...',
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
        // Premium/Trial/Intro (first 4 sessions) → Gemini Flash Lite (fast), otherwise DeepSeek
        final useGemini =
          isPremiumUser || isTrialActive || _zeroAdSessionsRemaining > 0;
      // Generate random category focus for challenge
      final categories = _categoriesForEligibility();
      final focusCategory = categories[Random().nextInt(categories.length)];
        final prompt = useGemini
          ? _buildChallengeModePrompt(focusCategory)
          : _buildFastChallengeModePrompt(focusCategory);
      
      // Build category map for Challenge Mode (10 questions)
      final categoryMap = <int, String>{
        1: focusCategory,
        2: focusCategory,
        3: focusCategory,
        4: focusCategory,
        5: focusCategory,
        6: focusCategory,
      };
      
      final otherCategories = categories.where((cat) => cat != focusCategory).toList();
      if (otherCategories.length == 1) {
        for (int q = 7; q <= 10; q++) {
          categoryMap[q] = otherCategories[0];
        }
      } else if (otherCategories.length == 2) {
        categoryMap[7] = otherCategories[0];
        categoryMap[8] = otherCategories[0];
        categoryMap[9] = otherCategories[1];
        categoryMap[10] = otherCategories[1];
      } else if (otherCategories.length == 3) {
        categoryMap[7] = otherCategories[0];
        categoryMap[8] = otherCategories[1];
        categoryMap[9] = otherCategories[2];
        categoryMap[10] = otherCategories[2];
      }
      
      late final List<Question> questions;
      if (useGemini) {
        if (GEMINI_API_KEY.trim().isEmpty) {
          throw Exception('Gemini API key missing. Re-run with --dart-define=GEMINI_API_KEY=...');
        }
        try {
          final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
          questions = await service.generateQuestions(prompt, eligibility, categoryMap: categoryMap);
        } catch (e) {
          final shouldFallbackToDeepSeek =
              _zeroAdSessionsRemaining > 0 && !isPremiumUser && !isTrialActive;
          if (!shouldFallbackToDeepSeek) rethrow;

          if (DEEPSEEK_API_KEY.trim().isEmpty) {
            throw Exception('DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
          }

          final service = _buildDeepSeekService(fastMode: false);
          questions = await service.generateQuestions(prompt, eligibility, categoryMap: categoryMap);
        }
      } else {
        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          throw Exception('DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
        }
        final service = _buildDeepSeekService(fastMode: true, tokenCap: 2200);
        questions = await service.generateQuestions(prompt, eligibility, categoryMap: categoryMap);
      }
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (questions.isNotEmpty) {
        // Increment daily usage counter
        _incrementGenerationUsage(questions.length);
        
        final results = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuestionScreen(
              questions: questions.take(10).toList(),
              isPremium: isPremiumUser || isTrialActive,
              recordResults: false,
              testMode: 'challenge',
              zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
            ),
          ),
        );
        
        if (results != null && mounted) {
          _updateTestResults(results);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating challenge: ${e.toString()}')),
        );
      }
    }
  }

  List<String> _categoriesForEligibility() {
    return pnleCategories;
  }

  String _getWeakestCategory() {
    final categories = _categoriesForEligibility();
    String weakest = '';
    double lowestPercentage = 100;

    for (final cat in categories) {
      final data = categoryScores[cat];
      if (data == null) {
        debugPrint('⚠️ Category $cat not found in categoryScores');
        continue;
      }
      final correct = data['correct'] as int;
      final total = data['total'] as int;
      
      if (total > 0) {
        final percentage = (correct / total) * 100;
        if (percentage < lowestPercentage) {
          lowestPercentage = percentage;
          weakest = cat;
        }
      }
    }
    return weakest;
  }

  Widget _buildCircularProgressCard(double totalAvg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.11),
            Colors.white.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 156,
                height: 156,
                child: CircularProgressIndicator(
                  value: (totalAvg / 100).clamp(0.0, 1.0),
                  strokeWidth: 9,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    totalAvg >= 65
                        ? PnleTheme.success
                      : totalAvg >= 50
                            ? PnleTheme.warning
                            : PnleTheme.danger,
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${totalAvg.toStringAsFixed(1)}%',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 36,
                    ),
                  ),
                  Text(
                    'Overall Average',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            totalAvg >= 65
                ? '🎉 Excellent! You\'re on track!'
              : totalAvg >= 50
                ? '⚠️ Keep practicing to reach 65%'
                    : '📚 More practice needed',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // _buildQuickStats removed - no longer used in UI
  
  // _buildStatItem removed - was only called by removed _buildQuickStats method

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 18) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  String _getGreetingWithName() {
    return '${_getGreeting()} there! 👋';
  }

  // =========================
  // GENERATION DIALOG
  // =========================
  void _showQuickPracticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                PnleTheme.bgTop.withOpacity(0.95),
                PnleTheme.bgBottom.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.purple.withOpacity(0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flash_on_rounded, color: Colors.purple.shade200, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'QUICK PRACTICE',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple.shade200),
              ),
              const SizedBox(height: 14),
              Text(
                'Generating questions...',
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGenerationDialog({String? modeLabel}) {
    final effectiveModeLabel = modeLabel ??
        (_isFocusMode
            ? 'FOCUS MODE${_focusCategory != null ? ' • ${_focusCategory!}' : ''}'
            : 'RANDOM QUIZ');

    // Check daily generation limit for premium users
    if (isPremiumUser || isTrialActive) {
      if (!_canGenerateMoreQuestions(_isFocusMode ? 15 : 20)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Daily limit reached: $_dailyGenerationSessionsUsed/$_maxDailyGenerationSessions sessions used today',
              style: GoogleFonts.outfit(),
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: PnleTheme.bgTop,
          ),
        );
        return;
      }
    }

    _shouldSkipAds(_isFocusMode ? 'focusMode' : 'randomQuiz').then((skipAds) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (context) {
          return GeneratingTestDialog(
            onGenerate: _generateTest,
            onShowAd: (isPremiumUser || skipAds) ? null : _showRewardedAd,
            onSuccess: isPremiumUser ? null : _onGenerationSuccess,
            isPremium: isPremiumUser,
            isFocusMode: _isFocusMode,
            focusCategory: _focusCategory,
            modeLabel: effectiveModeLabel,
            onStart: () async {
              Navigator.pop(context); // Close Test Coverage dialog
              _addSavedSession(_generatedQuestions, _currentTestCoverage);
              // Function to start the test
              Future<void> startTest(List<Question> questions) async {
                final results = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuestionScreen(
                      questions: questions,
                      isPremium: isPremiumUser || isTrialActive,
                      recordResults: true,
                      testMode: _isFocusMode ? 'focusMode' : 'randomQuiz',
                      zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
                    ),
                  ),
                );
                if (results is Map<String, dynamic> && mounted) {
                  _updateTestResults(results);
                  final nextAction = results['nextAction'];
                  if (nextAction == 'playAgain') {
                    if (_currentTestCoverage != null) {
                      _showTestCoverageDialog(
                        _currentTestCoverage!,
                        isFocusMode: _isFocusMode,
                        focusCategory: _focusCategory,
                      );
                    }
                  } else if (nextAction == 'menu') {
                    setState(() {
                      currentScreen = 0;
                    });
                  }
                }
                // Handle different return values
                else if (results == 'playAgain' && mounted) {
                  // User clicked Play Again - show Test Coverage dialog again for new test
                  if (_currentTestCoverage != null) {
                    _showTestCoverageDialog(
                      _currentTestCoverage!,
                      isFocusMode: _isFocusMode,
                      focusCategory: _focusCategory,
                    );
                  }
                } else if (results == 'menu' && mounted) {
                  // User clicked Main Menu - reset to Home section
                  setState(() {
                    currentScreen = 0; // 0 = Home
                  });
                } else if (results != null && mounted) {
                  // Normal completion - update results
                  _updateTestResults(results);
                }
              }
              await startTest(_generatedQuestions);
            },
          );
        },
      );
    });
  }

  void _onGenerationSuccess() {
    // Only called for free users on successful generation
    setState(() {
      remainingFreeTests--;
    });
    // Persist daily free tests locally
    _persistDailyFreeTests();
    
    // Decrement zero-ad sessions for Random Quiz / Focus Mode
    if (_zeroAdSessionsRemaining > 0) {
      _zeroAdSessionsRemaining--;
      _persistZeroAdSessions();
    }
  }

  String _pickSavedTitle(Map<String, String>? coverage) {
    if (coverage == null || coverage.isEmpty) {
      return 'Saved Session';
    }
    final values = coverage.values.toList();
    return values[Random().nextInt(values.length)];
  }

  void _addSavedSession(
    List<Question> questions,
    Map<String, String>? coverage,
  ) {
    final title = _pickSavedTitle(coverage);
    final savedSession = _SavedSession(title: title, questions: questions);
    final activityRecord = _QuizActivityRecord(
      date: DateTime.now(),
      questionCount: questions.length,
    );

    setState(() {
      _savedSessions.insert(0, savedSession);
      if (_savedSessions.length > 20) {
        _savedSessions.removeLast();
      }

      _quizActivityRecords.insert(0, activityRecord);
      _pruneQuizActivityRecords();
    });

    _persistQuizActivityRecords();
    _syncAllProgressToRtdb();
  }

  void _showSavedTestsDialog() {
    if (!isPremiumUser && !isTrialActive) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (context) => SubscriptionDialog(
          onStartTrial: () async {
            Navigator.pop(context);
            await _startTrialFlow();
          },
          onRestorePurchases: () async {
            Navigator.pop(context);
            await _restorePurchasesManually();
          },
          onClose: () {
            Navigator.pop(context);
          },
          triggerSource: 'saved_tests',
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [PnleTheme.bgTop, PnleTheme.bgBottom],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: PnleTheme.accent.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: PnleTheme.accent.withOpacity(0.5),
                            ),
                          ),
                          child: const Icon(
                            Icons.history_rounded,
                            color: PnleTheme.accent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saved Tests',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              ),
                              Text(
                                '${_savedSessions.length}/20 tests saved',
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: Icon(
                              Icons.close,
                              color: Colors.white.withOpacity(0.8),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(
                      color: Colors.white.withOpacity(0.2),
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 20),
                    // Notice about saved tests
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saved tests are stored locally. They will be deleted if you reinstall the app or clear app data.',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Content
                    if (_savedSessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 64,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No saved tests yet',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Complete a quiz to save it here',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _savedSessions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final session = _savedSessions[index];
                            final questionCount = session.questions.length;
                            final timeAgo = _formatTimeAgo(session.savedAt);
                            
                            return Dismissible(
                              key: Key('session_${session.savedAt.millisecondsSinceEpoch}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.delete_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              onDismissed: (direction) {
                                setDialogState(() {
                                  _savedSessions.removeAt(index);
                                });
                                if (mounted) {
                                  setState(() {});
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Test deleted',
                                        style: GoogleFonts.outfit(),
                                      ),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: PnleTheme.bgTop,
                                    ),
                                  );
                                }
                              },
                              child: GestureDetector(
                                onTap: () async {
                                  Navigator.pop(context);
                                  // Shuffle choices each time a saved test is replayed
                                  final shuffledQuestions = session.questions
                                      .map((q) => q.shuffled())
                                      .toList();
                                  
                                  // Function to start/replay the test
                                  Future<void> startTest(List<Question> questions) async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => QuestionScreen(
                                          questions: questions,
                                          isPremium: isPremiumUser || isTrialActive,
                                          recordResults: false,
                                          testMode: 'previous',
                                          zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
                                        ),
                                      ),
                                    );
                                    
                                    // Handle Play Again - reshuffle the same questions
                                    if (result == 'playAgain' && mounted) {
                                      final reshuffledQuestions = session.questions
                                          .map((q) => q.shuffled())
                                          .toList();
                                      await startTest(reshuffledQuestions);
                                    } else if (result == 'menu' && mounted) {
                                      // User clicked Main Menu - reset to Home section
                                      setState(() {
                                        currentScreen = 0; // 0 = Home
                                      });
                                    }
                                  }
                                  
                                  await startTest(shuffledQuestions);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.15),
                                        Colors.white.withOpacity(0.08),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: PnleTheme.accent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.quiz_rounded,
                                          color: PnleTheme.accent,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              session.title,
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.help_outline_rounded,
                                                  size: 14,
                                                  color: Colors.white.withOpacity(0.6),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$questionCount questions',
                                                  style: GoogleFonts.outfit(
                                                    color: Colors.white.withOpacity(0.6),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Icon(
                                                  Icons.access_time_rounded,
                                                  size: 14,
                                                  color: Colors.white.withOpacity(0.6),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  timeAgo,
                                                  style: GoogleFonts.outfit(
                                                    color: Colors.white.withOpacity(0.6),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white.withOpacity(0.7),
                                        size: 28,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (_savedSessions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Swipe left to delete',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  void _updateTestResults(dynamic results) {
    if (results is! Map<String, dynamic>) return;

    final correctCount = results['correctCount'] as Map<String, int>?;
    final totalCount = results['totalCount'] as Map<String, int>?;

    if (correctCount == null || totalCount == null) return;

    // Assess only first 4 completed sessions
    if (completedSessions >= 4) return;

    setState(() {
      // Increment completed sessions
      completedSessions++;

      // Accumulate category scores across sessions
      correctCount.forEach((category, correct) {
        if (categoryScores.containsKey(category)) {
          final currentCorrect = categoryScores[category]!['correct'] as int;
          final maxTotal = categoryScores[category]!['total'] as int;
          final updatedCorrect = currentCorrect + correct;

          categoryScores[category]!['correct'] =
              updatedCorrect > maxTotal ? maxTotal : updatedCorrect;
        }
      });

      // Only update streak if user completed all 4 sessions
      if (completedSessions == 4) {
        _updateStreakAfterQuiz();
      }
      
      // Update accumulated stats that persist across days
      accumulatedQuizzesCompleted++;
      totalCount.forEach((category, count) {
        accumulatedQuestionsAnswered += count;
      });
    });

    // Persist all data
    _persistAccumulatedStats();
    _persistCategoryScores();
    _persistCompletedSessions();
  }

  /// Generate dynamic streak motivation text based on daily session progress
  String _getStreakMotivationText() {
    if (completedSessions == 0) {
      return 'Complete 4 sessions today to keep your streak alive! 💪';
    } else if (completedSessions == 1) {
      return 'Complete 3 more sessions today to keep your streak alive! 💪';
    } else if (completedSessions == 2) {
      return 'Complete 2 more sessions today to keep your streak alive! 💪';
    } else if (completedSessions == 3) {
      return 'Complete 1 more session today to keep your streak alive! 💪';
    } else {
      // completedSessions == 4
      return 'Congrats! You completed 4 sessions—you\'re on a streak! 🎉🔥';
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    // Set status bar to be transparent with light icons
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: PnleTheme.appBackground,
                  ),
                ),
                Positioned(
                  top: -120,
                  right: -80,
                  child: Container(
                    height: 240,
                    width: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          PnleTheme.glowA.withOpacity(0.28),
                          PnleTheme.glowA.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -140,
                  left: -60,
                  child: Container(
                    height: 260,
                    width: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          PnleTheme.glowB.withOpacity(0.24),
                          PnleTheme.glowB.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildScreen(),
              ],
            ),
          ),
          // Banner Ad (only for free users) - positioned at bottom above nav bar
          if (!isPremiumUser && !isTrialActive && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _getCurrentScreenWidget(),
      ),
    );
  }

  Widget _settingsScreen() {
    return SettingsScreen(
      isPremium: isPremiumUser,
      isTrialActive: isTrialActive,
      trialEndDate: trialEndDate,
      embedded: true,
      onPremiumActivated: () {
        _startTrialFlow();
      },
      onRestorePurchases: () async {
        await _restorePurchasesManually();
      },
    );
  }

  Widget _getCurrentScreenWidget() {
    switch (currentScreen) {
      case 0:
        return _homeScreen();
      case 1:
        return _dailyPerformanceScreen();
      case 2:
        return _startQuizScreen();
      case 3:
        return _historyScreen();
      case 4:
        return _settingsScreen();
      default:
        return _homeScreen();
    }
  }

  Widget _homeScreen() {
    return SingleChildScrollView(
      key: const PageStorageKey('home_screen'),
      controller: _homeScrollController,
      child: _glassContainer(
        borderRadius: 26,
        padding: const EdgeInsets.all(16),
        child: _buildNormalHomeFlow(),
      ),
    );
  }

  Widget _buildFirstTimeEligibilityFlow() {
    // Show centered popup only once
    if (!_hasShownSpecializationDialog) {
      _hasShownSpecializationDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSpecializationSelectionDialog();
        }
      });
    }
    
    // Return a placeholder while dialog shows
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [PnleTheme.bgTop, PnleTheme.bgBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(PnleTheme.accent),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading specializations...',
              style: GoogleFonts.outfit(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpecializationSelectionDialog() {
    final specializations = getAllSpecializations();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                PnleTheme.bgTop.withOpacity(0.98),
                PnleTheme.bgBottom.withOpacity(0.98),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: PnleTheme.accent.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(),
                    child: Column(
                      children: [
                        Text(
                          'Select your Focus Category',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: PnleTheme.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Scrollable list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: specializations.length,
                      itemBuilder: (context, index) {
                        final spec = specializations[index];
                        String displayName = spec;
                        String description = '';
                        IconData icon = Icons.book_rounded;
                        
                        // Customize display for each specialization
                        switch (spec) {
                          case 'Elementary Majors':
                            description = 'Early Childhood & Special Needs';
                            icon = Icons.school_rounded;
                            break;
                          case 'English Major':
                            description = 'Language & Communication';
                            icon = Icons.language_rounded;
                            break;
                          case 'Filipino Major':
                            description = 'Filipino Language & Literature';
                            icon = Icons.abc_rounded;
                            break;
                          case 'Mathematics Major':
                            description = 'Numbers & Calculations';
                            icon = Icons.calculate_rounded;
                            break;
                          case 'Science Major':
                            description = 'Natural Sciences';
                            icon = Icons.science_rounded;
                            break;
                          case 'Social Studies Major':
                            description = 'History & Social Sciences';
                            icon = Icons.public_rounded;
                            break;
                          case 'Values Education Major':
                            description = 'Ethics & Values';
                            icon = Icons.favorite_rounded;
                            break;
                          case 'TLE Major':
                            description = 'Technical & Livelihood';
                            icon = Icons.build_rounded;
                            break;
                          case 'TVTEd Major':
                            description = 'Technical-Vocational Ed';
                            icon = Icons.engineering_rounded;
                            break;
                          case 'Physical Education Major':
                            description = 'Health & Physical Education';
                            icon = Icons.fitness_center_rounded;
                            break;
                          case 'Culture and Arts Education Major':
                            description = 'Arts & Cultural Education';
                            icon = Icons.palette_rounded;
                            break;
                        }
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _handleSpecializationSelection(spec);
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.08),
                                      Colors.white.withOpacity(0.03),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: PnleTheme.accent.withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: PnleTheme.accent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        icon,
                                        color: PnleTheme.accent,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            description,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white.withOpacity(0.6),
                                              fontWeight: FontWeight.w400,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      color: PnleTheme.accent.withOpacity(0.5),
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalHomeFlow() {
    final totalAvg = _calculateTotalAverage();
    // final percentToPass = (80 - totalAvg).clamp(0.0, 100.0); // Removed - not using recommendation system yet
    final weakestCategory = _getWeakestCategory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          _getGreetingWithName(),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          motivationalQuotes[Random().nextInt(motivationalQuotes.length)],
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: Colors.white.withOpacity(0.85),
            fontWeight: FontWeight.w500,
            fontSize: 14,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 28),

        // Daily Streak Badge
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.orange.withOpacity(0.3),
                Colors.red.withOpacity(0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Text(
                    '$currentStreak day streak!',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _getStreakMotivationText(),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.75),
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Circular Progress
        _buildCircularProgressCard(totalAvg),
        const SizedBox(height: 24),

        // Smart Recommendation
        if (weakestCategory.isNotEmpty && accumulatedQuizzesCompleted > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.5)),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF6B6B).withOpacity(0.15),
                  const Color(0xFFFF6B6B).withOpacity(0.05),
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    color: Color(0xFFFF6B6B), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Focus Area',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFFF6B6B),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Improve $weakestCategory to boost your score',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 8),
      ],
    );
  }

  Widget _startQuizScreen() {
    final totalAvg = _calculateTotalAverage();
    final weakestCategory = _getWeakestCategory();
    // Use accumulated stats that persist across sessions
    final totalQuizzesTaken = accumulatedQuizzesCompleted;
    final totalQuestionsAnswered = accumulatedQuestionsAnswered;
    final bestScore = totalAvg;
    final canTakeQuiz = isPremiumUser || isTrialActive || remainingFreeTests > 0;
    final isFreeLimitReached = !isPremiumUser && !isTrialActive && remainingFreeTests <= 0;

    return Stack(
      children: [
        _glassContainer(
          borderRadius: 26,
          padding: const EdgeInsets.all(16),
          child: ListView(
            key: const PageStorageKey('start_quiz_screen'),
            controller: _quizScrollController,
            children: [
              const SizedBox(height: 16),
              
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.25),
                        Colors.white.withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(
                    'UPCAT Standard Mix • 15 Questions',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Quick Stats Dashboard
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'YOUR STATS',
                      style: GoogleFonts.outfit(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _quickStat(
                          icon: Icons.checklist_rounded,
                          value: '$totalQuizzesTaken',
                          label: 'Quizzes',
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        _quickStat(
                          icon: Icons.question_answer_rounded,
                          value: '$totalQuestionsAnswered',
                          label: 'Questions',
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        _quickStat(
                          icon: Icons.emoji_events_rounded,
                          value: '${bestScore.toStringAsFixed(1)}%',
                          label: 'Best Score',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Daily Progress Tracker & Motivational Elements
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withOpacity(0.3),
                      Colors.orange.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Today\'s Progress',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sessions: $completedSessions/4',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Streak: $currentStreak ${currentStreak == 1 ? 'day' : 'days'} 🔥',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (!isPremiumUser && !isTrialActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: PnleTheme.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              remainingFreeTests > 100 ? 'Unlimited' : '$remainingFreeTests left',
                              style: GoogleFonts.outfit(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Smart Recommendations
              if (weakestCategory.isNotEmpty && totalAvg < 65 && accumulatedQuizzesCompleted > 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF34D399).withOpacity(0.2),
                        const Color(0xFF34D399).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF34D399).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tips_and_updates_rounded,
                          color: Color(0xFF34D399), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Tip',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF34D399),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                                totalAvg < 50
                                  ? 'Focus on $weakestCategory to improve your score quickly!'
                                  : 'You\'re ${(65 - totalAvg).toStringAsFixed(1)}% away from your goal. Keep going!',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (weakestCategory.isNotEmpty && totalAvg < 65 && accumulatedQuizzesCompleted > 0)
                const SizedBox(height: 24),

              if (isFreeLimitReached)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        PnleTheme.accent.withOpacity(0.24),
                        PnleTheme.accent.withOpacity(0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PnleTheme.accent.withOpacity(0.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily free limit reached',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Unlock unlimited quiz sessions with Premium or start your trial now.',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.86),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _showPremiumOfferDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PnleTheme.accent,
                          foregroundColor: PnleTheme.bgBottom,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        child: Text(
                          'Start Trial / Upgrade',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Quiz Mode Selection Header (moved up to avoid scrolling)
              Text(
                'SELECT QUIZ MODE',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              // Quiz Mode Cards
              // 1. Random Quiz (Main mode)
              _quizModeCard(
                icon: Icons.shuffle_rounded,
                title: 'Random Quiz',
                description: 'Mixed questions from all categories',
                gradient: canTakeQuiz
                    ? _modeFadeGradient()
                    : LinearGradient(
                        colors: [Colors.grey.shade600, Colors.grey.shade700],
                      ),
                onTap: canTakeQuiz
                    ? () async {
                        try {
                          final coverage = _generateTestCoverage();
                          _showTestCoverageDialog(coverage);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString()}')),
                          );
                        }
                      }
                    : _showPremiumOfferDialog,
                isPrimary: true,
                badge: isFreeLimitReached ? 'LIMIT' : null,
                isLocked: false,
              ),
              const SizedBox(height: 12),

              // Extra Quiz via Rewarded Ad
              if (!isPremiumUser && !isTrialActive && remainingFreeTests < 4)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: _modeFadeGradientWithColors(
                      Colors.purple.shade700,
                      Colors.purple.shade500,
                      strength: 0.82,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.purple.shade300.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Watch Ad for Extra Quiz',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${rewardedAdsWatchedToday}/2 today',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: rewardedAdsWatchedToday >= 2
                            ? null
                            : _watchRewardedAdForExtraQuiz,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          disabledBackgroundColor: Colors.grey.shade600,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          rewardedAdsWatchedToday >= 2 ? 'Max Ads' : 'Watch Ad',
                          style: GoogleFonts.outfit(
                            color: rewardedAdsWatchedToday >= 2
                                ? Colors.grey.shade400
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // 2. Focus Mode
              _quizModeCard(
                icon: Icons.center_focus_strong_rounded,
                title: 'Focus Mode',
                description:
                    weakestCategory.isNotEmpty
                        ? 'Target: $weakestCategory'
                        : 'Build strength in weak areas',
                gradient: _modeFadeGradientWithColors(
                  const Color(0xFFFF6B6B),
                  const Color(0xFFFF8A80),
                  strength: 0.9,
                ),
                onTap: weakestCategory.isNotEmpty
                    ? () async {
                        if (!canTakeQuiz) {
                          _showPremiumOfferDialog();
                          return;
                        }
                        try {
                          final coverage = _generateFocusModeCoverage(weakestCategory);
                          _showTestCoverageDialog(
                            coverage,
                            isFocusMode: true,
                            focusCategory: weakestCategory,
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString()}')),
                          );
                        }
                      }
                    : null,
                badge: isFreeLimitReached && weakestCategory.isNotEmpty ? 'LIMIT' : null,
                isLocked: weakestCategory.isEmpty,
              ),
              const SizedBox(height: 12),

              // 3. Quick Practice
              _quizModeCard(
                icon: Icons.flash_on_rounded,
                title: 'Quick Practice',
                description: '5 questions • Perfect for breaks',
                gradient: _modeFadeGradientWithColors(
                  Colors.purple,
                  Colors.deepPurple,
                  strength: 0.8,
                ),
                onTap: () => _startQuickPractice(),
                badge: null,
                isLocked: false,
              ),
              const SizedBox(height: 12),

              // 4. Challenge Mode (Premium)
              _quizModeCard(
                icon: Icons.emoji_events_rounded,
                title: 'Challenge Mode',
                description: 'Harder questions • Premium only',
                gradient: _modeFadeGradientWithColors(
                  Colors.amber,
                  Colors.orange,
                  strength: 0.86,
                ),
                onTap: isPremiumUser || isTrialActive
                    ? () => _startChallengeMode()
                    : _showPremiumOfferDialog,
                badge: isPremiumUser || isTrialActive ? null : 'PREMIUM',
                isLocked: !(isPremiumUser || isTrialActive),
                showPremiumBanner: !(isPremiumUser || isTrialActive),
              ),
              const SizedBox(height: 12),

              // 5. Load Saved Test
              if (_savedSessions.isNotEmpty)
                _quizModeCard(
                  icon: Icons.history_rounded,
                  title: 'Load Saved Test',
                  description: '${_savedSessions.length} saved ${_savedSessions.length == 1 ? 'test' : 'tests'} available',
                  gradient: _modeFadeGradientWithColors(
                    Colors.blueGrey,
                    Colors.blue,
                    strength: 0.74,
                  ),
                  onTap: _showSavedTestsDialog,
                  badge: isPremiumUser || isTrialActive ? '${_savedSessions.length}' : 'PREMIUM',
                  isLocked: !(isPremiumUser || isTrialActive),
                  showPremiumBanner: !(isPremiumUser || isTrialActive),
                ),
              
              if (_savedSessions.isNotEmpty)
                const SizedBox(height: 24),

              // Daily Generation Usage (Premium/Trial only)
              if (isPremiumUser || isTrialActive) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _dailyGenerationSessionsUsed >= _maxDailyGenerationSessions * 0.8
                          ? Colors.orange.withOpacity(0.4)
                          : Colors.white.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: _dailyGenerationSessionsUsed >= _maxDailyGenerationSessions * 0.8
                            ? Colors.orange
                            : PnleTheme.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Generations Today',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_dailyGenerationSessionsUsed/$_maxDailyGenerationSessions sessions • $_dailyGenerationQuestionsUsed/$_maxDailyGenerationQuestions questions',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_dailyGenerationSessionsUsed >= _maxDailyGenerationSessions * 0.8)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            _dailyGenerationSessionsUsed >= _maxDailyGenerationSessions
                                ? 'LIMIT'
                                : 'NEAR LIMIT',
                            style: GoogleFonts.outfit(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 24),

              // Recent Activity (if any quizzes taken) - moved after quiz modes
              if (totalQuizzesTaken > 0) ...[
                Text(
                  'RECENT ACTIVITY',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _activityRow(Icons.quiz_rounded, 'Total Quizzes',
                          '$totalQuizzesTaken completed'),
                      const Divider(height: 16, color: Colors.white24),
                      _activityRow(Icons.grade_rounded, 'Current Score',
                          '${totalAvg.toStringAsFixed(1)}%'),
                      if (_savedSessions.isNotEmpty) ...[
                        const Divider(height: 16, color: Colors.white24),
                        _activityRow(Icons.save_rounded, 'Saved Tests',
                            '${_savedSessions.length} available'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: PnleTheme.accent, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _activityRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: PnleTheme.accent, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _quizModeCard({
    required IconData icon,
    required String title,
    required String description,
    required Gradient gradient,
    VoidCallback? onTap,
    bool isPrimary = false,
    String? badge,
    bool isLocked = false,
    bool showPremiumBanner = false,
  }) {
    return InkWell(
      onTap: isLocked ? null : () {
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isLocked
              ? LinearGradient(
                  colors: [
                    Colors.grey.withOpacity(0.3),
                    Colors.grey.withOpacity(0.2),
                  ],
                )
              : gradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLocked
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.3),
            width: isPrimary ? 2 : 1,
          ),
          boxShadow: isPrimary && !isLocked
              ? [
                  BoxShadow(
                    color: PnleTheme.accent.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLocked
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isLocked ? Icons.lock_rounded : icon,
                color: isLocked ? Colors.white54 : (isPrimary ? PnleTheme.bgBottom : Colors.white),
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            color: isPrimary ? PnleTheme.bgBottom : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (badge != null && !showPremiumBanner)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLocked ? 'Complete more quizzes to unlock' : description,
                    style: GoogleFonts.outfit(
                      color: isPrimary ? PnleTheme.bgBottom.withOpacity(0.85) : Colors.white.withOpacity(0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLocked)
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isPrimary ? PnleTheme.bgBottom : Colors.white,
                size: 18,
              ),
          ],
        ),
          ),
          // Premium corner ribbon
          if (showPremiumBanner)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFFC700),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: PnleTheme.bgBottom,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'PREMIUM',
                      style: GoogleFonts.outfit(
                        color: PnleTheme.bgBottom,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                        letterSpacing: 0.5,
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

  LinearGradient _modeFadeGradient({double strength = 1.0}) {
    return _modeFadeGradientWithColors(
      PnleTheme.accent,
      PnleTheme.accentDeep,
      strength: strength,
    );
  }

  LinearGradient _modeFadeGradientWithColors(
    Color from,
    Color to, {
    double strength = 1.0,
  }) {
    final s = strength.clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        from.withOpacity(0.85 * s),
        to.withOpacity(0.78 * s),
        Colors.white.withOpacity(0.18 * s),
      ],
    );
  }

  Widget _buildBottomNav() {
    final navItems = [
      {'label': 'Home', 'icon': Icons.home_outlined},
      {'label': 'Daily', 'icon': Icons.today_outlined},
      {'label': 'Quiz', 'icon': Icons.quiz_rounded},
      {'label': '10-Days', 'icon': Icons.trending_up_outlined},
      {'label': 'Settings', 'icon': Icons.settings_outlined},
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PnleTheme.bgTop.withOpacity(0.96),
            PnleTheme.bgBottom.withOpacity(0.92),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: PnleTheme.accent.withOpacity(0.35),
            width: 1,
          ),
        ),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: PnleTheme.accent,
        unselectedItemColor: Colors.white.withOpacity(0.85),
        currentIndex: currentScreen,
        type: BottomNavigationBarType.fixed,
        items: List.generate(
          navItems.length,
          (index) {
            final isSelected = currentScreen == index;
            return BottomNavigationBarItem(
              icon: isSelected
                  ? Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: _modeFadeGradient(),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: PnleTheme.accent.withOpacity(0.45),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        navItems[index]['icon'] as IconData,
                        size: 24,
                        color: PnleTheme.bgBottom,
                      ),
                    )
                  : Icon(navItems[index]['icon'] as IconData),
              label: navItems[index]['label'] as String,
            );
          },
        ),
        onTap: _onBottomNavTap,
      ),
    );
  }

  void _onBottomNavTap(int index) async {
    setState(() {
      currentScreen = index;
    });

    if (index == 2) {
      unawaited(_primeFreeDeepSeekCaches());
    }
  }

  Widget _dailyPerformanceScreen() {
    final categories = _categoriesForEligibility();
    final totalAvg = _calculateTotalAverage();
    final hasData = categoryScores.values.any((data) => (data['total'] as int) > 0);

    // Calculate category performance groups
    final excellent = <String>[];
    final good = <String>[];
    final needsWork = <String>[];

    for (final cat in categories) {
      final data = categoryScores[cat]!;
      final correct = data['correct'] as int;
      final total = data['total'] as int;
      
      if (total > 0) {
        final percentage = (correct / total) * 100;
        if (percentage >= 80) {
          excellent.add(cat);
        } else if (percentage >= 60) {
          good.add(cat);
        } else {
          needsWork.add(cat);
        }
      }
    }

    final weakestCategory = _getWeakestCategory();

    return Stack(
      children: [
        _glassContainer(
          borderRadius: 26,
          padding: const EdgeInsets.all(16),
          child: ListView(
            key: const PageStorageKey('daily_performance_screen'),
            controller: _dailyScrollController,
            children: [
              // Header Section
              const SizedBox(height: 8),
              Text(
                'Daily Progress',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDate(DateTime.now()),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),

              // DAILY OBJECTIVES SECTION
              Text(
                'TODAY\'S OBJECTIVES',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              _objectiveCard(
                text: 'Complete 4 new sessions today.',
                progress: completedSessions / 4,
                trailing: '$completedSessions/4',
              ),
              const SizedBox(height: 12),
              _objectiveCard(
                text: 'Maintain overall average of at least 65%.',
                progress: _calculateTotalAverage() / 100,
                trailing: _getTotalAverageText(),
                trailingColor: _getTotalAverageColor(),
              ),
              const SizedBox(height: 28),
              
              // Sessions completed today
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PnleTheme.accent.withOpacity(0.3),
                      PnleTheme.accent.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PnleTheme.accent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.today_rounded, color: PnleTheme.accent, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Sessions Today',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$completedSessions/4',
                      style: GoogleFonts.outfit(
                        color: PnleTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              
              // OLD: Sessions completed today - REMOVED IN FAVOR OF OBJECTIVES ABOVE
              
              const SizedBox(height: 24),

              // Empty State
              if (!hasData) ...[
                const SizedBox(height: 40),
                Icon(
                  Icons.insert_chart_outlined_rounded,
                  size: 80,
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No data yet',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start your first quiz today to\ntrack your progress!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => currentScreen = 2),
                    icon: const Icon(Icons.quiz_rounded),
                    label: const Text('Start Quiz'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PnleTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],

              // Performance Insights Card
              if (hasData) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF34D399).withOpacity(0.2),
                        const Color(0xFF34D399).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF34D399).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insights, color: Color(0xFF34D399), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Performance Insights',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF34D399),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (weakestCategory.isNotEmpty)
                        _insightRow(Icons.trending_down_rounded, 'Focus on',
                            weakestCategory, const Color(0xFFFF6B6B)),
                      _insightRow(
                        Icons.local_fire_department_rounded,
                        'Current Streak',
                        '$currentStreak ${currentStreak == 1 ? 'day' : 'days'}',
                        Colors.orange,
                      ),
                      _insightRow(
                        Icons.score_rounded,
                        'Overall Score',
                        '${totalAvg.toStringAsFixed(1)}%',
                        totalAvg >= 80
                            ? const Color(0xFF34D399)
                            : totalAvg >= 60
                                ? Colors.amber
                                : const Color(0xFFFF6B6B),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Visual Categorization by Performance Level
                if (excellent.isNotEmpty) ...[
                  _performanceGroupHeader('Excellent Performance', const Color(0xFF34D399), Icons.emoji_events_rounded),
                  const SizedBox(height: 8),
                  ...excellent.map((cat) => _categoryProgressEnhanced(cat)),
                  const SizedBox(height: 16),
                ],
                if (good.isNotEmpty) ...[
                  _performanceGroupHeader('Good Progress', Colors.amber, Icons.thumb_up_rounded),
                  const SizedBox(height: 8),
                  ...good.map((cat) => _categoryProgressEnhanced(cat)),
                  const SizedBox(height: 16),
                ],
                if (needsWork.isNotEmpty) ...[
                  _performanceGroupHeader('Needs Improvement', const Color(0xFFFF6B6B), Icons.trending_up_rounded),
                  const SizedBox(height: 8),
                  ...needsWork.map((cat) => _categoryProgressEnhanced(cat)),
                  const SizedBox(height: 16),
                ],

                // Quick Actions
                const SizedBox(height: 8),
                Text(
                  'QUICK ACTIONS',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _quickActionButton(
                        icon: Icons.refresh_rounded,
                        label: 'Retake\nWeak Areas',
                        onTap: () {
                          setState(() => currentScreen = 2);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Focus on: $weakestCategory'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _quickActionButton(
                        icon: Icons.history_rounded,
                        label: 'View\nHistory',
                        onTap: () => setState(() => currentScreen = 3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _insightRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _performanceGroupHeader(String title, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _categoryProgressEnhanced(String category) {
    final data = categoryScores[category]!;
    final correct = data['correct'] as int;
    final total = data['total'] as int;
    final percentage = total > 0 ? (correct / total * 100) : 0.0;
    final progress = total > 0 ? correct / total : 0.0;
    
    final barColor = Color.lerp(
      const Color(0xFFFF6B6B),
      const Color(0xFF34D399),
      progress.clamp(0.0, 1.0),
    );

    // Simulate trend (compare with previous data — need real history)
    // When data is minimal, show neutral icon instead of misleading down arrow
    final trendUp = percentage >= 50;
    final hasEnoughData = total >= 5; // Need at least 5 answers for meaningful trend

    return _glassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 74, maxWidth: 96),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasEnoughData
                          ? (trendUp ? Icons.trending_up : Icons.trending_down)
                          : Icons.horizontal_rule_rounded,
                      color: hasEnoughData
                          ? (trendUp ? const Color(0xFF34D399) : const Color(0xFFFF6B6B))
                          : Colors.white38,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: (barColor ?? Colors.grey).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${percentage.toStringAsFixed(0)}%',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.15),
              color: barColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$correct/$total correct answers',
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.2),
              Colors.white.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: PnleTheme.accent, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyScreen() {
    if (isPremiumUser || isTrialActive) {
      return _premiumHistoryScreen();
    }

    // Free user view - Beautiful preview with features
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _historyScrollController,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Header
                Text(
                  '10-Day Performance Tracker',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'See how you perform over 10 consecutive days with detailed insights',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // Feature 1: Real-time tracking
                _build10DayFeatureCard(
                  icon: Icons.trending_up_rounded,
                  title: 'Real-Time Progress Tracking',
                  description: 'Watch your performance improve day by day',
                  gradient: _modeFadeGradientWithColors(
                    Colors.green,
                    Colors.teal,
                    strength: 0.72,
                  ),
                ),
                const SizedBox(height: 12),

                // Feature 2: Visual charts
                _build10DayFeatureCard(
                  icon: Icons.bar_chart_rounded,
                  title: 'Beautiful Performance Charts',
                  description: 'See your strengths & weaknesses at a glance',
                  gradient: _modeFadeGradientWithColors(
                    Colors.blue,
                    Colors.cyan,
                    strength: 0.7,
                  ),
                ),
                const SizedBox(height: 12),

                // Feature 3: Weakness identification
                _build10DayFeatureCard(
                  icon: Icons.center_focus_strong,
                  title: 'Weakness Identification',
                  description: 'Pinpoint areas to improve based on 10-day data',
                  gradient: _modeFadeGradientWithColors(
                    Colors.orange,
                    Colors.amber,
                    strength: 0.74,
                  ),
                ),
                const SizedBox(height: 12),

                // Feature 4: Performance trends
                _build10DayFeatureCard(
                  icon: Icons.insights_rounded,
                  title: 'Actionable Insights',
                  description: 'Get smart recommendations based on your trends',
                  gradient: _modeFadeGradientWithColors(
                    Colors.purple,
                    Colors.indigo,
                    strength: 0.76,
                  ),
                ),
                const SizedBox(height: 28),

                // Preview section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📊 You\'ll Also Get:',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '✨ Daily average scores for each category',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '✨ 10-day trend lines showing improvement',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '✨ Category-wise performance breakdown',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '✨ Smart recommendations for weak areas',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // CTA Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _showPremiumOfferDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PnleTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 8,
                      shadowColor: PnleTheme.accent.withOpacity(0.4),
                    ),
                    child: Text(
                      'Subscribe to Unlock',
                      style: GoogleFonts.outfit(
                        color: PnleTheme.bgBottom,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Secondary text
                Center(
                  child: Text(
                    'No credit card required for 3-day trial',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  List<Map<String, dynamic>> _buildTenDayActivity() {
    final now = DateTime.now();
    final activity = <DateTime, Map<String, int>>{};

    for (int i = 9; i >= 0; i--) {
      final day = _dateOnly(now.subtract(Duration(days: i)));
      activity[day] = {'quizzes': 0, 'questions': 0, 'correct': 0};
    }

    for (final record in _quizActivityRecords) {
      final day = _dateOnly(record.date);
      if (!activity.containsKey(day)) continue;
      activity[day]!['quizzes'] = (activity[day]!['quizzes'] ?? 0) + 1;
      activity[day]!['questions'] =
          (activity[day]!['questions'] ?? 0) + record.questionCount;
      // Calculate actual correct answers from session data
      int sessionCorrect = 0;
      // TODO: Track answer results in _SavedSession model
      // For now, use questions count as approximation
      sessionCorrect = 0;
      activity[day]!['correct'] =
          (activity[day]!['correct'] ?? 0) + sessionCorrect;
    }

    final entries = activity.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries
        .map(
          (entry) => {
            'date': entry.key,
            'quizzes': entry.value['quizzes'] ?? 0,
            'questions': entry.value['questions'] ?? 0,
            'correct': entry.value['correct'] ?? 0,
          },
        )
        .toList();
  }

  double _calculateDayOverallAverage(DateTime day) {
    // Return the user's overall average across all tests
    // This gives a meaningful percentage even for days with partial completion
    return _calculateTotalAverage();
  }

  Widget _premiumHistoryScreen() {
    final tenDayActivity = _buildTenDayActivity();
    final activeDays =
        tenDayActivity.where((day) => (day['quizzes'] as int) > 0).length;
    final totalQuizzes = tenDayActivity.fold<int>(
      0,
      (sum, day) => sum + (day['quizzes'] as int),
    );
    final totalQuestions = tenDayActivity.fold<int>(
      0,
      (sum, day) => sum + (day['questions'] as int),
    );
    final maxQuizzes = tenDayActivity.fold<int>(
      1,
      (max, day) => (day['quizzes'] as int) > max ? (day['quizzes'] as int) : max,
    );

    return Stack(
      children: [
        SingleChildScrollView(
          key: const PageStorageKey('history_screen_premium'),
          controller: _historyScrollController,
          child: Column(
            children: [
              _glassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      '10-Days Performance Record',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your real activity over the last 10 days',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _glassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _build10DayStatItem('$activeDays', 'Active Days', Icons.event_available_rounded),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    _build10DayStatItem('$totalQuizzes', 'Quizzes', Icons.quiz_outlined),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    _build10DayStatItem('$totalQuestions', 'Questions', Icons.fact_check_outlined),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Progress Insights
              _glassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Progress Analysis',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildProgressInsights(tenDayActivity),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _glassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bar_chart_rounded,
                          color: PnleTheme.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Daily Quiz Activity',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 150,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: tenDayActivity.map((day) {
                          final quizzes = day['quizzes'] as int;
                          final date = day['date'] as DateTime;
                          final percentage =
                              ((quizzes / maxQuizzes) * 100).clamp(0.0, 100.0);
                          return _buildChartBar(
                            percentage,
                            '${date.day}',
                            true,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _glassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last 10 Days Records',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...tenDayActivity.reversed.map((day) {
                      final date = day['date'] as DateTime;
                      final quizzes = day['quizzes'] as int;
                      // final questions = day['questions'] as int; // Number of quizzes in this day
                      final hasActivity = quizzes > 0;
                      final isComplete = quizzes >= 4;  // Must complete 4 tests
                      
                      // Calculate percentage and status
                      String statusText;
                      Color statusColor;
                      if (!hasActivity) {
                        statusText = 'No activity';
                        statusColor = Colors.white.withOpacity(0.4);
                      } else if (!isComplete) {
                        // Show current overall average if not finished
                        final dayOverallAvg = _calculateDayOverallAverage(date);
                        statusText = '${dayOverallAvg.toStringAsFixed(0)}% - UNFINISHED';
                        statusColor = const Color(0xFFFFA726);
                      } else {
                        // Show pass/fail only when 4 tests are complete
                        final dayOverallAvg = _calculateDayOverallAverage(date);
                        if (dayOverallAvg >= 80) {
                          statusText = '${dayOverallAvg.toStringAsFixed(0)}% - Passed ✓';
                          statusColor = const Color(0xFF34D399);
                        } else {
                          statusText = '${dayOverallAvg.toStringAsFixed(0)}% - Failed';
                          statusColor = const Color(0xFFFF6B6B);
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasActivity
                                ? statusColor.withOpacity(0.45)
                                : Colors.white.withOpacity(0.14),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatDate(date),
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              statusText,
                              style: GoogleFonts.outfit(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  // Helper method to build feature items
  // Helper method to build chart bars
  Widget _buildChartBar(double percentage, String label, bool unlocked) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            height: (percentage / 100) * 100,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: unlocked
                    ? [
                        const Color(0xFF34D399),
                        const Color(0xFF2196F3),
                      ]
                    : [
                        Colors.grey.withOpacity(0.3),
                        Colors.grey.withOpacity(0.2),
                      ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: unlocked 
                  ? Colors.white.withOpacity(0.7)
                  : Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build stat items for 10-Day Performance section
  Widget _build10DayStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: PnleTheme.accent.withOpacity(0.8),
          size: 16,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressInsights(List<Map<String, dynamic>> tenDayActivity) {
    // Check if there's any test data at all
    final totalQuizzesAll = tenDayActivity.fold<int>(0, (sum, day) => sum + (day['quizzes'] as int));
    
    // If no test data, show a placeholder message
    if (totalQuizzesAll == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.trending_up_rounded,
              color: Colors.white.withOpacity(0.5),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'No progress data yet',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Complete your first quiz to see your progress analysis',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    // Divide into first 5 days and last 5 days
    final firstHalf = tenDayActivity.take(5).toList();
    final secondHalf = tenDayActivity.skip(5).toList();
    
    final firstHalfQuizzes = firstHalf.fold<int>(0, (sum, day) => sum + (day['quizzes'] as int));
    final secondHalfQuizzes = secondHalf.fold<int>(0, (sum, day) => sum + (day['quizzes'] as int));
    
    final firstHalfActiveDays = firstHalf.where((day) => (day['quizzes'] as int) > 0).length;
    final secondHalfActiveDays = secondHalf.where((day) => (day['quizzes'] as int) > 0).length;
    
    // Calculate percentage change
    final quizzesChange = firstHalfQuizzes > 0 
        ? ((secondHalfQuizzes - firstHalfQuizzes) / firstHalfQuizzes * 100).toStringAsFixed(1)
        : '0.0';
    
    final isImproving = secondHalfQuizzes >= firstHalfQuizzes;
    final trendIcon = isImproving ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final trendColor = isImproving ? const Color(0xFF34D399) : const Color(0xFFFF6B6B);

    return Column(
      children: [
        // First vs Second Half Comparison
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'First 5 Days',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '$firstHalfQuizzes',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'quizzes',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$firstHalfActiveDays active days',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: trendColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last 5 Days',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: trendColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '$secondHalfQuizzes',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: trendColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'quizzes',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: trendColor.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$secondHalfActiveDays active days',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: trendColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Improvement Metric
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: trendColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: trendColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                trendIcon,
                color: trendColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isImproving ? '📈 You\'re improving!' : '📉 Slight decrease',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: trendColor,
                      ),
                    ),
                    Text(
                      '$quizzesChange% change from first to last 5 days',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: trendColor.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPremiumOfferDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => SubscriptionDialog(
        triggerSource: 'trial_offer',
        onStartTrial: () async {
          // Close the subscription dialog first
          Navigator.pop(context);
          // Then start the trial flow
          await _startTrialFlow();
        },
        onRestorePurchases: () async {
          Navigator.pop(context);
          await _restorePurchasesManually();
        },
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  Widget _build10DayFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Gradient gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.75),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startTrialFlow({VoidCallback? onPremiumActivated}) async {
    if (_premiumTestMode) {
      await _activatePremiumAccess();
      onPremiumActivated?.call();
      return;
    }

    await _startSubscriptionPurchase(onSuccess: onPremiumActivated);
  }

  Widget _objectiveCard({
    required String text,
    required double progress,
    required String trailing,
    Color? trailingColor,
  }) {
    final barColor = Color.lerp(
      const Color(0xFFFF6B6B),
      const Color(0xFF34D399),
      progress.clamp(0.0, 1.0),
    );
    final percentage = (progress * 100).toStringAsFixed(0);

    return _glassContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      (barColor ?? Colors.grey).withOpacity(0.8),
                      (barColor ?? Colors.grey).withOpacity(0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$percentage%',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(barColor ?? Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              trailing,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: trailingColor ?? Colors.white.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTotalAverage() {
    double totalWeightedScore = 0.0;

    for (final cat in _categoriesForEligibility()) {
      final data = categoryScores[cat];
      if (data == null) continue;

      final correct = data['correct'] as int;
      final total = data['total'] as int;
      final weight = (data['weight'] as num?)?.toDouble() ?? 0.20;

      if (total > 0) {
        final percentage = correct / total;
        totalWeightedScore += percentage * weight;
      }
    }

    return totalWeightedScore * 100;
  }

  bool _allCategoriesAtLeast(double minimumPercent) {
    for (final cat in _categoriesForEligibility()) {
      final data = categoryScores[cat];
      if (data == null) return false;
      final total = data['total'] as int;
      if (total <= 0) return false;
      final correct = data['correct'] as int;
      final percent = (correct / total) * 100;
      if (percent < minimumPercent) return false;
    }
    return true;
  }

  String _getTotalAverageText() {
    // Calculate cumulative raw count across all sessions
    int totalCorrect = 0;
    int totalQuestions = 0;
    
    final categories = _categoriesForEligibility();
    for (final cat in categories) {
      final data = categoryScores[cat];
      if (data == null) continue;
      totalCorrect += data['correct'] as int;
      totalQuestions += data['total'] as int;
    }
    
    // Get weighted overall average across UPCAT categories.
    final weightedAvg = _calculateTotalAverage();
    
    // Show cumulative format with session indicator
    final cumulativeText = totalQuestions > 0 
      ? '$totalCorrect/$totalQuestions · Session $completedSessions/4'
      : '0/0 · Session 0/4';
    
    if (completedSessions < 4) {
      return '$cumulativeText\n${weightedAvg.toStringAsFixed(1)}% (Weighted) - Incomplete';
    } else if (weightedAvg >= 65) {
      return '$cumulativeText\n${weightedAvg.toStringAsFixed(1)}% (Weighted) - PASSED';
    } else {
      return '$cumulativeText\n${weightedAvg.toStringAsFixed(1)}% (Weighted) - FAILED';
    }
  }

  Color _getTotalAverageColor() {
    final avg = _calculateTotalAverage();
    
    if (completedSessions < 4) {
      return Colors.amber;
    } else if (avg >= 65) {
      return Colors.green;
    } else {
      return PnleTheme.danger.withOpacity(0.82);
    }
  }

  Widget _glassContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 16,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: PnleTheme.glassFill,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: PnleTheme.glassBorder,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

// TODO: Re-enable when Firestore daily limit check is working
/*
void _showLimitReachedDialog() {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Daily Limit Reached'),
      content: const Text(
        'Free users can only create 4 sessions per day.\n'
        'Upgrade to Premium for unlimited access.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
*/

  void _showTestCoverageDialog(
    Map<String, String> coverage, {
    bool isFocusMode = false,
    String? focusCategory,
  }) {
    // Store the test coverage for use in prompt generation
    _currentTestCoverage = coverage;
    
    // Store focus mode parameters
    _isFocusMode = isFocusMode;
    _focusCategory = focusCategory;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PnleTheme.bgTop.withOpacity(0.95),
                      PnleTheme.bgBottom.withOpacity(0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isFocusMode
                        ? const Color(0xFFFF6B6B).withOpacity(0.6)
                        : PnleTheme.accent.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isFocusMode
                          ? const Color(0xFFFF6B6B).withOpacity(0.3)
                          : PnleTheme.accent.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isFocusMode ? 'FOCUS MODE' : 'RANDOM QUIZ',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isFocusMode ? focusCategory ?? '' : 'Test Coverage',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: isFocusMode
                              ? const Color(0xFFFF6B6B)
                              : PnleTheme.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      if (isFocusMode) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF6B6B).withOpacity(0.3),
                                const Color(0xFFFF6B6B).withOpacity(0.15),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFFF6B6B).withOpacity(0.6),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6B6B).withOpacity(0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6B6B).withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.gps_fixed,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '10 questions from $focusCategory + 5 mixed questions',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ...coverage.entries.map((e) => _coverageItem(e.key, e.value, isFocusMode: isFocusMode, focusCategory: focusCategory)),
                      const SizedBox(height: 24),
                      // CREATE TEST BUTTON
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [PnleTheme.accent, PnleTheme.accentDeep],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: PnleTheme.accent.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!isPremiumUser && !isTrialActive && remainingFreeTests <= 0) {
                              // Show subscription dialog
                              if (mounted) {
                                Navigator.pop(context);
                                showDialog(
                                  context: context,
                                  barrierColor: Colors.black87,
                                  builder: (_) => SubscriptionDialog(
                                    triggerSource: 'daily_limit',
                                    onStartTrial: () async {
                                      // Close the subscription dialog first
                                      Navigator.pop(context);
                                      // Then start the trial flow
                                      await _startTrialFlow();
                                    },
                                    onRestorePurchases: () async {
                                      Navigator.pop(context);
                                      await _restorePurchasesManually();
                                    },
                                    onClose: () => Navigator.pop(context),
                                  ),
                                );
                              }
                              return;
                            }

                            // Close coverage dialog and start generation
                            if (mounted) {
                              Navigator.pop(context);
                              
                              _showGenerationDialog(
                                modeLabel: isFocusMode
                                    ? 'FOCUS MODE${focusCategory != null ? ' • $focusCategory' : ''}'
                                    : 'RANDOM QUIZ',
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ADS icon (only for free users)
                              if (!isPremiumUser) ...[
                                Image.asset(
                                  'assets/images/ads.png',
                                  height: 24,
                                  width: 24,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Text(
                                'CREATE TEST',
                                style: GoogleFonts.outfit(
                                  color: PnleTheme.bgBottom,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: PnleTheme.bgBottom,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Remaining free tests counter (only for free users)
                      if (!isPremiumUser)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.bolt_rounded,
                                color: PnleTheme.accent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isPremiumUser || isTrialActive 
                                  ? 'Tests remaining today: Unlimited' 
                                  : 'Tests remaining today: $remainingFreeTests',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      // CLOSE button
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    if (category.contains('Verbal')) return Icons.chat_bubble_rounded;
    if (category.contains('Numerical')) return Icons.calculate_rounded;
    if (category.contains('General')) return Icons.public_rounded;
    if (category.contains('Analytical')) return Icons.psychology_rounded;
    if (category.contains('Clerical')) return Icons.description_rounded;
    return Icons.lightbulb_rounded;
  }

  Widget _coverageItem(String category, String topic, {bool isFocusMode = false, String? focusCategory}) {
    final isFocusCategory = isFocusMode && category == focusCategory;
    final accentColor = isFocusMode
        ? const Color(0xFFFF6B6B)
        : PnleTheme.accent;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isFocusCategory
            ? LinearGradient(
                colors: [
                  const Color(0xFFFF6B6B).withOpacity(0.25),
                  const Color(0xFFFF6B6B).withOpacity(0.15),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.08),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocusCategory
              ? const Color(0xFFFF6B6B).withOpacity(0.6)
              : Colors.white.withOpacity(0.25),
          width: isFocusCategory ? 2 : 1,
        ),
        boxShadow: isFocusCategory
            ? [
                BoxShadow(
                  color: const Color(0xFFFF6B6B).withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withOpacity(0.4),
              ),
            ),
            child: Icon(
              _getCategoryIcon(category),
              color: accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (isFocusCategory)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '10Q',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: accentColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        topic,
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildPrompt() {
    if (_currentTestCoverage == null) {
      throw Exception('Test coverage not generated');
    }

    final language =
        _currentTestCoverage!['Language Proficiency'] ?? 'General language proficiency topics';
    final reading =
        _currentTestCoverage!['Reading Comprehension'] ?? 'General reading comprehension topics';
    final mathematics = _currentTestCoverage!['Mathematics'] ?? 'General mathematics topics';
    final science = _currentTestCoverage!['Science'] ?? 'General science topics';

    return '''Create 15 unique, reasoning-based multiple-choice questions in JSON format for a UPCAT Reviewer Quiz App.

Each question must include:
- "number": Question number (1 to 15)
- "question": The full question text
- "choices": A list of exactly 4 answer choices
- "answer": The correct answer letter ("A", "B", "C", or "D")

Structure the JSON exactly like this:
{
  "questions": [
    {
      "number": 1,
      "question": "Question text here",
      "choices": ["Choice A", "Choice B", "Choice C", "Choice D"],
      "answer": "A"
    }
  ]
}

Constraints:
- Questions 1-2: Language Proficiency - $language
- Questions 3-7: Reading Comprehension - $reading
- Questions 8-11: Mathematics - $mathematics
- Questions 12-15: Science - $science
- Do not ask direct definition or pure recall questions.
- Every item must require reasoning, interpretation, comparison, or application.
- Use UPCAT-style wording and difficulty (academic, concise, non-trivial).
- Ensure one choice is correct and the answer logically follows from the question.
- Include plausible distractors based on common student mistakes.
- Keep each question clear and concise.
- Make all answer choices balanced in length and tone.
- Do not make the correct choice the longest option by wording length.
- Do not make the correct choice the shortest option either.
- All answer choices should be short noun phrases or short clauses of similar length.
- At least one incorrect choice must be as long as or longer than the correct answer.
- Language Proficiency questions must use sentence-based or word-relationship reasoning.
- Reading Comprehension questions must include a full passage in the same question text.
- For Reading Comprehension, never reference another item/passage using words like previous, above, below, earlier, or as mentioned.
- Reading passages should be 60-120 words in formal academic English.
- Mathematics questions must focus on evaluating/simplifying expressions or quantitative reasoning.
- Science questions must focus on systems, interactions, mechanisms, or cause-effect reasoning.
- Use only Unicode math symbols where needed (e.g., 1/2, 1/3, √, x²).
- Do not use LaTeX or backslashes.
- Randomize correct-answer letters across A/B/C/D; avoid obvious patterns or repeated streaks.
- Do not reveal the correct answer by wording patterns.
- No asterisks, bold, or special formatting.
- All text must be plain and readable.

Output rules:
- Return only a raw JSON object.
- Do not use triple backticks.
- Do not add explanations outside JSON.''';
  }

  String _buildFastPrompt() {
    if (_currentTestCoverage == null) {
      throw Exception('Test coverage not generated');
    }

    final language =
        _currentTestCoverage!['Language Proficiency'] ?? 'General language proficiency topics';
    final reading =
        _currentTestCoverage!['Reading Comprehension'] ?? 'General reading comprehension topics';
    final mathematics = _currentTestCoverage!['Mathematics'] ?? 'General mathematics topics';
    final science = _currentTestCoverage!['Science'] ?? 'General science topics';

    return '''Generate 15 reasoning-based UPCAT multiple-choice questions as raw JSON only.
Format:
{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}
Distribution:
- Q1-2 Language Proficiency: $language
- Q3-7 Reading Comprehension: $reading
- Q8-11 Mathematics: $mathematics
- Q12-15 Science: $science
Rules:
- Exactly 4 choices per question
- Correct answer must be one of A/B/C/D
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"
- No direct recall/definition items; require interpretation or application
- Language: sentence/relationship reasoning
- Reading: embed full 60-120 word passage per item; no cross-reference words (previous/above/below/earlier/as mentioned)
- Math: expression evaluation/simplification or quantitative reasoning
- Science: system interaction and mechanism reasoning
- Choices must be short phrases/short clauses with balanced length/tone
- At least one wrong choice must be as long as or longer than the correct choice
- Use Unicode math symbols only; no LaTeX or backslashes
- Make distractors plausible based on common student misconceptions
- Avoid giveaway wording patterns
- Do not make correct answer obviously longest/shortest
- Randomize answer letters across A/B/C/D without obvious streaks
- No markdown, no asterisks, no extra text
- Return JSON only, no markdown.''';
  }

  String _buildFocusPrompt(String focusCategory) {
    if (_currentTestCoverage == null) {
      throw Exception('Test coverage not generated');
    }

    // Get topic for the focus category
    final focusTopic = _currentTestCoverage![focusCategory] ?? 'General topics';
    
    // Get other topics for variety (1 question each)
    final categories = _categoriesForEligibility();
    final otherCategories = categories.where((cat) => cat != focusCategory).toList();
    
    // Focus mode creates 10 questions from the focus category, 5 from others
    String distribution = '';
    int questionNumber = 1;
    
    // 10 questions from focus category
    distribution += '- Questions $questionNumber–${questionNumber + 9}: $focusCategory - $focusTopic.\n';
    questionNumber += 10;
    
    // 5 questions from other categories
    for (int i = 0; i < otherCategories.length && questionNumber <= 15; i++) {
      final cat = otherCategories[i];
      final topic = _currentTestCoverage![cat] ?? 'General topics';
      final questionsInCat = (15 - questionNumber + 1) ~/ (otherCategories.length - i);
      final endQuestion = questionNumber + questionsInCat - 1;
      
      if (questionsInCat == 1) {
        distribution += '- Question $questionNumber: $cat - $topic.\n';
      } else {
        distribution += '- Questions $questionNumber–$endQuestion: $cat - $topic.\n';
      }
      questionNumber += questionsInCat;
    }

    return '''Create 15 unique, practical multiple-choice questions in JSON format for a UPCAT AI Reviewer app.

Each question must include:
- "number": Question number (1 to 15)
- "question": The full question text
- "choices": A list of exactly 4 answer choices
- "answer": The correct answer letter ("A", "B", "C", or "D")

Structure the JSON exactly like this:
{
  "questions": [
    {
      "number": 1,
      "question": "Question text here",
      "choices": ["Choice A", "Choice B", "Choice C", "Choice D"],
      "answer": "A"
    }
  ]
}

Constraints:
- FOCUS MODE distribution (10 focus + 5 mixed):
$distribution
- Ensure one choice is correct and the answer logically follows from the question.
- Use practical, application-based UPCAT scenarios.
- Keep all questions clear and concise.
- Make all answer choices balanced in length and tone.
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above".
- Do not make the correct choice the longest option by wording length.
- Do not make the correct choice the shortest option either.
- Keep all 4 choices within a similar length range (target 8-14 words each when feasible).
- Randomize correct-answer letters across A/B/C/D; avoid obvious patterns or repeated streaks.
- Do not reveal the correct answer by wording patterns.
- No asterisks, bold, or special formatting.
- All text must be plain and readable.

Output rules:
- Return only a raw JSON object.
- Do not use triple backticks.
- Do not add explanations outside JSON.''';
  }

  String _buildFastFocusPrompt(String focusCategory) {
    final focusTopic = _currentTestCoverage?[focusCategory] ??
        (keyAreas[focusCategory]?.isNotEmpty ?? false
            ? keyAreas[focusCategory]![Random().nextInt(keyAreas[focusCategory]!.length)]
            : 'General topics');

    final categories = _categoriesForEligibility();
    final otherCategories = categories.where((cat) => cat != focusCategory).toList();
    final otherText = otherCategories
        .map((cat) {
          final topic = _currentTestCoverage?[cat] ??
              (keyAreas[cat]?.isNotEmpty ?? false
                  ? keyAreas[cat]![Random().nextInt(keyAreas[cat]!.length)]
                  : 'General topics');
          return '$cat: $topic';
        })
        .join(' | ');

    return '''Generate 15 UPCAT reasoning multiple-choice questions as raw JSON only.
Format:
{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}
Distribution:
- Q1-10 focus category: $focusCategory ($focusTopic)
- Q11-15 mixed from: $otherText
Rules:
- Exactly 4 choices per question
- Correct answer must be one of A/B/C/D
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"
  - Use practical UPCAT-style scenarios with interpretation and application
  - Keep wording concise and academically accurate
  - Keep choices similar in length and tone (target 8-14 words when feasible)
- Make distractors plausible based on common student misconceptions
- Avoid giveaway wording like "always", "never", or obvious textbook clues
- Vary stem style (analysis, inference, best answer, problem-solving)
  - Do not make correct answer obviously longest/shortest by wording
  - Randomize answer letters across A/B/C/D without obvious streaks
  - No markdown, no asterisks, no extra text
- Return JSON only, no markdown.''';
  }

  String _buildQuickPracticePrompt(String focusCategory) {
    final focusTopic = keyAreas[focusCategory]?.isNotEmpty ?? false
        ? keyAreas[focusCategory]![Random().nextInt(keyAreas[focusCategory]!.length)]
        : 'General topics';

    return '''Create 5 unique, practical multiple-choice questions in JSON format for a UPCAT AI Reviewer app.

Each question must include:
- "number": Question number (1 to 5)
- "question": The full question text
- "choices": A list of exactly 4 answer choices
- "answer": The correct answer letter ("A", "B", "C", or "D")

Structure the JSON exactly like this:
{
  "questions": [
    {
      "number": 1,
      "question": "Question text here",
      "choices": ["Choice A", "Choice B", "Choice C", "Choice D"],
      "answer": "A"
    }
  ]
}

Constraints:
- Questions 1-5: Focus on $focusCategory - $focusTopic
- Keep questions short and practical for quick review.
- Ensure one choice is correct and the answer logically follows from the question.
- Make all answer choices balanced in length and tone.
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above".
- Do not make the correct choice the longest option by wording length.
- Do not make the correct choice the shortest option either.
- Keep all 4 choices within a similar length range (target 8-14 words each when feasible).
- Randomize correct-answer letters across A/B/C/D; avoid obvious patterns or repeated streaks.
- Do not reveal the correct answer by wording patterns.
- No asterisks, bold, or special formatting.
- All text must be plain and readable.

Output rules:
- Return only a raw JSON object.
- Do not use triple backticks.
- Do not add explanations outside JSON.''';
  }

  String _buildFastQuickPracticePrompt(String focusCategory) {
    final focusTopic = keyAreas[focusCategory]?.isNotEmpty ?? false
        ? keyAreas[focusCategory]![Random().nextInt(keyAreas[focusCategory]!.length)]
        : 'General topics';

    return '''Generate 5 UPCAT reasoning multiple-choice questions as raw JSON only.
Format:
{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}
Scope:
- Q1-5 focus on $focusCategory ($focusTopic)
Rules:
- Exactly 4 choices per question
- Correct answer must be one of A/B/C/D
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"
  - Keep items short, practical, and reasoning-focused
  - Keep choices similar in length and tone (target 8-14 words when feasible)
- Make distractors plausible based on common student misconceptions
- Avoid giveaway wording like "always", "never", or obvious textbook clues
- Vary stem style (analysis, inference, best answer, problem-solving)
  - Do not make correct answer obviously longest/shortest by wording
  - Randomize answer letters across A/B/C/D without obvious streaks
  - No markdown, no asterisks, no extra text
- Return JSON only, no markdown.''';
  }

  String _buildChallengeModePrompt(String focusCategory) {
    final focusTopic = keyAreas[focusCategory]?.isNotEmpty ?? false
        ? keyAreas[focusCategory]![Random().nextInt(keyAreas[focusCategory]!.length)]
        : 'General topics';
    final categories = _categoriesForEligibility();
    final otherCategories = categories.where((cat) => cat != focusCategory).toList();

    // Build distribution string for questions 7-10 (other categories)
    String otherCategoriesDistribution = '';
    if (otherCategories.length == 1) {
      final cat = otherCategories[0];
      final topic = keyAreas[cat]?.isNotEmpty ?? false
          ? keyAreas[cat]![Random().nextInt(keyAreas[cat]!.length)]
          : 'General topics';
      otherCategoriesDistribution = '- Questions 7–10: $cat - $topic (ADVANCED/DIFFICULT)';
    } else if (otherCategories.length == 2) {
      final cat1 = otherCategories[0];
      final cat2 = otherCategories[1];
      final topic1 = keyAreas[cat1]?.isNotEmpty ?? false
          ? keyAreas[cat1]![Random().nextInt(keyAreas[cat1]!.length)]
          : 'General topics';
      final topic2 = keyAreas[cat2]?.isNotEmpty ?? false
          ? keyAreas[cat2]![Random().nextInt(keyAreas[cat2]!.length)]
          : 'General topics';
      otherCategoriesDistribution = '- Questions 7–8: $cat1 - $topic1 (ADVANCED/DIFFICULT)\n- Questions 9–10: $cat2 - $topic2 (ADVANCED/DIFFICULT)';
    } else if (otherCategories.length == 3) {
      final cat1 = otherCategories[0];
      final cat2 = otherCategories[1];
      final cat3 = otherCategories[2];
      final topic1 = keyAreas[cat1]?.isNotEmpty ?? false
          ? keyAreas[cat1]![Random().nextInt(keyAreas[cat1]!.length)]
          : 'General topics';
      final topic2 = keyAreas[cat2]?.isNotEmpty ?? false
          ? keyAreas[cat2]![Random().nextInt(keyAreas[cat2]!.length)]
          : 'General topics';
      final topic3 = keyAreas[cat3]?.isNotEmpty ?? false
          ? keyAreas[cat3]![Random().nextInt(keyAreas[cat3]!.length)]
          : 'General topics';
      otherCategoriesDistribution = '- Question 7: $cat1 - $topic1 (ADVANCED/DIFFICULT)\n- Question 8: $cat2 - $topic2 (ADVANCED/DIFFICULT)\n- Questions 9–10: $cat3 - $topic3 (ADVANCED/DIFFICULT)';
    }

    return '''Create 10 unique, advanced multiple-choice questions in JSON format for a UPCAT AI Reviewer app.

Each question must include:
- "number": Question number (1 to 10)
- "question": The full question text
- "choices": A list of exactly 4 answer choices
- "answer": The correct answer letter ("A", "B", "C", or "D")

Structure the JSON exactly like this:
{
  "questions": [
    {
      "number": 1,
      "question": "Question text here",
      "choices": ["Choice A", "Choice B", "Choice C", "Choice D"],
      "answer": "A"
    }
  ]
}

Constraints:
- Challenge distribution:
- Questions 1-6: $focusCategory - $focusTopic
$otherCategoriesDistribution
- Use advanced UPCAT-level application and critical-thinking scenarios.
- Ensure one choice is correct and the answer logically follows from the question.
- Make all answer choices balanced in length and tone.
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above".
- Do not make the correct choice the longest option by wording length.
- Do not make the correct choice the shortest option either.
- Keep all 4 choices within a similar length range (target 8-14 words each when feasible).
- Randomize correct-answer letters across A/B/C/D; avoid obvious patterns or repeated streaks.
- Do not reveal the correct answer by wording patterns.
- No asterisks, bold, or special formatting.
- All text must be plain and readable.

Output rules:
- Return only a raw JSON object.
- Do not use triple backticks.
- Do not add explanations outside JSON.''';
  }

  String _buildFastChallengeModePrompt(String focusCategory) {
    final focusTopic = keyAreas[focusCategory]?.isNotEmpty ?? false
        ? keyAreas[focusCategory]![Random().nextInt(keyAreas[focusCategory]!.length)]
        : 'General topics';
    final categories = _categoriesForEligibility();
    final otherCategories = categories.where((cat) => cat != focusCategory).toList();
    final otherText = otherCategories
        .map((cat) {
          final topic = keyAreas[cat]?.isNotEmpty ?? false
              ? keyAreas[cat]![Random().nextInt(keyAreas[cat]!.length)]
              : 'General topics';
          return '$cat: $topic';
        })
        .join(' | ');

    return '''Generate 10 advanced UPCAT reasoning multiple-choice questions as raw JSON only.
Format:
{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}
Distribution:
- Q1-6 focus category: $focusCategory ($focusTopic)
- Q7-10 mixed categories: $otherText
Rules:
- Exactly 4 choices per question
- Correct answer must be one of A/B/C/D
- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"
- Keep wording concise but appropriately difficult (higher-order UPCAT reasoning)
- Keep choices similar in length and tone (target 8-14 words when feasible)
- Make distractors plausible based on common student misconceptions
- Avoid giveaway wording like "always", "never", or obvious textbook clues
- Vary stem style (analysis, inference, best answer, problem-solving)
- Do not make correct answer obviously longest/shortest by wording
- Randomize answer letters across A/B/C/D without obvious streaks
- No markdown, no asterisks, no extra text
- Return JSON only, no markdown.''';
  }
}


import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/device_service.dart';
import 'services/notification_service.dart';

import 'question_screen.dart';
import 'models/question.dart';
import 'models/pnle_key_areas.dart';
import 'services/question_generation_service.dart';
import 'services/deepseek_service.dart';
import 'config/secrets.dart';
import 'config/admob_ids.dart';
import 'config/pnle_theme.dart';
import 'generating_dialog.dart';
import 'settings_screen.dart';
import 'onboarding_screen.dart';
import 'services/sound_service.dart';

class _SavedSession {
  final String title;
  final List<Question> questions;
  final DateTime savedAt;
  final String sourceMode;

  _SavedSession({
    required this.title,
    required this.questions,
    DateTime? savedAt,
    this.sourceMode = 'randomQuiz',
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'savedAt': savedAt.toIso8601String(),
        'sourceMode': sourceMode,
        'questions': questions
            .map((q) => {
                  'number': q.number,
                  'category': q.category,
                  'question': q.question,
                  'choices': q.choices,
                  'answer': q.answer,
                  'explanation': q.explanation,
                  'source': q.source,
                })
            .toList(),
      };

  static _SavedSession? fromJson(Map<String, dynamic> json) {
    final titleRaw = json['title'];
    final savedAtRaw = json['savedAt'];
    final sourceModeRaw = json['sourceMode'];
    final questionsRaw = json['questions'];

    if (titleRaw is! String || savedAtRaw is! String || questionsRaw is! List) {
      return null;
    }

    final parsedSavedAt = DateTime.tryParse(savedAtRaw);
    if (parsedSavedAt == null) return null;

    final parsedQuestions = questionsRaw
        .whereType<Map>()
        .map((q) => Question.fromJson(Map<String, dynamic>.from(q)))
        .toList();

    if (parsedQuestions.isEmpty) return null;

    return _SavedSession(
      title: titleRaw,
      questions: parsedQuestions,
      savedAt: parsedSavedAt,
      sourceMode: sourceModeRaw is String ? sourceModeRaw : 'randomQuiz',
    );
  }
}

class _QuizActivityRecord {
  final DateTime date;
  final int questionCount;
  final int correctCount;
  final double scorePercent;

  const _QuizActivityRecord({
    required this.date,
    required this.questionCount,
    required this.correctCount,
    required this.scorePercent,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'questionCount': questionCount,
        'correctCount': correctCount,
        'scorePercent': scorePercent,
      };

  static _QuizActivityRecord? fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'] ?? json['d'];
    final questionRaw = json['questionCount'] ?? json['q'];
    final correctRaw = json['correctCount'] ?? json['c'];
    final scoreRaw = json['scorePercent'] ?? json['p'];
    if (dateRaw is! String || questionRaw is! num) return null;

    final parsedDate = DateTime.tryParse(dateRaw);
    if (parsedDate == null) return null;

    return _QuizActivityRecord(
      date: parsedDate,
      questionCount: questionRaw.toInt(),
      correctCount: (correctRaw is num) ? correctRaw.toInt() : 0,
      scorePercent: (scoreRaw is num) ? scoreRaw.toDouble() : 0,
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
  int _extraSessionAdChances = 2;
  DateTime? _nextExtraSessionAdRefillAt;
  static const int _maxExtraSessionAdChances = 2;
  static const Duration _extraSessionAdRefillDuration = Duration(hours: 2);
  Timer? _extraSessionAdRefillTicker;
  int _zeroAdSessionsRemaining = 4; // First 4 sessions are ad-free
  String? _lastStreakRewardClaimDate;

  // Accumulated stats (never reset, shows lifetime totals)
  int accumulatedQuizzesCompleted = 0;
  int accumulatedQuestionsAnswered = 0;
  int _lifetimeRandomQuizzesCompleted = 0;
  static const int _advancedModeUnlockRequirement = 2;

  bool _isOnline = true;
  int _serverTimeOffsetMs = 0;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  StreamSubscription<DatabaseEvent>? _serverOffsetSubscription;
  bool _hasReceivedConnectionEvent = false;
  Timer? _offlineStateTimer;
  Timer? _internetProbeTimer;

  // Services
  final DeviceService _deviceService = DeviceService();
  String? _deviceId;

  /// Get the Realtime DB instance with the explicit URL.
  /// Required because our RTDB is in asia-southeast1, not the default US region.
  FirebaseDatabase get _rtdb => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://upcat-ios-default-rtdb.asia-southeast1.firebasedatabase.app/',
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
  static const int _maxSavedSessions = 30;
  static const String _savedSessionsPrefsKey = 'savedSessionsPayload';
  final List<_QuizActivityRecord> _quizActivityRecords = [];
  static const int _maxQuizActivityRecords = 120;
  static const int _quizActivityRetentionDays = 45;

  // Daily generation limits (premium only)
  int _dailyGenerationSessionsUsed = 0;
  int _dailyGenerationQuestionsUsed = 0;
  String? _lastGenerationResetDate; // Format: yyyy-MM-dd

  // Focus mode state
  bool _isFocusMode = false;
  String? _focusCategory;
  bool _isPrimingFreeDeepSeekCache = false;
  bool _isPrimingRandomQuizCache = false;
  Completer<void>? _randomQuizPrimeCompleter;
  bool _usedCachedRandomForLastGeneration = false;
  bool _isPrimingChallengeCache = false;
  Completer<void>? _challengePrimeCompleter;
  final Set<String> _usedQuickPracticeSavedSignatures = <String>{};
  final Map<String, List<Question>> _cachedFocusQuestions = {};
  final Map<String, String> _lastPickedKeyAreaByCategory = {};
  List<Question>? _cachedRandomQuizQuestions;
  Map<String, String>? _cachedRandomQuizCoverage;
  List<Question>? _cachedChallengeQuestions;
  static const String _randomQuizCachePrefsKey = 'cachedRandomQuizPayload';
  static const String _focusCachePrefsKey = 'cachedFocusQuizPayload';
  static const String _challengeCachePrefsKey = 'cachedChallengeQuizPayload';
  // bool _hasChosenEligibility = false; // Removed - not currently used
  bool _showFirstTimeFlow = false;
  String _nickname = '';
  bool _muteAllSounds = false;
  bool _notificationsEnabled = false;

  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  InterstitialAd? _menuInterstitialAd;

  BannerAd? _bannerAd;

  Map<String, List<String>> get keyAreas => pnleKeyAreas;

  String _pickRandomKeyArea(
    String category, {
    bool avoidImmediateRepeat = true,
  }) {
    final topics = keyAreas[category];
    if (topics == null || topics.isEmpty) {
      debugPrint('⚠️ No topics found for category: $category');
      return 'General topics';
    }

    if (!avoidImmediateRepeat || topics.length <= 1) {
      final picked = topics[Random().nextInt(topics.length)];
      _lastPickedKeyAreaByCategory[category] = picked;
      return picked;
    }

    final lastPicked = _lastPickedKeyAreaByCategory[category];
    final pool = topics.where((topic) => topic != lastPicked).toList();
    final source = pool.isNotEmpty ? pool : topics;
    final picked = source[Random().nextInt(source.length)];
    _lastPickedKeyAreaByCategory[category] = picked;
    return picked;
  }

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

  bool get _hasUnlockedAdvancedModes =>
      _lifetimeRandomQuizzesCompleted >= _advancedModeUnlockRequirement;

  bool get _hasSavedTestsData => _savedSessions.isNotEmpty;

  bool get _canClaimStreakRewardToday =>
      completedSessions >= 4 &&
      _lastStreakRewardClaimDate != _getTodayDateString();

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
  String _dailyMotivationalQuote = '';
  String _dailyMotivationalQuoteDate = '';

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
    _initRealtimeStatusListeners();
    _loadPersonalizationPrefs();
    _checkOnboarding();

    // Kick off pre-generation immediately so first-time users can warm caches
    // even while RTDB restore/network permission prompts are in progress.
    _kickoffInitialPregenerationWarmup();

    // Restore from RTDB first (survives reinstall), then local loads fill in gaps
    _restoreAllProgressFromRtdb().then((_) {
      _loadSavedSessions();
      _loadFocusAndChallengeCaches();
      _loadRandomQuizCache();
      _loadStreak();
      _loadExtraSessionAdState();
      _loadAccumulatedStats();
      _loadQuizActivityRecords();
      _loadDailyGenerationUsage();
      _loadDailyFreeTestsFromRealtimeDb();
      _loadDailyCompletedSessions();
      _loadCategoryScores();
      _loadZeroAdSessions();
      _resetDailyCategoryScoresIfNeeded();
      unawaited(_primeMissingCachesAsNeeded());
      unawaited(_promptNicknameIfMissing());
    });
  }

  Future<void> _primeMissingCachesAsNeeded() async {
    unawaited(_primeRandomQuizCacheIfEligible());

    if (!_hasUnlockedAdvancedModes) return;

    final weakestCategory = _getWeakestCategory();
    if (weakestCategory.isNotEmpty) {
      unawaited(_primeFreeDeepSeekCaches());
    }
    unawaited(_primeChallengeCacheIfEligible());
  }

  void _kickoffInitialPregenerationWarmup() {
    unawaited(_primeMissingCachesAsNeeded());

    // Retry shortly after startup to catch cases where network permission dialog
    // delayed initial requests on first app open (notably iOS first launch).
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      unawaited(_primeMissingCachesAsNeeded());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rewardedAd?.dispose();
    _menuInterstitialAd?.dispose();
    _bannerAd?.dispose();
    _extraSessionAdRefillTicker?.cancel();
    _connectionSubscription?.cancel();
    _serverOffsetSubscription?.cancel();
    _offlineStateTimer?.cancel();
    _internetProbeTimer?.cancel();
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

  void _initRealtimeStatusListeners() {
    _connectionSubscription =
        _rtdb.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value == true;
      if (!mounted) {
        _isOnline = connected;
        return;
      }

      if (!_hasReceivedConnectionEvent) {
        _hasReceivedConnectionEvent = true;
        _isOnline = connected;
        if (connected) {
          unawaited(_restoreAllProgressFromRtdb());
          unawaited(_syncAllProgressToRtdb());
        }
        return;
      }

      if (connected) {
        _offlineStateTimer?.cancel();
        _offlineStateTimer = null;
        _internetProbeTimer?.cancel();

        final changed = !_isOnline;
        if (changed) {
          setState(() {
            _isOnline = true;
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          unawaited(_restoreAllProgressFromRtdb());
          unawaited(_syncAllProgressToRtdb());
        }
        return;
      }

      _offlineStateTimer?.cancel();
      _offlineStateTimer = Timer(const Duration(seconds: 4), () async {
        if (!mounted) {
          _isOnline = false;
          return;
        }
        if (!_isOnline) return;

        final hasInternet = await _verifyInternetConnectivity();
        if (!mounted) return;
        if (hasInternet) {
          if (!_isOnline) {
            setState(() {
              _isOnline = true;
            });
          }
          return;
        }

        setState(() {
          _isOnline = false;
        });
      });
    });

    _serverOffsetSubscription =
        _rtdb.ref('.info/serverTimeOffset').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw is num) {
        _serverTimeOffsetMs = raw.toInt();
      }
    });

    _internetProbeTimer =
        Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted) return;
      final hasInternet = await _verifyInternetConnectivity();
      if (!mounted) return;
      if (_isOnline != hasInternet) {
        setState(() {
          _isOnline = hasInternet;
        });
      }
    });
  }

  Future<bool> _verifyInternetConnectivity() async {
    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return true;
      }
    } catch (_) {}

    try {
      final response = await http
          .get(
            Uri.parse(
              'https://upcat-ios-default-rtdb.asia-southeast1.firebasedatabase.app/.json',
            ),
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode < 500) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  DateTime _serverNow() {
    return DateTime.now().add(Duration(milliseconds: _serverTimeOffsetMs));
  }

  bool _requireOnlineForProgressAction(String actionName) {
    if (_isOnline) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Connect to the internet to $actionName and keep session counts accurate.',
          style: GoogleFonts.outfit(),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    return false;
  }

  // =========================
  // ONBOARDING & STREAK
  // =========================
  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final isComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!isComplete) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (dialogContext) => OnboardingScreen(
          onComplete: (nickname) async {
            await _saveNickname(nickname);
            if (!mounted) return;
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
            setState(() {
              showOnboarding = false;
            });
          },
        ),
      );
      if (!mounted) return;
      setState(() => showOnboarding = true);
    }
  }

  Future<void> _loadPersonalizationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nickname = prefs.getString('user_nickname')?.trim() ?? '';
      _muteAllSounds = prefs.getBool('mute_all_sounds') ?? false;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
    });
    await SoundService().setMuted(_muteAllSounds);
    if (_notificationsEnabled) {
      await _syncNotificationSchedules();
    }
  }

  Future<bool> _setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (enabled) {
      final granted = await NotificationService.instance.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Notification permission denied. You can enable it in system settings.',
                style: GoogleFonts.outfit(),
              ),
            ),
          );
        }
        return false;
      }

      await NotificationService.instance.scheduleDailySessionsReady();
      await prefs.setBool('notifications_enabled', true);
      if (mounted) {
        setState(() {
          _notificationsEnabled = true;
        });
      } else {
        _notificationsEnabled = true;
      }
      await _syncNotificationSchedules();
      return true;
    }

    await NotificationService.instance.cancelAllManaged();
    await prefs.setBool('notifications_enabled', false);
    if (mounted) {
      setState(() {
        _notificationsEnabled = false;
      });
    } else {
      _notificationsEnabled = false;
    }
    return false;
  }

  Future<void> _syncNotificationSchedules() async {
    if (!_notificationsEnabled) return;

    await NotificationService.instance.scheduleDailySessionsReady();

    if (_extraSessionAdChances >= _maxExtraSessionAdChances ||
        _nextExtraSessionAdRefillAt == null) {
      await NotificationService.instance.cancelAdCapsRefilled();
      return;
    }

    final missing = _maxExtraSessionAdChances - _extraSessionAdChances;
    final target = _nextExtraSessionAdRefillAt!
        .add(_extraSessionAdRefillDuration * (missing - 1));
    await NotificationService.instance.scheduleAdCapsRefilled(target);
  }

  Future<void> _saveNickname(String nickname) async {
    final normalized = nickname.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_nickname', normalized);
    if (!mounted) return;
    setState(() {
      _nickname = normalized;
    });
    unawaited(_syncAllProgressToRtdb());
  }

  Future<void> _setMuteAllSounds(bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mute_all_sounds', muted);
    await SoundService().setMuted(muted);
    if (!mounted) return;
    setState(() {
      _muteAllSounds = muted;
    });
    unawaited(_syncAllProgressToRtdb());
  }

  Future<void> _promptNicknameIfMissing() async {
    if (!mounted) return;
    if (showOnboarding) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!onboardingComplete) return;

    final currentNickname = (_nickname.trim().isNotEmpty)
        ? _nickname.trim()
        : (prefs.getString('user_nickname')?.trim() ?? '');
    if (currentNickname.isNotEmpty) {
      if (_nickname != currentNickname && mounted) {
        setState(() {
          _nickname = currentNickname;
        });
      }
      return;
    }

    final nicknameController = TextEditingController();
    String entered = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: PnleTheme.bgTop,
              title: Text(
                'Set Your Nickname',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: TextField(
                controller: nicknameController,
                autofocus: true,
                maxLength: 24,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter your nickname',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  counterStyle: GoogleFonts.outfit(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: PnleTheme.accent),
                  ),
                ),
                onChanged: (value) {
                  entered = value.trim();
                  setDialogState(() {});
                },
              ),
              actions: [
                ElevatedButton(
                  onPressed: entered.isEmpty
                      ? null
                      : () async {
                          await _saveNickname(entered);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PnleTheme.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadStreak() async {
    final prefs = await SharedPreferences.getInstance();
    _lastStreakRewardClaimDate = prefs.getString('lastStreakRewardClaimDate');
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
        // Do not auto-increment on app open; streak only increments after
        // the user completes required sessions for the day.
        setState(() => currentStreak = max(currentStreak, streak));
      } else {
        // Missed a day, reset streak.
        setState(() => currentStreak = 0);
      }
    } else {
      setState(() => currentStreak = max(currentStreak, streak));
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

  Future<void> _loadExtraSessionAdState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedChances =
        prefs.getInt('extraSessionAdChances') ?? _maxExtraSessionAdChances;
    final savedNextRefill = prefs.getInt('nextExtraSessionAdRefillAtMs');

    if (!mounted) {
      _extraSessionAdChances = savedChances.clamp(0, _maxExtraSessionAdChances);
      _nextExtraSessionAdRefillAt = savedNextRefill == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(savedNextRefill);
      return;
    }

    setState(() {
      _extraSessionAdChances = savedChances.clamp(0, _maxExtraSessionAdChances);
      _nextExtraSessionAdRefillAt = savedNextRefill == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(savedNextRefill);
    });

    _processExtraSessionAdRefill(forcePersist: false);
    _ensureExtraSessionRefillTicker();
    unawaited(_syncNotificationSchedules());
  }

  Future<void> _persistExtraSessionAdState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('extraSessionAdChances', _extraSessionAdChances);
    if (_nextExtraSessionAdRefillAt == null) {
      await prefs.remove('nextExtraSessionAdRefillAtMs');
    } else {
      await prefs.setInt(
        'nextExtraSessionAdRefillAtMs',
        _nextExtraSessionAdRefillAt!.millisecondsSinceEpoch,
      );
    }
  }

  void _ensureExtraSessionRefillTicker() {
    _extraSessionAdRefillTicker ??=
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          _extraSessionAdChances < _maxExtraSessionAdChances &&
          _nextExtraSessionAdRefillAt != null) {
        setState(() {});
      }
      unawaited(_processExtraSessionAdRefill());
    });
  }

  Future<void> _processExtraSessionAdRefill({bool forcePersist = true}) async {
    if (_extraSessionAdChances >= _maxExtraSessionAdChances) {
      if (_nextExtraSessionAdRefillAt != null) {
        if (mounted) {
          setState(() {
            _nextExtraSessionAdRefillAt = null;
          });
        } else {
          _nextExtraSessionAdRefillAt = null;
        }
        if (forcePersist) {
          await _persistExtraSessionAdState();
          unawaited(_syncAllProgressToRtdb());
        }
      }
      return;
    }

    final now = _serverNow();
    var hasChanges = false;

    if (_nextExtraSessionAdRefillAt == null) {
      _nextExtraSessionAdRefillAt = now.add(_extraSessionAdRefillDuration);
      hasChanges = true;
    }

    while (_nextExtraSessionAdRefillAt != null &&
        !now.isBefore(_nextExtraSessionAdRefillAt!) &&
        _extraSessionAdChances < _maxExtraSessionAdChances) {
      _extraSessionAdChances++;
      hasChanges = true;
      if (_extraSessionAdChances < _maxExtraSessionAdChances) {
        _nextExtraSessionAdRefillAt =
            _nextExtraSessionAdRefillAt!.add(_extraSessionAdRefillDuration);
      } else {
        _nextExtraSessionAdRefillAt = null;
      }
    }

    if (hasChanges && mounted) {
      setState(() {});
    }

    if (hasChanges && forcePersist) {
      await _persistExtraSessionAdState();
      unawaited(_syncAllProgressToRtdb());
      unawaited(_syncNotificationSchedules());
    }
  }

  String _extraSessionCountdownText() {
    if (_extraSessionAdChances >= _maxExtraSessionAdChances ||
        _nextExtraSessionAdRefillAt == null) {
      return 'Full';
    }

    final remaining = _nextExtraSessionAdRefillAt!.difference(_serverNow());
    if (remaining.inSeconds <= 0) {
      return 'Refilling...';
    }

    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final s = remaining.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAccumulatedStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localQuizzes = prefs.getInt('accumulatedQuizzesCompleted') ?? 0;
      final localQuestions = prefs.getInt('accumulatedQuestionsAnswered') ?? 0;
      final localRandomQuizzes =
          prefs.getInt('lifetimeRandomQuizzesCompleted') ?? 0;

      // Merge with current values (max wins - never overwrite higher values
      // that may have been restored from RTDB or Firestore already)
      setState(() {
        accumulatedQuizzesCompleted =
            max(accumulatedQuizzesCompleted, localQuizzes);
        accumulatedQuestionsAnswered =
            max(accumulatedQuestionsAnswered, localQuestions);
        _lifetimeRandomQuizzesCompleted =
            max(_lifetimeRandomQuizzesCompleted, localRandomQuizzes);
      });
    } catch (e) {
      debugPrint('Error loading accumulated stats: $e');
    }
  }

  Future<void> _persistAccumulatedStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'accumulatedQuizzesCompleted', accumulatedQuizzesCompleted);
      await prefs.setInt(
          'accumulatedQuestionsAnswered', accumulatedQuestionsAnswered);
      await prefs.setInt(
        'lifetimeRandomQuizzesCompleted',
        _lifetimeRandomQuizzesCompleted,
      );

      // Also sync to RTDB (survives reinstall without sign-in)
      _syncAllProgressToRtdb();
    } catch (e) {
      debugPrint('Error persisting stats: $e');
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

  Future<void> _loadSavedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_savedSessionsPrefsKey);
      if (payload == null || payload.isEmpty) return;

      final decoded = jsonDecode(payload);
      if (decoded is! List) return;

      final loaded = <_SavedSession>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = _SavedSession.fromJson(Map<String, dynamic>.from(item));
        if (parsed != null) {
          loaded.add(parsed);
        }
      }

      if (!mounted) return;
      setState(() {
        _savedSessions
          ..clear()
          ..addAll(loaded.take(_maxSavedSessions));
      });
    } catch (e) {
      debugPrint('Error loading saved sessions: $e');
    }
  }

  Future<void> _persistSavedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = _savedSessions.map((e) => e.toJson()).toList();
      await prefs.setString(_savedSessionsPrefsKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Error persisting saved sessions: $e');
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
      await prefs.setString('dailyGenerationResetDate',
          _lastGenerationResetDate ?? _getTodayDateString());
      await prefs.setInt(
          'dailyGenerationSessions', _dailyGenerationSessionsUsed);
      await prefs.setInt(
          'dailyGenerationQuestions', _dailyGenerationQuestionsUsed);
    } catch (e) {
      debugPrint('Error persisting daily generation usage: $e');
    }
  }

  // ignore: unused_element
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

      final prefs = await SharedPreferences.getInstance();

      final today = DateTime.now();
      final todayStr =
          DateTime(today.year, today.month, today.day).toIso8601String();
      final storedFreeTestResetDate =
          prefs.getString('lastFreeTestResetDate') ?? todayStr;

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
        'lifetimeRandomQuizzesCompleted': _lifetimeRandomQuizzesCompleted,
        // Daily sessions
        'completedSessions': completedSessions,
        'lastSessionDate': todayStr,
        // Streak
        'currentStreak': currentStreak,
        'lastQuizDate': lastQuizDate?.toIso8601String(),
        // Eligibility
        'selectedEligibility': eligibility,
        'hasChosenEligibility': !_showFirstTimeFlow,
        'nickname': _nickname,
        'muteAllSounds': _muteAllSounds,
        // Free tests (also saved separately, but include here for completeness)
        'remainingFreeTests': remainingFreeTests,
        'lastFreeTestResetDate': storedFreeTestResetDate,
        // Extra-session ad chances with timed refill
        'extraSessionAdChances': _extraSessionAdChances,
        'nextExtraSessionAdRefillAtMs':
            _nextExtraSessionAdRefillAt?.millisecondsSinceEpoch,
        // Zero-ad sessions (lifetime counter)
        'zeroAdSessionsRemaining': _zeroAdSessionsRemaining,
        'lastStreakRewardClaimDate': _lastStreakRewardClaimDate,
        // Compact quiz activity history for 10-day screen (capped + pruned)
        'quizActivityRecords': _quizActivityRecords
            .map((record) => {
                  'd': record.date.toIso8601String(),
                  'q': record.questionCount,
                  'c': record.correctCount,
                  'p': record.scorePercent,
                })
            .toList(),
        // Daily reset tracking (prevents re-reset after app data clear)
        'lastCategoryScoreResetDate': todayStr,
        // Sync timestamp
        'lastSyncTime': DateTime.now().toIso8601String(),
      };

      await _rtdb
          .ref('devices/$_deviceId/progress')
          .set(progressData)
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
              remoteTotal > 0
                  ? remoteTotal
                  : (categoryScores[key]!['total'] as int),
            ),
            'weight': remoteWeight > 0
                ? remoteWeight
                : categoryScores[key]!['weight'],
          };
        }
      }
    }

    // --- Accumulated stats (max wins) ---
    final remoteQuizzes =
        (data['accumulatedQuizzesCompleted'] as num?)?.toInt() ?? 0;
    final remoteQuestions =
        (data['accumulatedQuestionsAnswered'] as num?)?.toInt() ?? 0;
    final remoteRandomQuizzes =
        (data['lifetimeRandomQuizzesCompleted'] as num?)?.toInt() ?? 0;
    accumulatedQuizzesCompleted =
        max(accumulatedQuizzesCompleted, remoteQuizzes);
    accumulatedQuestionsAnswered =
        max(accumulatedQuestionsAnswered, remoteQuestions);
    _lifetimeRandomQuizzesCompleted =
        max(_lifetimeRandomQuizzesCompleted, remoteRandomQuizzes);

    // --- Completed sessions (only restore if same day) ---
    final remoteCompletedSessions =
        (data['completedSessions'] as num?)?.toInt() ?? 0;
    final remoteLastSessionDate = data['lastSessionDate'] as String?;
    if (remoteLastSessionDate != null) {
      final remoteDate = DateTime.tryParse(remoteLastSessionDate);
      if (remoteDate != null) {
        final remoteDateOnly =
            DateTime(remoteDate.year, remoteDate.month, remoteDate.day);
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

    final remoteNickname = (data['nickname'] as String?)?.trim();
    if (remoteNickname != null && remoteNickname.isNotEmpty) {
      _nickname = remoteNickname;
    }

    final remoteMute = data['muteAllSounds'] as bool?;
    if (remoteMute != null) {
      _muteAllSounds = remoteMute;
      unawaited(SoundService().setMuted(remoteMute));
    }

    _ensurePnleCategoryScores();

    // --- Zero-ad sessions (lifetime counter: min wins, preserves most progress) ---
    final remoteZeroAdSessions =
        (data['zeroAdSessionsRemaining'] as num?)?.toInt();
    if (remoteZeroAdSessions != null) {
      _zeroAdSessionsRemaining =
          min(_zeroAdSessionsRemaining, remoteZeroAdSessions);
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
        final resetDayOnly =
            DateTime(resetDate.year, resetDate.month, resetDate.day);
        if (todayOnly.isAtSameMomentAs(resetDayOnly)) {
          remainingFreeTests = min(remainingFreeTests, remoteRemaining);
        } else {
          remainingFreeTests = 4;
        }
      }
    }

    // --- Extra-session ad chances (server-backed, not daily reset) ---
    final remoteAdChances = (data['extraSessionAdChances'] as num?)?.toInt();
    if (remoteAdChances != null) {
      _extraSessionAdChances =
          remoteAdChances.clamp(0, _maxExtraSessionAdChances);
    }

    final remoteRefillMs =
        (data['nextExtraSessionAdRefillAtMs'] as num?)?.toInt();
    if (remoteRefillMs != null) {
      _nextExtraSessionAdRefillAt =
          DateTime.fromMillisecondsSinceEpoch(remoteRefillMs);
    }

    final remoteStreakRewardDate = data['lastStreakRewardClaimDate'] as String?;
    if (remoteStreakRewardDate != null && remoteStreakRewardDate.isNotEmpty) {
      _lastStreakRewardClaimDate = remoteStreakRewardDate;
    }
  }

  /// Restore ALL app state from Realtime DB. Called on app startup
  /// BEFORE SharedPreferences load so RTDB data wins when prefs are empty.
  Future<void> _restoreAllProgressFromRtdb() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final snapshot = await _rtdb
          .ref('devices/$_deviceId/progress')
          .get()
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
      await prefs.setInt(
          'accumulatedQuizzesCompleted', accumulatedQuizzesCompleted);
      await prefs.setInt(
          'accumulatedQuestionsAnswered', accumulatedQuestionsAnswered);
      await prefs.setInt(
        'lifetimeRandomQuizzesCompleted',
        _lifetimeRandomQuizzesCompleted,
      );
      await prefs.setString('categoryScores', jsonEncode(categoryScores));
      await prefs.setInt('currentStreak', currentStreak);
      if (lastQuizDate != null) {
        await prefs.setString('lastQuizDate', lastQuizDate!.toIso8601String());
      }
      await prefs.setString('selected_eligibility', eligibility);
      await prefs.setBool('has_chosen_eligibility', !_showFirstTimeFlow);
      await prefs.setString('user_nickname', _nickname);
      await prefs.setBool('mute_all_sounds', _muteAllSounds);
      await prefs.setInt('completedSessions', completedSessions);
      final now = DateTime.now();
      final remoteLastSessionDate = data['lastSessionDate'] as String?;
      if (remoteLastSessionDate != null && remoteLastSessionDate.isNotEmpty) {
        await prefs.setString('lastSessionDate', remoteLastSessionDate);
      } else {
        await prefs.setString('lastSessionDate',
            DateTime(now.year, now.month, now.day).toIso8601String());
      }
      await prefs.setInt('remainingFreeTests', remainingFreeTests);
      await prefs.setInt('extraSessionAdChances', _extraSessionAdChances);
      if (_nextExtraSessionAdRefillAt != null) {
        await prefs.setInt(
          'nextExtraSessionAdRefillAtMs',
          _nextExtraSessionAdRefillAt!.millisecondsSinceEpoch,
        );
      } else {
        await prefs.remove('nextExtraSessionAdRefillAtMs');
      }
      if (_lastStreakRewardClaimDate != null) {
        await prefs.setString(
          'lastStreakRewardClaimDate',
          _lastStreakRewardClaimDate!,
        );
      }
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
      await _processExtraSessionAdRefill(forcePersist: false);
      _ensureExtraSessionRefillTicker();
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
          final today = DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day);

          if (lastResetDateStr != null) {
            final lastResetDate = DateTime.parse(lastResetDateStr);
            final lastResetDay = DateTime(
                lastResetDate.year, lastResetDate.month, lastResetDate.day);

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
              await ref.update({
                'remaining': 4,
                'lastResetDate': today.toIso8601String(),
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('remainingFreeTests', 4);
              await prefs.setString(
                  'lastFreeTestResetDate', today.toIso8601String());
            }
          } else {
            await ref.update({
              'remaining': 4,
              'lastResetDate': today.toIso8601String(),
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('remainingFreeTests', 4);
            await prefs.setString(
                'lastFreeTestResetDate', today.toIso8601String());
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
      debugPrint('Error loading free tests from Realtime DB: $e');
      await _loadDailyFreeTestsLocal();
    }
  }

  /// Initialize free tests in Realtime DB (first time)
  Future<void> _initializeRealtimeDbFreeTests() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
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
      debugPrint('Error initializing Realtime DB: $e');
    }
  }

  /// Load daily free tests from local storage (fallback)
  Future<void> _loadDailyFreeTestsLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastResetDateStr = prefs.getString('lastFreeTestResetDate');
      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);

      if (lastResetDateStr == null) {
        await prefs.setString('lastFreeTestResetDate', today.toIso8601String());
        if (!mounted) return;
        setState(() => remainingFreeTests = 4);
        return;
      }

      final lastResetDate = DateTime.parse(lastResetDateStr);
      final lastResetDay =
          DateTime(lastResetDate.year, lastResetDate.month, lastResetDate.day);

      if (!mounted) return;
      setState(() {
        if (today.isAfter(lastResetDay)) {
          remainingFreeTests = 4;
        } else {
          remainingFreeTests = prefs.getInt('remainingFreeTests') ?? 4;
        }
      });

      if (today.isAfter(lastResetDay)) {
        await prefs.setInt('remainingFreeTests', 4);
        await prefs.setString('lastFreeTestResetDate', today.toIso8601String());
      }
    } catch (e) {
      debugPrint('Error loading daily free tests locally: $e');
    }
  }

  /// Save remaining free tests to both local and Realtime DB
  Future<void> _persistDailyFreeTests() async {
    // Save locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('remainingFreeTests', remainingFreeTests);
    } catch (e) {
      debugPrint('Error persisting free tests locally: $e');
    }

    // Save to Realtime DB
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayOnly =
          DateTime(now.year, now.month, now.day).toIso8601String();
      final lastResetDate =
          prefs.getString('lastFreeTestResetDate') ?? todayOnly;
      final db = _rtdb;
      await db.ref('devices/$_deviceId/freeTests').update({
        'remaining': remainingFreeTests,
        'lastResetDate': lastResetDate,
      });

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
          final localWeight = (value['weight'] as num?)?.toDouble() ??
              defaultWeights[key] ??
              0.0;

          if (categoryScores.containsKey(key)) {
            final currentCorrect = categoryScores[key]!['correct'] as int;
            // Max merge: never overwrite higher values from RTDB/Firestore restore
            categoryScores[key] = {
              'correct': max(currentCorrect, localCorrect),
              'total': max(
                _dailyTargetTotalForCategory(key),
                localTotal > 0
                    ? localTotal
                    : (categoryScores[key]!['total'] as int),
              ),
              'weight': localWeight > 0
                  ? localWeight
                  : categoryScores[key]!['weight'],
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
      debugPrint('Error loading category scores: $e');
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
      debugPrint('Error persisting category scores: $e');
    }
  }

  /// Load daily completed sessions with reset at midnight (merge, never overwrite higher)
  Future<void> _loadDailyCompletedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSessionDateStr = prefs.getString('lastSessionDate');
      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);

      if (lastSessionDateStr == null) {
        // First time — only set date, don't reset completedSessions
        // (may already be restored from RTDB/Firestore)
        await prefs.setString('lastSessionDate', today.toIso8601String());
        return;
      }

      final lastSessionDate = DateTime.parse(lastSessionDateStr);
      final lastSessionDay = DateTime(
          lastSessionDate.year, lastSessionDate.month, lastSessionDate.day);

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
      debugPrint('Error loading completed sessions: $e');
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
      debugPrint('Error persisting completed sessions: $e');
    }
  }

  Future<void> _updateStreakAfterQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _serverNow();
    final today = DateTime(now.year, now.month, now.day);
    final newStreak = currentStreak + 1;

    await prefs.setString('lastQuizDate', today.toIso8601String());
    await prefs.setInt('currentStreak', newStreak);

    if (!mounted) return;
    setState(() {
      lastQuizDate = today;
      currentStreak = newStreak;
    });

    // Sync to RTDB (survives reinstall)
    await _syncAllProgressToRtdb();
    await _showStreakRewardClaimDialogIfEligible();
  }

  Future<void> _showStreakRewardClaimDialogIfEligible() async {
    if (!mounted || completedSessions < 4) return;
    if (!_requireOnlineForProgressAction('claim your streak reward')) return;

    final todayKey = _getTodayDateString();
    if (_lastStreakRewardClaimDate == todayKey) {
      return;
    }

    final claimed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    PnleTheme.bgTop.withValues(alpha: 0.96),
                    PnleTheme.bgBottom.withValues(alpha: 0.93),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: PnleTheme.accent.withValues(alpha: 0.55),
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: PnleTheme.accent.withValues(alpha: 0.28),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Streak Reward Unlocked',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You completed all 4 sessions today. Claim +1 free session now?',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          'Later',
                          style: GoogleFonts.outfit(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PnleTheme.accent,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(
                          'Claim +1',
                          style:
                              GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (claimed != true || !mounted) return;

    setState(() {
      remainingFreeTests++;
      _lastStreakRewardClaimDate = todayKey;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastStreakRewardClaimDate', todayKey);
    await _persistDailyFreeTests();
    await _syncAllProgressToRtdb();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Streak reward claimed: +1 free session.',
          style: GoogleFonts.outfit(),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
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

  String _normalizeSpecialization(String? value) {
    if (value == null || value.isEmpty) return 'English Major';
    if (value == 'Professional Eligibility' ||
        value == 'Sub-Professional Eligibility') {
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
  String _rewardedAdUnitId({bool forceTestFallback = false}) {
    if (forceTestFallback && Platform.isIOS) return AdMobIds.iosRewardedTest;
    return AdMobIds.rewarded;
  }

  String _bannerAdUnitId({bool forceTestFallback = false}) {
    if (forceTestFallback && Platform.isIOS) return AdMobIds.iosBannerTest;
    return AdMobIds.banner;
  }

  String _menuInterstitialAdUnitId({bool forceTestFallback = false}) {
    if (forceTestFallback && Platform.isIOS) {
      return AdMobIds.iosInterstitialTest;
    }
    return AdMobIds.interstitial;
  }

  void _loadRewardedAd({bool useTestFallback = false}) {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId(forceTestFallback: useTestFallback),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          if (Platform.isIOS && !AdMobIds.useTestAds && !useTestFallback) {
            debugPrint(
              'iOS rewarded ad failed (${error.code}: ${error.message}). Retrying with test rewarded ID fallback.',
            );
            _loadRewardedAd(useTestFallback: true);
          }
        },
      ),
    );
  }

  void _loadMenuInterstitialAd({bool useTestFallback = false}) {
    InterstitialAd.load(
      adUnitId: _menuInterstitialAdUnitId(forceTestFallback: useTestFallback),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _menuInterstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          if (Platform.isIOS && !AdMobIds.useTestAds && !useTestFallback) {
            debugPrint(
              'iOS interstitial ad failed (${error.code}: ${error.message}). Retrying with test interstitial ID fallback.',
            );
            _loadMenuInterstitialAd(useTestFallback: true);
          }
        },
      ),
    );
  }

  void _loadBannerAd({bool useTestFallback = false}) {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId(forceTestFallback: useTestFallback),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (Platform.isIOS && !AdMobIds.useTestAds && !useTestFallback) {
            debugPrint(
              'iOS banner ad failed (${error.code}: ${error.message}). Retrying with test banner ID fallback.',
            );
            _loadBannerAd(useTestFallback: true);
          }
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

  /// Load zero-ad sessions remaining from SharedPreferences
  Future<void> _loadZeroAdSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final remaining = prefs.getInt('zeroAdSessionsRemaining');
    if (remaining != null && mounted) {
      setState(() {
        _zeroAdSessionsRemaining = remaining;
      });
    }
    unawaited(_primeRandomQuizCacheIfEligible());
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
      final lastResetOnly =
          DateTime(lastReset.year, lastReset.month, lastReset.day);
      if (todayOnly.isAtSameMomentAs(lastResetOnly)) {
        return; // Already reset today
      }
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
    await prefs.setString(
        'lastCategoryScoreResetDate', todayOnly.toIso8601String());
    await prefs.setString('categoryScores', jsonEncode(categoryScores));
  }

  Future<void> _watchRewardedAdForExtraQuiz() async {
    if (!_requireOnlineForProgressAction('watch an ad for a bonus session')) {
      return;
    }

    await _processExtraSessionAdRefill();
    if (!mounted) return;

    if (_extraSessionAdChances <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No ad chances left. Next refill in ${_extraSessionCountdownText()}.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
      return;
    }

    // Show rewarded ad
    final adWatched = await _showRewardedAd();

    if (adWatched && mounted) {
      final now = _serverNow();
      setState(() {
        remainingFreeTests++; // Grant 1 extra quiz
        _extraSessionAdChances = max(0, _extraSessionAdChances - 1);
        if (_extraSessionAdChances < _maxExtraSessionAdChances) {
          // Keep the existing refill countdown if one is already running.
          if (_nextExtraSessionAdRefillAt == null ||
              !_nextExtraSessionAdRefillAt!.isAfter(now)) {
            _nextExtraSessionAdRefillAt =
                now.add(_extraSessionAdRefillDuration);
          }
        }
      });

      // Persist free tests + ad count to RTDB immediately
      await _persistDailyFreeTests();
      await _persistExtraSessionAdState();
      _ensureExtraSessionRefillTicker();
      await _syncAllProgressToRtdb();
      await _syncNotificationSchedules();

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

  String _quickPracticeSignature(Question q) {
    return '${q.category}::${q.question}::${q.answer}';
  }

  List<Question> _quickPracticeFromUnusedSavedPool(String focusCategory) {
    final pooled = _savedSessions
        .expand((session) => session.questions)
        .where((question) => question.category == focusCategory)
        .where((question) => !_usedQuickPracticeSavedSignatures
            .contains(_quickPracticeSignature(question)))
        .map((question) => question.shuffled())
        .toList();
    pooled.shuffle(Random());
    return pooled.take(5).toList();
  }

  DeepSeekService _buildDeepSeekService({
    required bool fastMode,
    int? tokenCap,
    Duration? requestTimeoutOverride,
    int? maxRetriesOverride,
  }) {
    return DeepSeekService(
      apiKey: DEEPSEEK_API_KEY,
      requestTimeout: requestTimeoutOverride ??
          (fastMode
              ? const Duration(seconds: 100)
              : const Duration(seconds: 90)),
      maxRetries: maxRetriesOverride ?? (fastMode ? 1 : 3),
      temperature: fastMode ? 0.2 : 0.3,
      maxTokens: tokenCap,
    );
  }

  Future<void> _primeFreeDeepSeekCaches() async {
    if (isPremiumUser || isTrialActive || _isPrimingFreeDeepSeekCache) return;
    if (!_hasUnlockedAdvancedModes) return;

    final weakestCategory = _getWeakestCategory();
    if (weakestCategory.isEmpty) return;

    final hasFocusCache =
        (_cachedFocusQuestions[weakestCategory]?.length ?? 0) >= 15;
    if (hasFocusCache) return;

    _isPrimingFreeDeepSeekCache = true;
    try {
      if (!hasFocusCache) {
        final focusPrompt = _buildFastFocusPrompt(weakestCategory);
        final focusCategoryMap = _buildFocusCategoryMap(weakestCategory);

        final focusService =
            _buildDeepSeekService(fastMode: true, tokenCap: 3200);
        List<Question> deepSeekQuestions = const [];

        try {
          deepSeekQuestions = await focusService.generateQuestions(
            focusPrompt,
            eligibility,
            categoryMap: focusCategoryMap,
            allowPartialResults: true,
          );
        } catch (e) {
          debugPrint('Focus cache warmup DeepSeek incomplete: $e');
        }

        if (deepSeekQuestions.length >= 15) {
          _cachedFocusQuestions[weakestCategory] =
              deepSeekQuestions.take(15).toList();
          unawaited(_persistFocusAndChallengeCaches());
          return;
        }

        if (GEMINI_API_KEY.trim().isNotEmpty) {
          try {
            final geminiService =
                QuestionGenerationService(apiKey: GEMINI_API_KEY);
            final geminiQuestions = await geminiService.generateQuestions(
              focusPrompt,
              eligibility,
              categoryMap: focusCategoryMap,
            );

            final merged = <Question>[];
            final seen = <String>{};
            void addAllUnique(List<Question> items) {
              for (final q in items) {
                if (merged.length >= 15) break;
                final signature =
                    '${q.category}|${q.question.trim().toLowerCase()}';
                if (seen.add(signature)) {
                  merged.add(q);
                }
              }
            }

            addAllUnique(deepSeekQuestions);
            addAllUnique(geminiQuestions);

            if (merged.length >= 15) {
              _cachedFocusQuestions[weakestCategory] = merged.take(15).toList();
              unawaited(_persistFocusAndChallengeCaches());
              return;
            }
          } catch (e) {
            debugPrint('Focus cache warmup Gemini rescue failed: $e');
          }
        }

        // Keep whatever DeepSeek produced so it can still be reused by future recovery logic.
        if (deepSeekQuestions.isNotEmpty) {
          _cachedFocusQuestions[weakestCategory] = deepSeekQuestions;
          unawaited(_persistFocusAndChallengeCaches());
        }
      }
    } catch (e) {
      debugPrint('Free DeepSeek cache warmup skipped: $e');
    } finally {
      _isPrimingFreeDeepSeekCache = false;
    }
  }

  bool _canUseDeepSeekPregeneration() {
    return !isPremiumUser &&
        !isTrialActive &&
        !_showFirstTimeFlow &&
        DEEPSEEK_API_KEY.trim().isNotEmpty;
  }

  String _categoryForQuestionNumber(int number) {
    if (number >= 1 && number <= 2) return 'Language Proficiency';
    if (number >= 3 && number <= 7) return 'Reading Comprehension';
    if (number >= 8 && number <= 11) return 'Mathematics';
    return 'Science';
  }

  Question _cloneQuestionWithNumber(Question source, int number) {
    return Question(
      number: number,
      category: _categoryForQuestionNumber(number),
      question: source.question,
      choices: List<String>.from(source.choices),
      answer: source.answer,
      explanation: source.explanation,
      source: source.source,
    );
  }

  List<Question> _mergeQuestionSetsForRandomCache({
    required List<Question> salvaged,
    required List<Question> fallback,
    int needed = 15,
  }) {
    final mergedByNumber = <int, Question>{};

    for (final q in salvaged) {
      if (q.number >= 1 &&
          q.number <= needed &&
          !mergedByNumber.containsKey(q.number)) {
        mergedByNumber[q.number] = _cloneQuestionWithNumber(q, q.number);
      }
    }

    for (final q in fallback) {
      if (q.number >= 1 &&
          q.number <= needed &&
          !mergedByNumber.containsKey(q.number)) {
        mergedByNumber[q.number] = _cloneQuestionWithNumber(q, q.number);
      }
    }

    if (mergedByNumber.length < needed) {
      for (final q in fallback) {
        if (mergedByNumber.length >= needed) break;
        int slot = 1;
        while (slot <= needed && mergedByNumber.containsKey(slot)) {
          slot++;
        }
        if (slot <= needed) {
          mergedByNumber[slot] = _cloneQuestionWithNumber(q, slot);
        }
      }
    }

    final result = <Question>[];
    for (int i = 1; i <= needed; i++) {
      final q = mergedByNumber[i];
      if (q != null) result.add(q);
    }
    return result;
  }

  Future<List<Question>> _buildRandomPregeneratedQuestions(
      Map<String, String> coverage) async {
    final prompt = _buildFastPromptFromCoverage(coverage);
    List<Question> salvagedDeepSeek = const [];

    if (DEEPSEEK_API_KEY.trim().isNotEmpty) {
      try {
        final deepSeekService = _buildDeepSeekService(
          fastMode: true,
          requestTimeoutOverride: const Duration(seconds: 80),
          maxRetriesOverride: 1,
        );
        salvagedDeepSeek = await deepSeekService.generateQuestions(
          prompt,
          eligibility,
          allowPartialResults: true,
        );
      } catch (e) {
        debugPrint('Random quiz pre-generation DeepSeek failed: $e');
      }
    }

    if (salvagedDeepSeek.length >= 15) {
      return salvagedDeepSeek.take(15).toList();
    }

    if (GEMINI_API_KEY.trim().isEmpty) {
      if (salvagedDeepSeek.isNotEmpty) {
        return salvagedDeepSeek;
      }
      throw Exception('Gemini API key missing for pre-generation fallback.');
    }

    final geminiService = QuestionGenerationService(apiKey: GEMINI_API_KEY);
    final fallbackGemini = await geminiService
        .generateQuestions(prompt, eligibility)
        .timeout(const Duration(seconds: 80));

    if (salvagedDeepSeek.isEmpty) {
      return fallbackGemini.take(15).toList();
    }

    return _mergeQuestionSetsForRandomCache(
      salvaged: salvagedDeepSeek,
      fallback: fallbackGemini,
      needed: 15,
    );
  }

  bool _coverageMatchesCachedRandom(Map<String, String>? coverage) {
    if (coverage == null || _cachedRandomQuizCoverage == null) return false;
    if (coverage.length != _cachedRandomQuizCoverage!.length) return false;
    for (final entry in coverage.entries) {
      if (_cachedRandomQuizCoverage![entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _loadRandomQuizCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_randomQuizCachePrefsKey);
      if (payload == null || payload.isEmpty) return;

      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final coverageRaw = decoded['coverage'];
      final questionsRaw = decoded['questions'];
      if (coverageRaw is! Map || questionsRaw is! List) return;

      final coverage = Map<String, String>.from(coverageRaw);
      final questions = questionsRaw
          .whereType<Map>()
          .map((q) => Question.fromJson(Map<String, dynamic>.from(q)))
          .toList();

      if (questions.length < 15) return;

      if (!mounted) return;
      setState(() {
        _cachedRandomQuizCoverage = coverage;
        _cachedRandomQuizQuestions = questions;
      });
    } catch (e) {
      debugPrint('Could not load random quiz pregen cache: $e');
    }
  }

  Map<String, dynamic> _questionToJson(Question q) {
    return {
      'number': q.number,
      'category': q.category,
      'question': q.question,
      'choices': q.choices,
      'answer': q.answer,
      'explanation': q.explanation,
      'source': q.source,
    };
  }

  Question _questionFromJson(Map<String, dynamic> json) {
    return Question.fromJson(json);
  }

  Future<void> _loadFocusAndChallengeCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final focusPayload = prefs.getString(_focusCachePrefsKey);
      if (focusPayload != null && focusPayload.isNotEmpty) {
        final decoded = jsonDecode(focusPayload);
        if (decoded is Map) {
          final restoredFocus = <String, List<Question>>{};
          for (final entry in decoded.entries) {
            final key = entry.key.toString();
            final value = entry.value;
            if (value is! List) continue;
            final parsed = value
                .whereType<Map>()
                .map((q) => _questionFromJson(Map<String, dynamic>.from(q)))
                .toList();
            if (parsed.isNotEmpty) {
              restoredFocus[key] = parsed;
            }
          }
          if (mounted) {
            setState(() {
              _cachedFocusQuestions
                ..clear()
                ..addAll(restoredFocus);
            });
          } else {
            _cachedFocusQuestions
              ..clear()
              ..addAll(restoredFocus);
          }
        }
      }

      final challengePayload = prefs.getString(_challengeCachePrefsKey);
      if (challengePayload != null && challengePayload.isNotEmpty) {
        final decoded = jsonDecode(challengePayload);
        if (decoded is List) {
          final parsed = decoded
              .whereType<Map>()
              .map((q) => _questionFromJson(Map<String, dynamic>.from(q)))
              .toList();
          if (parsed.isNotEmpty) {
            if (mounted) {
              setState(() {
                _cachedChallengeQuestions = parsed;
              });
            } else {
              _cachedChallengeQuestions = parsed;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Could not load focus/challenge pregen cache: $e');
    }
  }

  Future<void> _persistFocusAndChallengeCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final focusPayload = _cachedFocusQuestions.map(
        (category, questions) => MapEntry(
          category,
          questions.map(_questionToJson).toList(),
        ),
      );
      if (focusPayload.isEmpty) {
        await prefs.remove(_focusCachePrefsKey);
      } else {
        await prefs.setString(_focusCachePrefsKey, jsonEncode(focusPayload));
      }

      final challengeQuestions = _cachedChallengeQuestions;
      if (challengeQuestions == null || challengeQuestions.isEmpty) {
        await prefs.remove(_challengeCachePrefsKey);
      } else {
        await prefs.setString(
          _challengeCachePrefsKey,
          jsonEncode(challengeQuestions.map(_questionToJson).toList()),
        );
      }
    } catch (e) {
      debugPrint('Could not persist focus/challenge pregen cache: $e');
    }
  }

  Future<void> _persistRandomQuizCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_cachedRandomQuizCoverage == null ||
          _cachedRandomQuizQuestions == null) {
        await prefs.remove(_randomQuizCachePrefsKey);
        return;
      }

      final payload = {
        'coverage': _cachedRandomQuizCoverage,
        'questions': _cachedRandomQuizQuestions!.map(_questionToJson).toList(),
      };
      await prefs.setString(_randomQuizCachePrefsKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Could not persist random quiz pregen cache: $e');
    }
  }

  Future<void> _clearRandomQuizCache() async {
    if (!mounted) return;
    setState(() {
      _cachedRandomQuizCoverage = null;
      _cachedRandomQuizQuestions = null;
    });
    await _persistRandomQuizCache();
  }

  Future<void> _primeRandomQuizCacheIfEligible({
    bool force = false,
    Map<String, String>? coverageOverride,
  }) async {
    if (!_canUseDeepSeekPregeneration()) return;
    if (_isPrimingRandomQuizCache) {
      await _randomQuizPrimeCompleter?.future;
      return;
    }
    if (!force && (_cachedRandomQuizQuestions?.length ?? 0) >= 15) {
      if (coverageOverride == null ||
          _coverageMatchesCachedRandom(coverageOverride)) {
        return;
      }
    }

    _isPrimingRandomQuizCache = true;
    _randomQuizPrimeCompleter = Completer<void>();
    try {
      final coverage = coverageOverride ?? _generateTestCoverage();
      final questions = await _buildRandomPregeneratedQuestions(coverage);
      if (questions.length < 15 || !mounted) return;

      setState(() {
        _cachedRandomQuizCoverage = Map<String, String>.from(coverage);
        _cachedRandomQuizQuestions = questions;
      });
      await _persistRandomQuizCache();
    } catch (e) {
      debugPrint('Random quiz DeepSeek pre-generation skipped: $e');
    } finally {
      _isPrimingRandomQuizCache = false;
      if (!(_randomQuizPrimeCompleter?.isCompleted ?? true)) {
        _randomQuizPrimeCompleter?.complete();
      }
      _randomQuizPrimeCompleter = null;
    }
  }

  Future<void> _primeFocusCacheForCategory(
    String category, {
    bool force = false,
  }) async {
    if (!_canUseDeepSeekPregeneration()) return;
    final existing = _cachedFocusQuestions[category];
    if (!force && (existing?.length ?? 0) >= 15) return;

    try {
      final service = _buildDeepSeekService(fastMode: true);
      final focusQuestions = await service.generateQuestions(
        _buildFastFocusPrompt(category),
        eligibility,
        categoryMap: _buildFocusCategoryMap(category),
      );
      if (focusQuestions.length < 15 || !mounted) return;

      setState(() {
        _cachedFocusQuestions[category] = focusQuestions;
      });
      await _persistFocusAndChallengeCaches();
    } catch (e) {
      debugPrint('Focus quiz pre-generation skipped: $e');
    }
  }

  // =========================
  // TEST GENERATION
  // =========================
  Future<bool> _generateTest(
      {bool isFocusMode = false, String? focusCategory}) async {
    _usedCachedRandomForLastGeneration = false;

    // Premium/Trial uses Gemini-first; all other users go straight to DeepSeek pre-generation flow.
    final useGemini = isPremiumUser || isTrialActive;

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
        throw Exception(
            'Gemini API key missing. Re-run with --dart-define=GEMINI_API_KEY=...');
      }
      try {
        final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
        _generatedQuestions = await service.generateQuestions(
          prompt,
          eligibility,
          categoryMap: categoryMap,
        );
      } catch (e) {
        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          throw Exception(
              'DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
        }

        final service = _buildDeepSeekService(fastMode: false);
        _generatedQuestions = await service.generateQuestions(
          prompt,
          eligibility,
          categoryMap: categoryMap,
        );
      }
    } else {
      if (DEEPSEEK_API_KEY.trim().isEmpty) {
        throw Exception(
            'DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
      }
      if (useFocusMode && category != null) {
        final cached = _cachedFocusQuestions[category];
        if (cached != null && cached.length >= 15) {
          _generatedQuestions = cached.take(15).toList();
          _cachedFocusQuestions.remove(category);
          unawaited(_persistFocusAndChallengeCaches());
          unawaited(_primeFocusCacheForCategory(category, force: true));
        } else {
          final service = _buildDeepSeekService(fastMode: true);
          _generatedQuestions = await service.generateQuestions(
            deepSeekPrompt,
            eligibility,
            categoryMap: categoryMap,
          );
        }
      } else {
        if (_isPrimingRandomQuizCache) {
          await _randomQuizPrimeCompleter?.future;
        }

        if ((_cachedRandomQuizQuestions?.length ?? 0) >= 15) {
          _usedCachedRandomForLastGeneration = true;
          if (_cachedRandomQuizCoverage != null) {
            _currentTestCoverage =
                Map<String, String>.from(_cachedRandomQuizCoverage!);
          }
          _generatedQuestions = _cachedRandomQuizQuestions!.take(15).toList();
        } else {
          final service = _buildDeepSeekService(fastMode: true);
          _generatedQuestions = await service.generateQuestions(
            deepSeekPrompt,
            eligibility,
            categoryMap: categoryMap,
          );
        }
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
    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();

    // Questions 1-10: Focus category
    for (int q = 1; q <= 10; q++) {
      categoryMap[q] = focusCategory;
    }

    // Questions 11-15: Other categories (mixed)
    int questionNum = 11;
    for (int i = 0; i < otherCategories.length && questionNum <= 15; i++) {
      final cat = otherCategories[i];
      final questionsInCat =
          (15 - questionNum + 1) ~/ (otherCategories.length - i);
      for (int j = 0; j < questionsInCat && questionNum <= 15; j++) {
        categoryMap[questionNum] = cat;
        questionNum++;
      }
    }

    return categoryMap;
  }

  Map<int, String> _buildChallengeCategoryMap(String focusCategory) {
    final categoryMap = <int, String>{};
    final categories = _categoriesForEligibility();

    for (int q = 1; q <= 6; q++) {
      categoryMap[q] = focusCategory;
    }

    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();
    if (otherCategories.length == 1) {
      for (int q = 7; q <= 10; q++) {
        categoryMap[q] = otherCategories[0];
      }
    } else if (otherCategories.length == 2) {
      categoryMap[7] = otherCategories[0];
      categoryMap[8] = otherCategories[0];
      categoryMap[9] = otherCategories[1];
      categoryMap[10] = otherCategories[1];
    } else if (otherCategories.length >= 3) {
      categoryMap[7] = otherCategories[0];
      categoryMap[8] = otherCategories[1];
      categoryMap[9] = otherCategories[2];
      categoryMap[10] = otherCategories[2];
    }

    return categoryMap;
  }

  Future<void> _primeChallengeCacheIfEligible({bool force = false}) async {
    if (!_hasUnlockedAdvancedModes) return;
    if (DEEPSEEK_API_KEY.trim().isEmpty) return;

    if (_isPrimingChallengeCache) {
      await _challengePrimeCompleter?.future;
      return;
    }

    if (!force && (_cachedChallengeQuestions?.length ?? 0) >= 10) {
      return;
    }

    _isPrimingChallengeCache = true;
    _challengePrimeCompleter = Completer<void>();
    try {
      final categories = _categoriesForEligibility();
      if (categories.isEmpty) return;

      final focusCategory = categories[Random().nextInt(categories.length)];
      final prompt = _buildFastChallengeModePrompt(focusCategory);
      final categoryMap = _buildChallengeCategoryMap(focusCategory);

      final service = _buildDeepSeekService(fastMode: true, tokenCap: 2200);
      final questions = await service.generateQuestions(
        prompt,
        eligibility,
        categoryMap: categoryMap,
      );

      if (!mounted || questions.length < 10) return;
      setState(() {
        _cachedChallengeQuestions = questions.take(10).toList();
      });
      await _persistFocusAndChallengeCaches();
    } catch (e) {
      debugPrint('Challenge cache pre-generation skipped: $e');
    } finally {
      _isPrimingChallengeCache = false;
      if (!(_challengePrimeCompleter?.isCompleted ?? true)) {
        _challengePrimeCompleter?.complete();
      }
      _challengePrimeCompleter = null;
    }
  }

  Map<String, String> _generateTestCoverage() {
    final Map<String, String> selected = {};

    final categories = _categoriesForEligibility();

    for (final category in categories) {
      selected[category] = _pickRandomKeyArea(category);
    }

    return selected;
  }

  Map<String, String> _generateFocusModeCoverage(String focusCategory) {
    final Map<String, String> selected = {};
    final categories = _categoriesForEligibility();

    // Generate topics for all categories (for the 5 mixed questions in focus mode)
    for (final category in categories) {
      selected[category] = _pickRandomKeyArea(category);
    }

    return selected;
  }

  // Quick Practice Mode (5 questions)
  Future<void> _startQuickPractice() async {
    if (!_hasSavedTestsData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Quick Practice unlocks after you have at least one saved test.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final weakestCategory = _getWeakestCategory();
    final targetCategory = weakestCategory.isNotEmpty
        ? weakestCategory
        : _savedSessions.first.questions.first.category;

    final pooledQuestions = _quickPracticeFromUnusedSavedPool(targetCategory);

    if (pooledQuestions.length >= 5) {
      for (final q in pooledQuestions.take(5)) {
        _usedQuickPracticeSavedSignatures.add(_quickPracticeSignature(q));
      }

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
      final prompt = _buildFastQuickPracticePrompt(targetCategory);

      // Build category map for Quick Practice (all 5 questions from weakest category)
      final categoryMap = <int, String>{
        1: targetCategory,
        2: targetCategory,
        3: targetCategory,
        4: targetCategory,
        5: targetCategory,
      };

      late final List<Question> questions;
      if (DEEPSEEK_API_KEY.trim().isEmpty) {
        throw Exception(
            'DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
      }

      try {
        final service = _buildDeepSeekService(
          fastMode: true,
          tokenCap: 1800,
          requestTimeoutOverride: const Duration(seconds: 60),
          maxRetriesOverride: 1,
        );
        questions = await service.generateQuestions(
          prompt,
          eligibility,
          categoryMap: categoryMap,
        );
      } catch (_) {
        if (GEMINI_API_KEY.trim().isEmpty) {
          rethrow;
        }
        final geminiService = QuestionGenerationService(apiKey: GEMINI_API_KEY);
        questions = await geminiService.generateQuestions(
          _buildQuickPracticePrompt(targetCategory),
          eligibility,
          categoryMap: categoryMap,
        );
      }

      if (!mounted) return;
      Navigator.pop(context); // Close generation dialog

      if (questions.isNotEmpty) {
        final results = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuestionScreen(
              questions: questions.take(5).toList(),
              isPremium: isPremiumUser || isTrialActive,
              recordResults:
                  false, // Quick Practice doesn't count toward objective
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
          SnackBar(
              content: Text('Error generating questions: ${e.toString()}')),
        );
      }
    }
  }

  // Challenge Mode (10 advanced questions)
  Future<void> _startChallengeMode() async {
    if (!_hasUnlockedAdvancedModes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete $_advancedModeUnlockRequirement Random Quizzes to unlock Challenge Mode.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (remainingFreeTests <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No session credits left. Watch an ad or claim streak rewards to continue.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if ((_cachedChallengeQuestions?.length ?? 0) < 10 &&
        _isPrimingChallengeCache) {
      await _waitForChallengeCachePrime();
      if (!mounted) return;
    }

    _launchChallengeMode();
  }

  Future<void> _waitForChallengeCachePrime({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final future = _challengePrimeCompleter?.future;
    if (future == null) return;
    try {
      await future.timeout(timeout);
    } catch (_) {
      // Timeout fallback: launch will continue with regular generation.
    }
  }

  Future<void> _launchChallengeMode() async {
    if ((_cachedChallengeQuestions?.length ?? 0) >= 10) {
      final cachedQuestions = _cachedChallengeQuestions!.take(10).toList();
      _cachedChallengeQuestions = null;
      unawaited(_persistFocusAndChallengeCaches());

      if (!_consumeFreeSessionAllowance()) {
        return;
      }

      _incrementGenerationUsage(cachedQuestions.length);
      _addSavedSession(cachedQuestions, null, sourceMode: 'challenge');
      unawaited(_primeChallengeCacheIfEligible(force: true));

      final results = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionScreen(
            questions: cachedQuestions,
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
                PnleTheme.bgTop.withValues(alpha: 0.95),
                PnleTheme.bgBottom.withValues(alpha: 0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.amber.withValues(alpha: 0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_rounded,
                      color: Colors.amber.shade200, size: 18),
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
                valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.amber.shade200),
              ),
              const SizedBox(height: 14),
              Text(
                'Generating advanced questions...',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Premium/Trial uses Gemini-first; all other users use DeepSeek generation flow.
      final useGemini = isPremiumUser || isTrialActive;
      // Generate random category focus for challenge
      final categories = _categoriesForEligibility();
      final focusCategory = categories[Random().nextInt(categories.length)];
      final prompt = useGemini
          ? _buildChallengeModePrompt(focusCategory)
          : _buildFastChallengeModePrompt(focusCategory);

      final categoryMap = _buildChallengeCategoryMap(focusCategory);

      late final List<Question> questions;
      if (useGemini) {
        if (GEMINI_API_KEY.trim().isEmpty) {
          throw Exception(
              'Gemini API key missing. Re-run with --dart-define=GEMINI_API_KEY=...');
        }
        try {
          final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
          questions = await service.generateQuestions(prompt, eligibility,
              categoryMap: categoryMap);
        } catch (e) {
          if (DEEPSEEK_API_KEY.trim().isEmpty) {
            throw Exception(
                'DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
          }

          final service = _buildDeepSeekService(fastMode: false);
          questions = await service.generateQuestions(prompt, eligibility,
              categoryMap: categoryMap);
        }
      } else {
        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          throw Exception(
              'DeepSeek API key missing. Re-run with --dart-define=DEEPSEEK_API_KEY=...');
        }
        final service = _buildDeepSeekService(fastMode: true, tokenCap: 2200);
        questions = await service.generateQuestions(prompt, eligibility,
            categoryMap: categoryMap);
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (questions.isNotEmpty) {
        setState(() {
          _cachedChallengeQuestions = questions.take(10).toList();
        });
        unawaited(_persistFocusAndChallengeCaches());

        if (!_consumeFreeSessionAllowance()) {
          return;
        }

        // Increment daily usage counter
        _incrementGenerationUsage(questions.length);
        _addSavedSession(
          questions.take(10).toList(),
          null,
          sourceMode: 'challenge',
        );

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

        unawaited(_primeChallengeCacheIfEligible(force: true));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error generating challenge: ${e.toString()}')),
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
        continue;
      }

      final correct = (data['correct'] ?? 0) as int;
      final total = (data['total'] ?? 0) as int;
      if (total <= 0) {
        continue;
      }

      final percentage = (correct / total) * 100;
      if (percentage < lowestPercentage) {
        lowestPercentage = percentage;
        weakest = cat;
      }
    }

    return weakest;
  }

  Widget _buildCircularProgressCard(double totalAvg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.11),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
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
                      color: Colors.white.withValues(alpha: 0.7),
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
                ? 'Excellent progress. Keep the momentum.'
                : totalAvg >= 50
                    ? 'Steady progress. Keep practicing to reach 65%.'
                    : 'More practice needed. Stay consistent each day.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.85),
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
    final name = _nickname.trim();
    if (name.isEmpty) {
      return '${_getGreeting()} there! 👋';
    }
    return '${_getGreeting()} $name! 👋';
  }

  String _getDailyMotivationalQuote() {
    final todayKey = _getTodayDateString();
    if (_dailyMotivationalQuote.isNotEmpty &&
        _dailyMotivationalQuoteDate == todayKey) {
      return _dailyMotivationalQuote;
    }

    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final index = Random(seed).nextInt(motivationalQuotes.length);
    _dailyMotivationalQuote = motivationalQuotes[index];
    _dailyMotivationalQuoteDate = todayKey;
    return _dailyMotivationalQuote;
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
                PnleTheme.bgTop.withValues(alpha: 0.95),
                PnleTheme.bgBottom.withValues(alpha: 0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.purple.withValues(alpha: 0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flash_on_rounded,
                      color: Colors.purple.shade200, size: 18),
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
                valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.purple.shade200),
              ),
              const SizedBox(height: 14),
              Text(
                'Generating questions...',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.9),
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
    final bool activeIsFocusMode = _isFocusMode;
    final String? activeFocusCategory = _focusCategory;
    final Map<String, String>? activeCoverage = _currentTestCoverage == null
        ? null
        : Map<String, String>.from(_currentTestCoverage!);

    final effectiveModeLabel = modeLabel ??
        (activeIsFocusMode
            ? 'FOCUS MODE${activeFocusCategory != null ? ' • $activeFocusCategory' : ''}'
            : 'RANDOM QUIZ');

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      useRootNavigator: true,
      builder: (dialogContext) {
        return GeneratingTestDialog(
          onGenerate: _generateTest,
          onShowAd: null,
          onSuccess: null,
          onSkip: () {
            final consumed = _consumeFreeSessionAllowance();
            if (consumed && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Skipped session: 1 credit was consumed.',
                    style: GoogleFonts.outfit(),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }

            if (_usedCachedRandomForLastGeneration) {
              unawaited(_clearRandomQuizCache());
            }

            if (activeIsFocusMode && activeFocusCategory != null) {
              unawaited(_primeFocusCacheForCategory(activeFocusCategory,
                  force: true));
            } else {
              unawaited(_primeRandomQuizCacheIfEligible(
                force: true,
              ));
              unawaited(_primeFreeDeepSeekCaches());
            }
          },
          isPremium: isPremiumUser,
          isFocusMode: activeIsFocusMode,
          focusCategory: activeFocusCategory,
          modeLabel: effectiveModeLabel,
          onStart: () async {
            if (!_consumeFreeSessionAllowance()) {
              return;
            }

            if (_usedCachedRandomForLastGeneration) {
              await _clearRandomQuizCache();
            }
            if (!mounted || !dialogContext.mounted) return;

            Navigator.of(dialogContext, rootNavigator: true)
                .pop(); // Close generation dialog
            _addSavedSession(
              _generatedQuestions,
              activeCoverage,
              sourceMode: activeIsFocusMode ? 'focusMode' : 'randomQuiz',
            );
            if (activeIsFocusMode && activeFocusCategory != null) {
              unawaited(_primeFocusCacheForCategory(activeFocusCategory,
                  force: true));
            } else {
              unawaited(_primeRandomQuizCacheIfEligible(
                force: true,
              ));
              unawaited(_primeFreeDeepSeekCaches());
            }
            // Function to start the test
            Future<void> startTest(List<Question> questions) async {
              final results = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionScreen(
                    questions: questions,
                    isPremium: isPremiumUser || isTrialActive,
                    recordResults: true,
                    testMode: activeIsFocusMode ? 'focusMode' : 'randomQuiz',
                    zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
                  ),
                ),
              );
              if (results is Map<String, dynamic> && mounted) {
                _updateTestResults(results);
                final nextAction = results['nextAction'];
                if (nextAction == 'playAgain') {
                  final replayCoverage =
                      !activeIsFocusMode && _cachedRandomQuizCoverage != null
                          ? Map<String, String>.from(_cachedRandomQuizCoverage!)
                          : activeCoverage;
                  if (replayCoverage != null) {
                    _showTestCoverageDialog(
                      replayCoverage,
                      isFocusMode: activeIsFocusMode,
                      focusCategory: activeFocusCategory,
                    );
                  }
                } else if (nextAction == 'menu') {
                  setState(() {
                    currentScreen = 2;
                  });
                }
              }
              // Handle different return values
              else if (results == 'playAgain' && mounted) {
                // User clicked Play Again - show Test Coverage dialog again for new test
                final replayCoverage =
                    !activeIsFocusMode && _cachedRandomQuizCoverage != null
                        ? Map<String, String>.from(_cachedRandomQuizCoverage!)
                        : activeCoverage;
                if (replayCoverage != null) {
                  _showTestCoverageDialog(
                    replayCoverage,
                    isFocusMode: activeIsFocusMode,
                    focusCategory: activeFocusCategory,
                  );
                }
              } else if (results == 'menu' && mounted) {
                // User clicked Quiz Menu - return to Quiz section
                setState(() {
                  currentScreen = 2; // 2 = Quiz
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
  }

  bool _consumeFreeSessionAllowance() {
    if (!_requireOnlineForProgressAction('start this session')) {
      return false;
    }

    if (remainingFreeTests <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No session credits left. Watch an ad or claim streak rewards to continue.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
    }

    setState(() {
      remainingFreeTests--;
    });
    unawaited(_persistDailyFreeTests());
    unawaited(_syncAllProgressToRtdb());

    // Decrement zero-ad sessions for Random Quiz / Focus Mode
    if (_zeroAdSessionsRemaining > 0) {
      _zeroAdSessionsRemaining--;
      _persistZeroAdSessions();
      if (_zeroAdSessionsRemaining <= 0) {
        unawaited(_primeRandomQuizCacheIfEligible(
          force: true,
          coverageOverride: _currentTestCoverage,
        ));
      }
    }

    return true;
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
    Map<String, String>? coverage, {
    String sourceMode = 'randomQuiz',
  }) {
    final title = _pickSavedTitle(coverage);
    final resolvedTitle = sourceMode == 'challenge' ? 'Challenge Mode' : title;
    final savedSession = _SavedSession(
      title: resolvedTitle,
      questions: questions,
      sourceMode: sourceMode,
    );
    setState(() {
      _savedSessions.insert(0, savedSession);
      if (_savedSessions.length > _maxSavedSessions) {
        _savedSessions.removeLast();
      }
    });

    unawaited(_persistSavedSessions());
    _syncAllProgressToRtdb();
  }

  void _showSavedTestsDialog() {
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
                    color: Colors.white.withValues(alpha: 0.3),
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
                            color: PnleTheme.accent.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: PnleTheme.accent.withValues(alpha: 0.5),
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
                                '${_savedSessions.length}/$_maxSavedSessions tests saved',
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.6),
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
                              color: Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              Icons.close,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.2),
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 20),
                    // Notice about saved tests
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber.withValues(alpha: 0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saved tests are stored locally. They will be deleted if you reinstall the app or clear app data.',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.8),
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
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No saved tests yet',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Complete a quiz to save it here',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.5),
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final session = _savedSessions[index];
                            final questionCount = session.questions.length;
                            final timeAgo = _formatTimeAgo(session.savedAt);
                            final modeIcon =
                                _savedSessionModeIcon(session.sourceMode);
                            final modeColor =
                                _savedSessionModeColor(session.sourceMode);

                            return Dismissible(
                              key: Key(
                                  'session_${session.savedAt.millisecondsSinceEpoch}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.8),
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
                                unawaited(_persistSavedSessions());
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
                                  Future<void> startTest(
                                      List<Question> questions) async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => QuestionScreen(
                                          questions: questions,
                                          isPremium:
                                              isPremiumUser || isTrialActive,
                                          recordResults: false,
                                          testMode: 'previous',
                                          zeroAdSessionsRemaining:
                                              _zeroAdSessionsRemaining,
                                        ),
                                      ),
                                    );

                                    // Handle Play Again - reshuffle the same questions
                                    if (result == 'playAgain' && mounted) {
                                      final reshuffledQuestions = session
                                          .questions
                                          .map((q) => q.shuffled())
                                          .toList();
                                      await startTest(reshuffledQuestions);
                                    } else if (result == 'menu' && mounted) {
                                      // User clicked Quiz Menu - return to Quiz section
                                      setState(() {
                                        currentScreen = 2; // 2 = Quiz
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
                                        Colors.white.withValues(alpha: 0.15),
                                        Colors.white.withValues(alpha: 0.08),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              modeColor.withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          modeIcon,
                                          color: modeColor,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                  modeIcon,
                                                  size: 14,
                                                  color: modeColor.withValues(
                                                      alpha: 0.9),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$questionCount questions',
                                                  style: GoogleFonts.outfit(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.6),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Icon(
                                                  Icons.access_time_rounded,
                                                  size: 14,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  timeAgo,
                                                  style: GoogleFonts.outfit(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.6),
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
                                        color:
                                            Colors.white.withValues(alpha: 0.7),
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
                          color: Colors.white.withValues(alpha: 0.4),
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

  IconData _savedSessionModeIcon(String sourceMode) {
    switch (sourceMode) {
      case 'focusMode':
        return Icons.center_focus_strong_rounded;
      case 'challenge':
        return Icons.emoji_events_rounded;
      case 'quickPractice':
        return Icons.flash_on_rounded;
      case 'randomQuiz':
      default:
        return Icons.shuffle_rounded;
    }
  }

  Color _savedSessionModeColor(String sourceMode) {
    switch (sourceMode) {
      case 'focusMode':
        return const Color(0xFFFF8A80);
      case 'challenge':
        return Colors.amber.shade300;
      case 'quickPractice':
        return Colors.purple.shade200;
      case 'randomQuiz':
      default:
        return PnleTheme.accent;
    }
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
    final resultMode = results['testMode'] as String?;

    if (correctCount == null || totalCount == null) return;

    // Assess only first 4 completed sessions
    if (completedSessions >= 4) return;

    var shouldUpdateStreak = false;
    final hadChallengeUnlock = _hasUnlockedAdvancedModes;

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
        shouldUpdateStreak = true;
      }

      // Update accumulated stats that persist across days
      accumulatedQuizzesCompleted++;
      totalCount.forEach((category, count) {
        accumulatedQuestionsAnswered += count;
      });
      if (resultMode == 'randomQuiz') {
        _lifetimeRandomQuizzesCompleted++;
      }

      final sessionQuestions =
          totalCount.values.fold<int>(0, (sum, value) => sum + value);
      final sessionCorrect =
          correctCount.values.fold<int>(0, (sum, value) => sum + value);
      final sessionPercent = sessionQuestions > 0
          ? (sessionCorrect / sessionQuestions) * 100
          : 0.0;

      _quizActivityRecords.insert(
        0,
        _QuizActivityRecord(
          date: DateTime.now(),
          questionCount: sessionQuestions,
          correctCount: sessionCorrect,
          scorePercent: sessionPercent,
        ),
      );
      _pruneQuizActivityRecords();
    });

    // Persist all data
    _persistQuizActivityRecords();
    _persistAccumulatedStats();
    _persistCategoryScores();
    _persistCompletedSessions();
    unawaited(_syncNotificationSchedules());
    unawaited(_primeMissingCachesAsNeeded());

    if (shouldUpdateStreak) {
      unawaited(_updateStreakAfterQuiz());
    }

    if (!hadChallengeUnlock && _hasUnlockedAdvancedModes) {
      unawaited(_primeChallengeCacheIfEligible(force: true));
    }
  }

  String _remainingSessionsTodayText() {
    return '$remainingFreeTests ${remainingFreeTests == 1 ? 'session' : 'sessions'} left today';
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
                          PnleTheme.glowA.withValues(alpha: 0.28),
                          PnleTheme.glowA.withValues(alpha: 0.0),
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
                          PnleTheme.glowB.withValues(alpha: 0.24),
                          PnleTheme.glowB.withValues(alpha: 0.0),
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
      nickname: _nickname,
      muteAllSounds: _muteAllSounds,
      notificationsEnabled: _notificationsEnabled,
      onNicknameChanged: (nickname) async {
        await _saveNickname(nickname);
      },
      onMuteAllSoundsChanged: (muted) async {
        await _setMuteAllSounds(muted);
      },
      onNotificationsChanged: (enabled) async {
        return _setNotificationsEnabled(enabled);
      },
      embedded: true,
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

  // ignore: unused_element
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
                PnleTheme.bgTop.withValues(alpha: 0.98),
                PnleTheme.bgBottom.withValues(alpha: 0.98),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: PnleTheme.accent.withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
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
                                      Colors.white.withValues(alpha: 0.08),
                                      Colors.white.withValues(alpha: 0.03),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color:
                                        PnleTheme.accent.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: PnleTheme.accent
                                            .withValues(alpha: 0.15),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                              color: Colors.white
                                                  .withValues(alpha: 0.6),
                                              fontWeight: FontWeight.w400,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      color: PnleTheme.accent
                                          .withValues(alpha: 0.5),
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
          _getDailyMotivationalQuote(),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: Colors.white.withValues(alpha: 0.85),
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
                Colors.orange.withValues(alpha: 0.3),
                Colors.red.withValues(alpha: 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
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
            ],
          ),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD76B), Color(0xFFF7A531)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF7A531).withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _canClaimStreakRewardToday
                    ? '4/4 completed today. Claim +1 free session.'
                    : completedSessions >= 4
                        ? '4/4 completed today. +1 reward already claimed.'
                        : 'Complete 4 sessions today to earn +1 free session.',
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _canClaimStreakRewardToday
                    ? 'Claim your reward now. Complete 4 again tomorrow for another bonus session.'
                    : completedSessions >= 4
                        ? 'Excellent consistency today. Come back tomorrow to unlock another bonus session.'
                        : 'Progress today: $completedSessions of 4 sessions completed.',
                style: GoogleFonts.outfit(
                  color: Colors.black.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
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
        if (accumulatedQuizzesCompleted > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.5)),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  const Color(0xFFFF6B6B).withValues(alpha: 0.05),
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
                        weakestCategory.isNotEmpty
                            ? 'Improve $weakestCategory to boost your score'
                            : 'Keep answering quizzes to detect your weakest area',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.8),
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
        ],
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
    final canTakeQuiz = remainingFreeTests > 0;
    final hasRandomReady = (_cachedRandomQuizQuestions?.length ?? 0) >= 15 &&
        _cachedRandomQuizCoverage != null;
    final hasFocusReady = weakestCategory.isNotEmpty &&
        ((_cachedFocusQuestions[weakestCategory]?.length ?? 0) >= 15);
    final hasChallengeReady = (_cachedChallengeQuestions?.length ?? 0) >= 10;
    final showPregenerationState = _canUseDeepSeekPregeneration();
    final isRandomFetching =
        showPregenerationState && _isPrimingRandomQuizCache && !hasRandomReady;
    final isFocusFetching = _hasUnlockedAdvancedModes &&
        _isPrimingFreeDeepSeekCache &&
        !hasFocusReady;
    final isChallengeFetching = _hasUnlockedAdvancedModes &&
        _isPrimingChallengeCache &&
        !hasChallengeReady;

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

              // Quick Stats Dashboard
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'YOUR STATS',
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.7),
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
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        _quickStat(
                          icon: Icons.question_answer_rounded,
                          value: '$totalQuestionsAnswered',
                          label: 'Questions',
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withValues(alpha: 0.2),
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

              if (!_isOnline)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline: quiz starts and rewards are paused until internet reconnects.',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Daily Progress Tracker & Motivational Elements
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withValues(alpha: 0.3),
                      Colors.orange.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.5)),
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
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Streak: $currentStreak ${currentStreak == 1 ? 'day' : 'days'} 🔥',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: PnleTheme.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _remainingSessionsTodayText(),
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_canClaimStreakRewardToday) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isOnline
                                  ? const [
                                      Color(0xFFFFF4B0),
                                      Color(0xFFFFD76B),
                                      Color(0xFFF7A531),
                                    ]
                                  : [
                                      Colors.grey.shade500,
                                      Colors.grey.shade600,
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _isOnline
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFF7A531)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 16,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isOnline
                                  ? _showStreakRewardClaimDialogIfEligible
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.card_giftcard_rounded,
                                      size: 16,
                                      color: _isOnline
                                          ? Colors.black
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Claim Streak Reward (+1 Session)',
                                      style: GoogleFonts.outfit(
                                        color: _isOnline
                                            ? Colors.black
                                            : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Smart Recommendations
              if (weakestCategory.isNotEmpty &&
                  totalAvg < 65 &&
                  accumulatedQuizzesCompleted > 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF34D399).withValues(alpha: 0.2),
                        const Color(0xFF34D399).withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF34D399).withValues(alpha: 0.4)),
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
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (weakestCategory.isNotEmpty &&
                  totalAvg < 65 &&
                  accumulatedQuizzesCompleted > 0)
                const SizedBox(height: 24),

              // Extra sessions via rewarded ads (timed refill, max stack = 2)
              if (remainingFreeTests < 4)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: _modeFadeGradientWithColors(
                      const Color(0xFF4338CA),
                      const Color(0xFF1D4ED8),
                      strength: 0.78,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Watch Ad for +1 Session',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Chances: $_extraSessionAdChances/$_maxExtraSessionAdChances • Next refill: ${_extraSessionCountdownText()}',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (_extraSessionAdChances > 0 && _isOnline)
                            ? _watchRewardedAdForExtraQuiz
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: PnleTheme.bgBottom,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: Text(
                          'Watch',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
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
                  color: Colors.white.withValues(alpha: 0.7),
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
                          if (!mounted) return;
                          final hasPregeneratedRandom =
                              (_cachedRandomQuizQuestions?.length ?? 0) >= 15 &&
                                  _cachedRandomQuizCoverage != null;
                          final coverage = hasPregeneratedRandom
                              ? Map<String, String>.from(
                                  _cachedRandomQuizCoverage!)
                              : _generateTestCoverage();
                          FocusScope.of(context).unfocus();
                          _showTestCoverageDialog(coverage);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString()}')),
                          );
                        }
                      }
                    : null,
                isPrimary: true,
                badge: canTakeQuiz ? null : 'NO CREDITS',
                showReadyBadge: hasRandomReady,
                showFetchingBadge: isRandomFetching,
                isLocked: !canTakeQuiz,
              ),
              const SizedBox(height: 12),

              // 2. Focus Mode
              _quizModeCard(
                icon: Icons.center_focus_strong_rounded,
                title: 'Focus Mode',
                description: weakestCategory.isNotEmpty
                    ? 'Target: $weakestCategory'
                    : 'Unlock after Random Quiz progress',
                gradient: _modeFadeGradientWithColors(
                  const Color(0xFFFF6B6B),
                  const Color(0xFFFF8A80),
                  strength: 0.9,
                ),
                onTap: (canTakeQuiz &&
                        _hasUnlockedAdvancedModes &&
                        weakestCategory.isNotEmpty)
                    ? () async {
                        try {
                          final coverage =
                              _generateFocusModeCoverage(weakestCategory);
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
                badge: !canTakeQuiz
                    ? 'NO CREDITS'
                    : (_hasUnlockedAdvancedModes
                        ? null
                        : '$_lifetimeRandomQuizzesCompleted/$_advancedModeUnlockRequirement'),
                showReadyBadge: hasFocusReady,
                showFetchingBadge: isFocusFetching,
                isLocked: !canTakeQuiz ||
                    !_hasUnlockedAdvancedModes ||
                    weakestCategory.isEmpty,
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
                onTap: _hasSavedTestsData ? () => _startQuickPractice() : null,
                badge: _hasSavedTestsData ? null : 'LOCKED',
                isLocked: !_hasSavedTestsData,
              ),
              const SizedBox(height: 12),

              // 4. Challenge Mode
              _quizModeCard(
                icon: Icons.emoji_events_rounded,
                title: 'Challenge Mode',
                description:
                    'Advanced mixed-difficulty simulation • Does not count toward daily session objective',
                gradient: _modeFadeGradientWithColors(
                  Colors.amber,
                  Colors.orange,
                  strength: 0.86,
                ),
                onTap: (canTakeQuiz && _hasUnlockedAdvancedModes)
                    ? () => _startChallengeMode()
                    : null,
                badge: !canTakeQuiz
                    ? 'NO CREDITS'
                    : (_hasUnlockedAdvancedModes
                        ? null
                        : '$_lifetimeRandomQuizzesCompleted/$_advancedModeUnlockRequirement'),
                showReadyBadge: hasChallengeReady,
                showFetchingBadge: isChallengeFetching,
                isLocked: !canTakeQuiz || !_hasUnlockedAdvancedModes,
                showPremiumBanner: false,
              ),
              const SizedBox(height: 12),

              // 5. Load Saved Test
              if (_savedSessions.isNotEmpty)
                _quizModeCard(
                  icon: Icons.history_rounded,
                  title: 'Load Saved Test',
                  description:
                      '${_savedSessions.length} saved ${_savedSessions.length == 1 ? 'test' : 'tests'} available',
                  gradient: _modeFadeGradientWithColors(
                    Colors.blueGrey,
                    Colors.blue,
                    strength: 0.74,
                  ),
                  onTap: _showSavedTestsDialog,
                  badge: '${_savedSessions.length}',
                  isLocked: false,
                  showPremiumBanner: false,
                ),

              if (_savedSessions.isNotEmpty) const SizedBox(height: 24),

              const SizedBox(height: 24),

              // Recent Activity (if any quizzes taken) - moved after quiz modes
              if (totalQuizzesTaken > 0) ...[
                Text(
                  'RECENT ACTIVITY',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
            color: Colors.white.withValues(alpha: 0.6),
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
                color: Colors.white.withValues(alpha: 0.8),
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
    bool showReadyBadge = false,
    bool showFetchingBadge = false,
    bool isLocked = false,
    bool showPremiumBanner = false,
  }) {
    return InkWell(
      onTap: isLocked
          ? null
          : () {
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
                        Colors.grey.withValues(alpha: 0.3),
                        Colors.grey.withValues(alpha: 0.2),
                      ],
                    )
                  : gradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLocked
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.3),
                width: isPrimary ? 2 : 1,
              ),
              boxShadow: isPrimary && !isLocked
                  ? [
                      BoxShadow(
                        color: PnleTheme.accent.withValues(alpha: 0.3),
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
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_rounded : icon,
                    color: isLocked ? Colors.white54 : Colors.white,
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
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (!showPremiumBanner &&
                              (badge != null ||
                                  showReadyBadge ||
                                  showFetchingBadge))
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (badge != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.92),
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
                                if (showReadyBadge)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32)
                                          .withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Text(
                                      'READY',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                if (!showReadyBadge && showFetchingBadge)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1565C0)
                                          .withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Text(
                                      'FETCHING',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLocked
                            ? 'Complete more quizzes to unlock'
                            : description,
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLocked)
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
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
                      color: Colors.black.withValues(alpha: 0.3),
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
        from.withValues(alpha: 0.85 * s),
        to.withValues(alpha: 0.78 * s),
        Colors.white.withValues(alpha: 0.18 * s),
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
            PnleTheme.bgTop.withValues(alpha: 0.96),
            PnleTheme.bgBottom.withValues(alpha: 0.92),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: PnleTheme.accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: PnleTheme.accent,
        unselectedItemColor: Colors.white.withValues(alpha: 0.85),
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
                            color: PnleTheme.accent.withValues(alpha: 0.45),
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
  }

  Widget _dailyPerformanceScreen() {
    final categories = _categoriesForEligibility();
    final totalAvg = _calculateTotalAverage();
    final hasData =
        categoryScores.values.any((data) => (data['total'] as int) > 0);

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
                  color: Colors.white.withValues(alpha: 0.7),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PnleTheme.accent.withValues(alpha: 0.3),
                      PnleTheme.accent.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: PnleTheme.accent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.today_rounded,
                            color: PnleTheme.accent, size: 20),
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
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No data yet',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start your first quiz today to\ntrack your progress!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.5),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
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
                        const Color(0xFF34D399).withValues(alpha: 0.2),
                        const Color(0xFF34D399).withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insights,
                              color: Color(0xFF34D399), size: 20),
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
                  _performanceGroupHeader('Excellent Performance',
                      const Color(0xFF34D399), Icons.emoji_events_rounded),
                  const SizedBox(height: 8),
                  ...excellent.map((cat) => _categoryProgressEnhanced(cat)),
                  const SizedBox(height: 16),
                ],
                if (good.isNotEmpty) ...[
                  _performanceGroupHeader(
                      'Good Progress', Colors.amber, Icons.thumb_up_rounded),
                  const SizedBox(height: 8),
                  ...good.map((cat) => _categoryProgressEnhanced(cat)),
                  const SizedBox(height: 16),
                ],
                if (needsWork.isNotEmpty) ...[
                  _performanceGroupHeader('Needs Improvement',
                      const Color(0xFFFF6B6B), Icons.trending_up_rounded),
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
                    color: Colors.white.withValues(alpha: 0.7),
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
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
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
                  color: Colors.white.withValues(alpha: 0.8),
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
    final hasEnoughData =
        total >= 5; // Need at least 5 answers for meaningful trend

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
                          ? (trendUp
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFF6B6B))
                          : Colors.white38,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              (barColor ?? Colors.grey).withValues(alpha: 0.3),
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
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              color: barColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$correct/$total correct answers',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.7),
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
              Colors.white.withValues(alpha: 0.2),
              Colors.white.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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
    return _premiumHistoryScreen();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<Map<String, dynamic>> _buildTenDayActivity() {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final activity = <DateTime, Map<String, num>>{};

    for (int i = 9; i >= 0; i--) {
      final day = _dateOnly(now.subtract(Duration(days: i)));
      activity[day] = {
        'quizzes': 0,
        'questions': 0,
        'correct': 0,
        'percentSum': 0,
      };
    }

    for (final record in _quizActivityRecords) {
      final day = _dateOnly(record.date);
      if (!activity.containsKey(day)) continue;
      activity[day]!['quizzes'] = (activity[day]!['quizzes'] ?? 0) + 1;
      activity[day]!['questions'] =
          (activity[day]!['questions'] ?? 0) + record.questionCount;
      activity[day]!['correct'] =
          (activity[day]!['correct'] ?? 0) + record.correctCount;
      activity[day]!['percentSum'] =
          (activity[day]!['percentSum'] ?? 0) + record.scorePercent;
    }

    final todayData = activity[today];
    if (todayData != null &&
        (todayData['quizzes'] ?? 0) == 0 &&
        completedSessions > 0) {
      final fallbackQuestions = completedSessions * 15;
      final fallbackCorrect = categoryScores.values.fold<int>(
        0,
        (sum, value) => sum + ((value['correct'] as int?) ?? 0),
      );
      final fallbackPercent = fallbackQuestions > 0
          ? (fallbackCorrect / fallbackQuestions) * 100
          : 0.0;

      todayData['quizzes'] = completedSessions;
      todayData['questions'] = fallbackQuestions;
      todayData['correct'] = fallbackCorrect;
      todayData['percentSum'] = fallbackPercent * completedSessions;
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
            'percentSum': entry.value['percentSum'] ?? 0,
          },
        )
        .toList();
  }

  double _calculateDayOverallAverage(Map<String, dynamic> day) {
    final quizzes = day['quizzes'] as int;
    final questions = day['questions'] as int;
    final correct = day['correct'] as int;
    final percentSum = (day['percentSum'] as num?)?.toDouble() ?? 0;

    if (questions > 0) {
      return (correct / questions) * 100;
    }
    if (quizzes > 0) {
      return percentSum / quizzes;
    }
    return 0;
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
                        color: Colors.white.withValues(alpha: 0.7),
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
                    _build10DayStatItem('$activeDays', 'Active Days',
                        Icons.event_available_rounded),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _build10DayStatItem(
                        '$totalQuizzes', 'Quizzes', Icons.quiz_outlined),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _build10DayStatItem('$totalQuestions', 'Questions',
                        Icons.fact_check_outlined),
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
                          final date = day['date'] as DateTime;
                          final percentage = _calculateDayOverallAverage(day)
                              .clamp(0.0, 100.0);
                          return _buildChartBar(
                            percentage,
                            '${date.day}',
                            '${percentage.toStringAsFixed(0)}%',
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
                      final isComplete = quizzes >= 4; // Must complete 4 tests

                      // Calculate percentage and status
                      String statusText;
                      Color statusColor;
                      if (!hasActivity) {
                        statusText = 'No activity';
                        statusColor = Colors.white.withValues(alpha: 0.4);
                      } else if (!isComplete) {
                        // Show current overall average if not finished
                        final dayOverallAvg = _calculateDayOverallAverage(day);
                        statusText =
                            '${dayOverallAvg.toStringAsFixed(0)}% - UNFINISHED';
                        statusColor = const Color(0xFFFFA726);
                      } else {
                        // Show pass/fail only when 4 tests are complete
                        final dayOverallAvg = _calculateDayOverallAverage(day);
                        if (dayOverallAvg >= 80) {
                          statusText =
                              '${dayOverallAvg.toStringAsFixed(0)}% - Passed ✓';
                          statusColor = const Color(0xFF34D399);
                        } else {
                          statusText =
                              '${dayOverallAvg.toStringAsFixed(0)}% - Failed';
                          statusColor = const Color(0xFFFF6B6B);
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasActivity
                                ? statusColor.withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.14),
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
  Widget _buildChartBar(
    double percentage,
    String label,
    String percentLabel,
    bool unlocked,
  ) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            percentLabel,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: unlocked
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 4),
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
                        Colors.grey.withValues(alpha: 0.3),
                        Colors.grey.withValues(alpha: 0.2),
                      ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: unlocked
                  ? Colors.white.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.3),
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
          color: PnleTheme.accent.withValues(alpha: 0.8),
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
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressInsights(List<Map<String, dynamic>> tenDayActivity) {
    // Check if there's any test data at all
    final totalQuizzesAll = tenDayActivity.fold<int>(
        0, (sum, day) => sum + (day['quizzes'] as int));

    // If no test data, show a placeholder message
    if (totalQuizzesAll == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.trending_up_rounded,
              color: Colors.white.withValues(alpha: 0.5),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'No progress data yet',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Complete your first quiz to see your progress analysis',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    // Divide into first 5 days and last 5 days
    final firstHalf = tenDayActivity.take(5).toList();
    final secondHalf = tenDayActivity.skip(5).toList();

    final firstHalfQuizzes =
        firstHalf.fold<int>(0, (sum, day) => sum + (day['quizzes'] as int));
    final secondHalfQuizzes =
        secondHalf.fold<int>(0, (sum, day) => sum + (day['quizzes'] as int));

    final firstHalfActiveDays =
        firstHalf.where((day) => (day['quizzes'] as int) > 0).length;
    final secondHalfActiveDays =
        secondHalf.where((day) => (day['quizzes'] as int) > 0).length;

    // Calculate percentage change
    final quizzesChange = firstHalfQuizzes > 0
        ? ((secondHalfQuizzes - firstHalfQuizzes) / firstHalfQuizzes * 100)
            .toStringAsFixed(1)
        : '0.0';

    final isImproving = secondHalfQuizzes >= firstHalfQuizzes;
    final trendIcon =
        isImproving ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final trendColor =
        isImproving ? const Color(0xFF34D399) : const Color(0xFFFF6B6B);

    return Column(
      children: [
        // First vs Second Half Comparison
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'First 5 Days',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
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
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$firstHalfActiveDays active days',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
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
                  color: trendColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: trendColor.withValues(alpha: 0.3)),
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
                            color: trendColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$secondHalfActiveDays active days',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: trendColor.withValues(alpha: 0.6),
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
            color: trendColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: trendColor.withValues(alpha: 0.3)),
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
                      isImproving
                          ? '📈 You\'re improving!'
                          : '📉 Slight decrease',
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
                        color: trendColor.withValues(alpha: 0.8),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      (barColor ?? Colors.grey).withValues(alpha: 0.8),
                      (barColor ?? Colors.grey).withValues(alpha: 0.6),
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
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor:
                  AlwaysStoppedAnimation<Color>(barColor ?? Colors.grey),
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
                color: trailingColor ?? Colors.white.withValues(alpha: 0.8),
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
      return PnleTheme.danger.withValues(alpha: 0.82);
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
    !isFocusMode && _coverageMatchesCachedRandom(coverage);

    // Store focus mode parameters
    _isFocusMode = isFocusMode;
    _focusCategory = focusCategory;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
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
                      PnleTheme.bgTop.withValues(alpha: 0.95),
                      PnleTheme.bgBottom.withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isFocusMode
                        ? const Color(0xFFFF6B6B).withValues(alpha: 0.6)
                        : PnleTheme.accent.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isFocusMode
                          ? const Color(0xFFFF6B6B).withValues(alpha: 0.3)
                          : PnleTheme.accent.withValues(alpha: 0.3),
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
                                const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                                const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFFF6B6B)
                                  .withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6B6B)
                                    .withValues(alpha: 0.2),
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
                                  color: const Color(0xFFFF6B6B)
                                      .withValues(alpha: 0.3),
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
                      ...coverage.entries.map((e) => _coverageItem(
                          e.key, e.value,
                          isFocusMode: isFocusMode,
                          focusCategory: focusCategory)),
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
                              color: PnleTheme.accent.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!_isOnline) {
                              showDialog<void>(
                                context: dialogContext,
                                barrierColor: Colors.black87,
                                builder: (_) => AlertDialog(
                                  backgroundColor: PnleTheme.bgTop,
                                  title: Text(
                                    'Internet Required',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  content: Text(
                                    'Please reconnect to the internet before creating a test.',
                                    style: GoogleFonts.outfit(
                                      color:
                                          Colors.white.withValues(alpha: 0.88),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: Text(
                                        'OK',
                                        style: GoogleFonts.outfit(
                                          color: PnleTheme.accent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            if (remainingFreeTests <= 0) {
                              await showDialog<void>(
                                context: dialogContext,
                                barrierColor: Colors.black87,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 12, sigmaY: 12),
                                      child: Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              PnleTheme.bgTop
                                                  .withValues(alpha: 0.96),
                                              PnleTheme.bgBottom
                                                  .withValues(alpha: 0.93),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          border: Border.all(
                                            color: const Color(0xFFFFB74D)
                                                .withValues(alpha: 0.65),
                                            width: 1.6,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFFB74D)
                                                  .withValues(alpha: 0.25),
                                              blurRadius: 16,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Color(0xFFFFB74D),
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'No Session Credits',
                                                    style: GoogleFonts.outfit(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'No session credits left. Watch an ad or claim streak rewards to continue.',
                                              style: GoogleFonts.outfit(
                                                color: Colors.white
                                                    .withValues(alpha: 0.88),
                                                height: 1.4,
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: ElevatedButton(
                                                onPressed: () => Navigator.pop(
                                                    dialogContext),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      PnleTheme.accent,
                                                  foregroundColor:
                                                      PnleTheme.bgBottom,
                                                ),
                                                child: Text(
                                                  'OK',
                                                  style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }

                            if (!mounted) return;

                            // Close coverage dialog first, then open generation dialog on next frame.
                            Navigator.of(dialogContext).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _showGenerationDialog(
                                modeLabel: isFocusMode
                                    ? 'FOCUS MODE${focusCategory != null ? ' • $focusCategory' : ''}'
                                    : 'RANDOM QUIZ',
                              );
                            });
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
                            color: Colors.white.withValues(alpha: 0.8),
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

  Widget _coverageItem(String category, String topic,
      {bool isFocusMode = false, String? focusCategory}) {
    final isFocusCategory = isFocusMode && category == focusCategory;
    final accentColor =
        isFocusMode ? const Color(0xFFFF6B6B) : PnleTheme.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isFocusCategory
            ? LinearGradient(
                colors: [
                  const Color(0xFFFF6B6B).withValues(alpha: 0.25),
                  const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.08),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocusCategory
              ? const Color(0xFFFF6B6B).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.25),
          width: isFocusCategory ? 2 : 1,
        ),
        boxShadow: isFocusCategory
            ? [
                BoxShadow(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.2),
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
              color: accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.4),
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
                          color: Colors.white.withValues(alpha: 0.9),
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

    final language = _currentTestCoverage!['Language Proficiency'] ??
        'General language proficiency topics';
    final reading = _currentTestCoverage!['Reading Comprehension'] ??
        'General reading comprehension topics';
    final mathematics =
        _currentTestCoverage!['Mathematics'] ?? 'General mathematics topics';
    final science =
        _currentTestCoverage!['Science'] ?? 'General science topics';

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

    return _buildFastPromptFromCoverage(_currentTestCoverage!);
  }

  String _buildFastPromptFromCoverage(Map<String, String> coverage) {
    final language = coverage['Language Proficiency'] ??
        'General language proficiency topics';
    final reading = coverage['Reading Comprehension'] ??
        'General reading comprehension topics';
    final mathematics = coverage['Mathematics'] ?? 'General mathematics topics';
    final science = coverage['Science'] ?? 'General science topics';

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
    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();

    // Focus mode creates 10 questions from the focus category, 5 from others
    String distribution = '';
    int questionNumber = 1;

    // 10 questions from focus category
    distribution +=
        '- Questions $questionNumber–${questionNumber + 9}: $focusCategory - $focusTopic.\n';
    questionNumber += 10;

    // 5 questions from other categories
    for (int i = 0; i < otherCategories.length && questionNumber <= 15; i++) {
      final cat = otherCategories[i];
      final topic = _currentTestCoverage![cat] ?? 'General topics';
      final questionsInCat =
          (15 - questionNumber + 1) ~/ (otherCategories.length - i);
      final endQuestion = questionNumber + questionsInCat - 1;

      if (questionsInCat == 1) {
        distribution += '- Question $questionNumber: $cat - $topic.\n';
      } else {
        distribution +=
            '- Questions $questionNumber–$endQuestion: $cat - $topic.\n';
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
        _pickRandomKeyArea(focusCategory);

    final categories = _categoriesForEligibility();
    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();
    final otherText = otherCategories.map((cat) {
      final topic = _currentTestCoverage?[cat] ?? _pickRandomKeyArea(cat);
      return '$cat: $topic';
    }).join(' | ');

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
        ? keyAreas[focusCategory]![
            Random().nextInt(keyAreas[focusCategory]!.length)]
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
        ? keyAreas[focusCategory]![
            Random().nextInt(keyAreas[focusCategory]!.length)]
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
    final focusTopic = _pickRandomKeyArea(focusCategory);
    final categories = _categoriesForEligibility();
    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();

    // Build distribution string for questions 7-10 (other categories)
    String otherCategoriesDistribution = '';
    if (otherCategories.length == 1) {
      final cat = otherCategories[0];
      final topic = _pickRandomKeyArea(cat);
      otherCategoriesDistribution =
          '- Questions 7–10: $cat - $topic (ADVANCED/DIFFICULT)';
    } else if (otherCategories.length == 2) {
      final cat1 = otherCategories[0];
      final cat2 = otherCategories[1];
      final topic1 = _pickRandomKeyArea(cat1);
      final topic2 = _pickRandomKeyArea(cat2);
      otherCategoriesDistribution =
          '- Questions 7–8: $cat1 - $topic1 (ADVANCED/DIFFICULT)\n- Questions 9–10: $cat2 - $topic2 (ADVANCED/DIFFICULT)';
    } else if (otherCategories.length == 3) {
      final cat1 = otherCategories[0];
      final cat2 = otherCategories[1];
      final cat3 = otherCategories[2];
      final topic1 = _pickRandomKeyArea(cat1);
      final topic2 = _pickRandomKeyArea(cat2);
      final topic3 = _pickRandomKeyArea(cat3);
      otherCategoriesDistribution =
          '- Question 7: $cat1 - $topic1 (ADVANCED/DIFFICULT)\n- Question 8: $cat2 - $topic2 (ADVANCED/DIFFICULT)\n- Questions 9–10: $cat3 - $topic3 (ADVANCED/DIFFICULT)';
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
    final focusTopic = _pickRandomKeyArea(focusCategory);
    final categories = _categoriesForEligibility();
    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();
    final otherText = otherCategories.map((cat) {
      final topic = _pickRandomKeyArea(cat);
      return '$cat: $topic';
    }).join(' | ');

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

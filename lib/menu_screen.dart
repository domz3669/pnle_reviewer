import 'dart:math';
import 'dart:async';
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
import 'models/acet_assessment.dart';
import 'models/question.dart';
import 'models/pnle_key_areas.dart';
import 'services/question_generation_service.dart';
import 'services/deepseek_service.dart';
import 'services/exam_driven_config_service.dart';
import 'services/seed_question_pool_service.dart';
import 'services/acet_assessment_service.dart';
import 'services/local_visual_question_service.dart';
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
            .map(
              (q) => {
                'number': q.number,
                'category': q.category,
                'question': q.question,
                'imageAssetPath': q.imageAssetPath,
                'choices': q.choices,
                'answer': q.answer,
                'explanation': q.explanation,
                'source': q.source,
              },
            )
            .toList(),
      };

  static _SavedSession? fromJson(Map<String, dynamic> json) {
    final rawQuestions = json['questions'];
    if (rawQuestions is! List || rawQuestions.isEmpty) return null;

    final parsedQuestions = <Question>[];
    for (final item in rawQuestions) {
      if (item is! Map) continue;
      parsedQuestions.add(Question.fromJson(Map<String, dynamic>.from(item)));
    }
    if (parsedQuestions.isEmpty) return null;

    DateTime parsedSavedAt;
    final rawSavedAt = json['savedAt'];
    if (rawSavedAt is String) {
      parsedSavedAt = DateTime.tryParse(rawSavedAt) ?? DateTime.now();
    } else {
      parsedSavedAt = DateTime.now();
    }

    final rawTitle = json['title'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : 'Saved Session';

    final rawSourceMode = json['sourceMode'];
    final sourceMode =
        rawSourceMode is String && rawSourceMode.trim().isNotEmpty
            ? rawSourceMode.trim()
            : 'randomQuiz';

    return _SavedSession(
      title: title,
      questions: parsedQuestions,
      savedAt: parsedSavedAt,
      sourceMode: sourceMode,
    );
  }

  _SavedSession copyWith({
    String? title,
    List<Question>? questions,
    DateTime? savedAt,
    String? sourceMode,
  }) {
    return _SavedSession(
      title: title ?? this.title,
      questions: questions ?? this.questions,
      savedAt: savedAt ?? this.savedAt,
      sourceMode: sourceMode ?? this.sourceMode,
    );
  }
}

class _QuizActivityRecord {
  final DateTime date;
  final String mode;
  final int questionCount;
  final int correctCount;
  final double scorePercent;
  final int elapsedSeconds;
  final int timedOutCount;
  final Map<String, int> categoryCorrect;
  final Map<String, int> categoryTotal;
  final AcetAssessment? assessment;

  const _QuizActivityRecord({
    required this.date,
    this.mode = 'randomQuiz',
    required this.questionCount,
    required this.correctCount,
    required this.scorePercent,
    this.elapsedSeconds = 0,
    this.timedOutCount = 0,
    this.categoryCorrect = const <String, int>{},
    this.categoryTotal = const <String, int>{},
    this.assessment,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'mode': mode,
        'questionCount': questionCount,
        'correctCount': correctCount,
        'scorePercent': scorePercent,
        'elapsedSeconds': elapsedSeconds,
        'timedOutCount': timedOutCount,
        'categoryCorrect': categoryCorrect,
        'categoryTotal': categoryTotal,
        'assessment': assessment?.toJson(),
      };

  static _QuizActivityRecord? fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'] ?? json['d'];
    final modeRaw = json['mode'] ?? json['m'];
    final questionRaw = json['questionCount'] ?? json['q'];
    final correctRaw = json['correctCount'] ?? json['c'];
    final scoreRaw = json['scorePercent'] ?? json['p'];
    final elapsedRaw = json['elapsedSeconds'] ?? json['e'];
    final timedOutRaw = json['timedOutCount'] ?? json['t'];
    final categoryCorrectRaw = json['categoryCorrect'] ?? json['cc'];
    final categoryTotalRaw = json['categoryTotal'] ?? json['ct'];
    final assessmentRaw = json['assessment'] ?? json['a'];
    if (dateRaw is! String || questionRaw is! num) return null;

    final parsedDate = DateTime.tryParse(dateRaw);
    if (parsedDate == null) return null;

    final parsedCategoryCorrect = <String, int>{};
    if (categoryCorrectRaw is Map) {
      for (final entry in categoryCorrectRaw.entries) {
        if (entry.key is String && entry.value is num) {
          parsedCategoryCorrect[entry.key as String] =
              (entry.value as num).toInt();
        }
      }
    }

    final parsedCategoryTotal = <String, int>{};
    if (categoryTotalRaw is Map) {
      for (final entry in categoryTotalRaw.entries) {
        if (entry.key is String && entry.value is num) {
          parsedCategoryTotal[entry.key as String] =
              (entry.value as num).toInt();
        }
      }
    }

    return _QuizActivityRecord(
      date: parsedDate,
      mode: modeRaw is String && modeRaw.trim().isNotEmpty
          ? modeRaw.trim()
          : 'randomQuiz',
      questionCount: questionRaw.toInt(),
      correctCount: (correctRaw is num) ? correctRaw.toInt() : 0,
      scorePercent: (scoreRaw is num) ? scoreRaw.toDouble() : 0,
      elapsedSeconds: (elapsedRaw is num) ? elapsedRaw.toInt() : 0,
      timedOutCount: (timedOutRaw is num) ? timedOutRaw.toInt() : 0,
      categoryCorrect: parsedCategoryCorrect,
      categoryTotal: parsedCategoryTotal,
      assessment: assessmentRaw is Map
          ? AcetAssessment.fromJson(Map<String, dynamic>.from(assessmentRaw))
          : null,
    );
  }
}

class _MistakeRecord {
  final Question question;
  final String? selectedAnswer;
  final bool timedOut;
  final DateTime timestamp;

  const _MistakeRecord({
    required this.question,
    required this.selectedAnswer,
    required this.timedOut,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'question': {
          'number': question.number,
          'category': question.category,
          'question': question.question,
          'imageAssetPath': question.imageAssetPath,
          'choices': question.choices,
          'answer': question.answer,
          'explanation': question.explanation,
          'source': question.source,
        },
        'selectedAnswer': selectedAnswer,
        'timedOut': timedOut,
        'timestamp': timestamp.toIso8601String(),
      };

  static _MistakeRecord? fromJson(Map<String, dynamic> json) {
    final questionRaw = json['question'];
    final timedOutRaw = json['timedOut'];
    final timestampRaw = json['timestamp'];
    if (questionRaw is! Map ||
        timedOutRaw is! bool ||
        timestampRaw is! String) {
      return null;
    }

    final question = Question.fromJson(Map<String, dynamic>.from(questionRaw));
    final timestamp = DateTime.tryParse(timestampRaw);
    if (timestamp == null) return null;

    final selectedRaw = json['selectedAnswer'];
    return _MistakeRecord(
      question: question,
      selectedAnswer: selectedRaw is String ? selectedRaw : null,
      timedOut: timedOutRaw,
      timestamp: timestamp,
    );
  }
}

class _PausedQuizSession {
  final List<Question> questions;
  final int currentIndex;
  final Map<String, int> correctCount;
  final int elapsedSeconds;
  final String testMode;
  final bool recordResults;
  final DateTime pausedAt;
  final List<AcetQuestionAttempt> assessmentAttempts;

  const _PausedQuizSession({
    required this.questions,
    required this.currentIndex,
    required this.correctCount,
    required this.elapsedSeconds,
    required this.testMode,
    required this.recordResults,
    required this.pausedAt,
    this.assessmentAttempts = const <AcetQuestionAttempt>[],
  });

  Map<String, dynamic> toJson() => {
        'questions': questions
            .map((q) => {
                  'number': q.number,
                  'category': q.category,
                  'question': q.question,
                  'imageAssetPath': q.imageAssetPath,
                  'choices': q.choices,
                  'answer': q.answer,
                  'explanation': q.explanation,
                  'source': q.source,
                })
            .toList(),
        'currentIndex': currentIndex,
        'correctCount': correctCount,
        'elapsedSeconds': elapsedSeconds,
        'testMode': testMode,
        'recordResults': recordResults,
        'pausedAt': pausedAt.toIso8601String(),
        'assessmentAttempts':
            assessmentAttempts.map((attempt) => attempt.toJson()).toList(),
      };

  static _PausedQuizSession? fromJson(Map<String, dynamic> json) {
    final questionsRaw = json['questions'];
    final indexRaw = json['currentIndex'];
    final correctRaw = json['correctCount'];
    final elapsedRaw = json['elapsedSeconds'];
    final modeRaw = json['testMode'];
    final recordRaw = json['recordResults'];
    final pausedAtRaw = json['pausedAt'];
    final attemptsRaw = json['assessmentAttempts'];

    if (questionsRaw is! List ||
        indexRaw is! num ||
        correctRaw is! Map ||
        elapsedRaw is! num ||
        modeRaw is! String ||
        recordRaw is! bool) {
      return null;
    }

    final questions = questionsRaw
        .whereType<Map>()
        .map((item) => Question.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    if (questions.isEmpty) return null;

    final correctCount = <String, int>{};
    for (final entry in correctRaw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is num) {
        correctCount[key] = value.toInt();
      }
    }

    final idx = indexRaw.toInt().clamp(0, questions.length - 1);
    final pausedAt = pausedAtRaw is String
        ? (DateTime.tryParse(pausedAtRaw) ?? DateTime.now())
        : DateTime.now();
    final attempts = <AcetQuestionAttempt>[];
    if (attemptsRaw is List) {
      for (final item in attemptsRaw) {
        if (item is Map) {
          attempts.add(
            AcetQuestionAttempt.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return _PausedQuizSession(
      questions: questions,
      currentIndex: idx,
      correctCount: correctCount,
      elapsedSeconds: elapsedRaw.toInt(),
      testMode: modeRaw,
      recordResults: recordRaw,
      pausedAt: pausedAt,
      assessmentAttempts: attempts,
    );
  }

  _PausedQuizSession copyWith({
    List<Question>? questions,
    int? currentIndex,
    Map<String, int>? correctCount,
    int? elapsedSeconds,
    String? testMode,
    bool? recordResults,
    DateTime? pausedAt,
    List<AcetQuestionAttempt>? assessmentAttempts,
  }) {
    return _PausedQuizSession(
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      correctCount: correctCount ?? this.correctCount,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      testMode: testMode ?? this.testMode,
      recordResults: recordResults ?? this.recordResults,
      pausedAt: pausedAt ?? this.pausedAt,
      assessmentAttempts: assessmentAttempts ?? this.assessmentAttempts,
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  // Change this for future exam clones when reusing the app shell.
  static const String _activeExamId = 'acet';
  static const String _defaultVisualAbstractAssetPath =
      'assets/Abstract Reasoning/visual_abstract_questions.json';
  static const String _usedVisualAbstractPoolIdsPrefsKey =
      'usedVisualAbstractPoolIds';

  final ExamDrivenConfigService _examConfigService =
      ExamDrivenConfigService.instance;
  final AcetAssessmentService _acetAssessmentService =
      const AcetAssessmentService();
  final LocalVisualQuestionService _localVisualQuestionService =
      const LocalVisualQuestionService();

  // =========================
  // STATE
  // =========================
  int currentScreen = 0; // 0=Home, 1=Daily, 2=Quiz, 3=History, 4=Settings
  String programInterest = 'General ACET';
  static const String _selectedProgramInterestPrefsKey =
      'selected_program_interest';
  static const String _hasChosenProgramInterestPrefsKey =
      'has_chosen_program_interest';
  static const List<String> _acetStudyPreferences = [
    'General ACET',
    'English Priority',
    'Mathematics Priority',
    'Logical Reasoning Priority',
    'Mental Ability Priority',
  ];
  static const Map<String, int> _acetReadinessThresholds = {
    'English': 65,
    'Mathematics': 65,
    'Logical Reasoning': 65,
    'Mental Ability / Abstract': 65,
  };
  bool hasUnlimitedAccess = false;
  bool hasGraceAccess = false;
  DateTime? graceAccessEndDate;
  // Daily tracking
  int completedSessions = 0; // Out of daily target per day
  int remainingFreeTests =
      4; // Firebase-synced daily counter (fallback default)
  int _extraSessionAdChances = 2;
  DateTime? _nextExtraSessionAdRefillAt;
  static const int _maxExtraSessionAdChances = 2;
  static const Duration _extraSessionAdRefillDuration = Duration(hours: 2);
  Timer? _extraSessionAdRefillTicker;
  int _zeroAdSessionsRemaining = 4; // First daily-target sessions are ad-free
  bool _isLoadingDailyFreeTests = true;
  bool _isLoadingDailyTaskRewards = true;
  String? _lastStreakRewardClaimDate;
  int _dailyTaskSessionsCompleted = 0;
  bool _dailyTaskHighScoreAchieved = false;
  int _dailyTaskFocusCompleted = 0;
  int _dailyTaskChallengeCompleted = 0;
  int _dailyTaskTimedCompleted = 0;
  int _dailyTaskQuestionsAnswered = 0;
  String? _lastEightSessionRewardClaimDate;
  String? _lastHighScoreRewardClaimDate;
  String? _lastFocusRewardClaimDate;
  String? _lastChallengeRewardClaimDate;
  String? _lastTimedExamRewardClaimDate;
  String? _lastThirtyAnswersRewardClaimDate;

  // Accumulated stats (never reset, shows lifetime totals)
  int accumulatedQuizzesCompleted = 0;
  int accumulatedQuestionsAnswered = 0;
  int _lifetimeRandomQuizzesCompleted = 0;
  static const int _advancedModeUnlockRequirement = 0;

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
            'https://acet-reviewer-default-rtdb.asia-southeast1.firebasedatabase.app/',
      );

  // Category scoring targets across daily target sessions.
  Map<String, Map<String, dynamic>> categoryScores = {
    'English': {'correct': 0, 'total': 16, 'weight': 0.25},
    'Mathematics': {'correct': 0, 'total': 16, 'weight': 0.25},
    'Logical Reasoning': {'correct': 0, 'total': 16, 'weight': 0.25},
    'Mental Ability / Abstract': {'correct': 0, 'total': 16, 'weight': 0.25},
  };

  late List<Question> _generatedQuestions;
  Map<String, String>? _currentTestCoverage; // Stores selected key areas
  final List<_SavedSession> _savedSessions = [];
  static const int _maxSavedSessions = 30;
  static const String _savedSessionsPrefsKey = 'savedSessionsPayload';
  bool _isLoadingSavedSessions = true;
  final List<_MistakeRecord> _mistakeQueue = [];
  static const int _maxMistakeQueue = 50;
  static const String _mistakeQueuePrefsKey = 'mistakeQueuePayload';
  bool _isLoadingMistakeQueue = true;
  final Map<String, _PausedQuizSession> _pausedQuizSessions = {};
  static const String _pausedQuizSessionPrefsKey = 'pausedQuizSessionsPayload';
  bool _isLoadingPausedQuizSessions = true;
  final List<_QuizActivityRecord> _quizActivityRecords = [];
  static const int _maxQuizActivityRecords = 120;
  static const int _quizActivityRetentionDays = 45;

  // Daily generation limits (access-enabled only)
  int _dailyGenerationSessionsUsed = 0;
  int _dailyGenerationQuestionsUsed = 0;
  String? _lastGenerationResetDate; // Format: yyyy-MM-dd

  // Focus mode state
  bool _isFocusMode = false;
  String? _focusCategory;
  bool _usedCachedRandomForLastGeneration = false;
  bool _isStartingGeneratedSession = false;
  String _activeGenerationMode = 'randomQuiz';
  DateTime? _lastSessionConsumeAt;
  bool _isPrimingChallengeCache = false;
  Completer<void>? _challengePrimeCompleter;
  bool _isLaunchingChallengeMode = false;
  final SeedQuestionPoolService _seedPoolService = SeedQuestionPoolService();
  bool _seedPoolReady = false;
  bool _isRefillingSeedPool = false;
  bool _poolWarmupChecked = false;
  bool _poolWarmupComplete = false;
  int _poolWarmupReadyBuckets = 0;
  bool _showPoolWarmupIndicator = true;
  static const String _poolWarmupIndicatorDismissedPrefsKey =
      'poolWarmupIndicatorDismissed';
  final Map<String, List<Question>> _cachedFocusQuestions = {};
  final Map<String, String> _lastPickedKeyAreaByCategory = {};
  final Map<String, List<String>> _recentKeyAreasByCategory = {};
  static const int _recentKeyAreaWindow = 5;
  List<Question>? _cachedRandomQuizQuestions;
  Map<String, String>? _cachedRandomQuizCoverage;
  List<Question>? _cachedChallengeQuestions;
  List<Question>? _visualAbstractQuestionPool;
  final Set<String> _usedVisualAbstractPoolIds = <String>{};
  bool _usedVisualAbstractPoolLoaded = false;
  static const String _randomQuizCachePrefsKey = 'cachedRandomQuizPayload';
  static const String _focusCachePrefsKey = 'cachedFocusQuizPayload';
  static const String _challengeCachePrefsKey = 'cachedChallengeQuizPayload';
  // bool _hasChosenProgramInterest = false; // Removed - not currently used
  bool _showFirstTimeFlow = false;
  String _nickname = '';
  bool _muteAllSounds = false;
  bool _notificationsEnabled = false;
  bool _strictTimingEnabled = false;

  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  InterstitialAd? _menuInterstitialAd;

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  Map<String, List<String>> get keyAreas => pnleKeyAreas;

  String _pickRandomKeyArea(
    String category, {
    bool avoidImmediateRepeat = true,
  }) {
    final topics = keyAreas[category];
    if (topics == null || topics.isEmpty) {
      debugPrint('Warning: No topics found for category: $category');
      return 'General topics';
    }

    if (!avoidImmediateRepeat || topics.length <= 1) {
      final picked = topics[Random().nextInt(topics.length)];
      _lastPickedKeyAreaByCategory[category] = picked;
      final history = _recentKeyAreasByCategory.putIfAbsent(
        category,
        () => <String>[],
      );
      history.add(picked);
      while (history.length > _recentKeyAreaWindow) {
        history.removeAt(0);
      }
      return picked;
    }

    final lastPicked = _lastPickedKeyAreaByCategory[category];
    final recent = _recentKeyAreasByCategory[category] ?? const <String>[];
    final pool = topics
        .where((topic) => topic != lastPicked && !recent.contains(topic))
        .toList();
    final source = pool.isNotEmpty ? pool : topics;
    final picked = source[Random().nextInt(source.length)];

    final history = _recentKeyAreasByCategory.putIfAbsent(
      category,
      () => <String>[],
    );
    history.add(picked);
    while (history.length > _recentKeyAreaWindow) {
      history.removeAt(0);
    }

    _lastPickedKeyAreaByCategory[category] = picked;
    return picked;
  }

  int _dailyTargetTotalForCategory(String category) {
    return 16;
  }

  double _defaultWeightForCategory(String category) {
    return 0.25;
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

  int get _dailySessionTarget =>
      _examConfigService.getExamConfig(_activeExamId)?.dailySessionTarget ?? 4;

  bool get _canClaimStreakRewardToday =>
      !_isLoadingDailyTaskRewards &&
      completedSessions >= _dailySessionTarget &&
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
    remainingFreeTests = _dailySessionTarget;
    _zeroAdSessionsRemaining = _dailySessionTarget;
    unawaited(_examConfigService.ensureLoaded());
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
    _loadPoolWarmupIndicatorPref();
    _loadPersonalizationPrefs();
    _checkOnboarding();

    // Kick off pre-generation immediately so first-time users can warm caches
    // even while RTDB restore/network permission prompts are in progress.
    _kickoffInitialPregenerationWarmup();
    unawaited(_initializeSeedPool());

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
      _loadDailyTaskRewardState();
      _loadCategoryScores();
      _loadMistakeQueue();
      _loadPausedQuizSession();
      _loadZeroAdSessions();
      _resetDailyCategoryScoresIfNeeded();
      unawaited(_primeMissingCachesAsNeeded());
      unawaited(_promptNicknameIfMissing());
    });
  }

  Future<void> _primeMissingCachesAsNeeded() async {
    await _ensureSeedPoolReadyForGeneration();
    if (!_seedPoolReady) return;
    unawaited(_refillSeedPoolsIfNeeded());
    unawaited(_refreshPoolWarmupStatus());
  }

  Future<void> _initializeSeedPool() async {
    try {
      await _seedPoolService.ensureInitialized();
      if (!mounted) return;
      setState(() {
        _seedPoolReady = true;
      });
      unawaited(_refreshPoolWarmupStatus());
      unawaited(_refillSeedPoolsIfNeeded());
    } catch (e) {
      debugPrint('Seed pool initialization skipped: $e');
    }
  }

  Future<void> _loadPoolWarmupIndicatorPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed =
          prefs.getBool(_poolWarmupIndicatorDismissedPrefsKey) ?? false;
      if (!mounted) {
        _showPoolWarmupIndicator = !dismissed;
        return;
      }
      setState(() {
        _showPoolWarmupIndicator = !dismissed;
      });
    } catch (e) {
      debugPrint('Unable to load pool warmup indicator pref: $e');
    }
  }

  Future<void> _dismissPoolWarmupIndicator() async {
    setState(() {
      _showPoolWarmupIndicator = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_poolWarmupIndicatorDismissedPrefsKey, true);
    } catch (e) {
      debugPrint('Unable to persist pool warmup indicator pref: $e');
    }
  }

  Future<void> _refreshPoolWarmupStatus() async {
    if (!_seedPoolReady) return;

    final categories = _categoriesForProgramInterest();
    final totalBuckets =
        categories.length * 4; // random, focus, challenge, timed

    try {
      final deficits =
          await _seedPoolService.getDeficits(threshold: 29, targetSize: 30);
      final missingBuckets = deficits.values.where((value) => value > 0).length;
      final readyBuckets =
          (totalBuckets - missingBuckets).clamp(0, totalBuckets);
      final complete = missingBuckets == 0;

      if (!mounted) {
        _poolWarmupChecked = true;
        _poolWarmupReadyBuckets = readyBuckets;
        _poolWarmupComplete = complete;
        return;
      }

      setState(() {
        _poolWarmupChecked = true;
        _poolWarmupReadyBuckets = readyBuckets;
        _poolWarmupComplete = complete;
      });
    } catch (e) {
      debugPrint('Unable to refresh pool warmup status: $e');
      if (!mounted) {
        _poolWarmupChecked = true;
        return;
      }
      setState(() {
        _poolWarmupChecked = true;
      });
    }
  }

  void _kickoffInitialPregenerationWarmup() {
    // Keep startup warmup focused on local seed-pool readiness/refill only.
    unawaited(_primeMissingCachesAsNeeded());

    // Retry shortly after startup to catch cases where network permission dialogs
    // delay early refill calls on first app open (notably iOS first launch).
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
  // APP LIFECYCLE â€” SYNC ON BACKGROUND
  // =========================
  /// Fires when user presses Home button (paused) or app is being killed (detached).
  /// We flush all progress to RTDB immediately so nothing is lost
  /// even if the user clears recent apps right after.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      debugPrint('App going to background ($state) - flushing data...');
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
              'https://acet-reviewer-default-rtdb.asia-southeast1.firebasedatabase.app/.json',
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

  DateTime _currentClockTime() {
    return _serverNow();
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _dateKeyFor(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  DateTime _currentDayStart() {
    return _startOfDay(_currentClockTime());
  }

  bool _isSameCalendarDay(DateTime left, DateTime right) {
    return _startOfDay(left).isAtSameMomentAs(_startOfDay(right));
  }

  bool _isBeforeCurrentDay(DateTime value) {
    return _currentDayStart().isAfter(_startOfDay(value));
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

  void _showOfflineProgressSavedMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$message Saved on this device and will sync when you reconnect.',
          style: GoogleFonts.outfit(),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
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
            _promptCourseTargetIfNeeded();
          },
        ),
      );
      if (!mounted) return;
      setState(() => showOnboarding = true);
    }
  }

  Future<void> _loadPersonalizationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyHasChosenProgramInterest =
        prefs.getBool('has_chosen_eligibility');
    final legacySavedProgramInterest = prefs.getString('selected_eligibility');
    final hasChosenProgramInterest =
        prefs.getBool(_hasChosenProgramInterestPrefsKey) ??
            legacyHasChosenProgramInterest ??
            false;
    final savedProgramInterest =
        prefs.getString(_selectedProgramInterestPrefsKey) ??
            legacySavedProgramInterest;
    final normalizedProgramInterest =
        _normalizeSpecialization(savedProgramInterest);

    if (!mounted) return;
    setState(() {
      _nickname = _normalizeNickname(prefs.getString('user_nickname') ?? '');
      _muteAllSounds = prefs.getBool('mute_all_sounds') ?? false;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
      _strictTimingEnabled = prefs.getBool('strict_timing_enabled') ?? false;
      programInterest = normalizedProgramInterest;
      _showFirstTimeFlow = !hasChosenProgramInterest;
    });
    await SoundService().setMuted(_muteAllSounds);
    if (_notificationsEnabled) {
      await _syncNotificationSchedules();
    }
    if (legacyHasChosenProgramInterest != null ||
        legacySavedProgramInterest != null) {
      await prefs.setString(
        _selectedProgramInterestPrefsKey,
        normalizedProgramInterest,
      );
      await prefs.setBool(
        _hasChosenProgramInterestPrefsKey,
        hasChosenProgramInterest,
      );
      await _removeLegacyEligibilityPrefs(prefs);
    }
    _promptCourseTargetIfNeeded();
  }

  Future<void> _removeLegacyEligibilityPrefs(SharedPreferences prefs) async {
    await prefs.remove('selected_eligibility');
    await prefs.remove('has_chosen_eligibility');
  }

  void _promptCourseTargetIfNeeded() {
    // ACET readiness should not require a study preference before practice.
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

  String _normalizeNickname(String nickname) {
    final normalized = nickname.trim();
    if (normalized.isEmpty) return '';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }

  Future<void> _saveNickname(String nickname) async {
    final normalized = _normalizeNickname(nickname);
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

  Future<void> _setStrictTimingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('strict_timing_enabled', enabled);
    if (!mounted) return;
    setState(() {
      _strictTimingEnabled = enabled;
    });
  }

  Future<void> _promptNicknameIfMissing() async {
    if (!mounted) return;
    if (showOnboarding) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!onboardingComplete) return;

    final currentNickname = (_nickname.trim().isNotEmpty)
        ? _normalizeNickname(_nickname)
        : _normalizeNickname(prefs.getString('user_nickname') ?? '');
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
    _lastStreakRewardClaimDate =
        _normalizeClaimDate(prefs.getString('lastStreakRewardClaimDate'));
    final lastDate = prefs.getString('lastQuizDate');
    final streak = prefs.getInt('currentStreak') ?? 0;

    if (lastDate != null) {
      final lastQuizDateTime = DateTime.parse(lastDate);
      final difference =
          _currentDayStart().difference(_startOfDay(lastQuizDateTime)).inDays;

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
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSavedSessions = false;
        });
      }
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

  Future<void> _loadMistakeQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_mistakeQueuePrefsKey);
      if (payload == null || payload.isEmpty) return;

      final decoded = jsonDecode(payload);
      if (decoded is! List) return;

      final loaded = <_MistakeRecord>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = _MistakeRecord.fromJson(Map<String, dynamic>.from(item));
        if (parsed != null) {
          loaded.add(parsed);
        }
      }

      if (!mounted) return;
      setState(() {
        _mistakeQueue
          ..clear()
          ..addAll(loaded.take(_maxMistakeQueue));
      });
    } catch (e) {
      debugPrint('Error loading mistake queue: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMistakeQueue = false;
        });
      }
    }
  }

  Future<void> _persistMistakeQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = _mistakeQueue
          .take(_maxMistakeQueue)
          .map((record) => record.toJson())
          .toList();
      await prefs.setString(_mistakeQueuePrefsKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Error persisting mistake queue: $e');
    }
  }

  Future<void> _appendMistakesFromResult(Map<String, dynamic> results) async {
    final raw = results['mistakes'];
    if (raw is! List) return;

    final incoming = <_MistakeRecord>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final parsed = _MistakeRecord.fromJson(Map<String, dynamic>.from(item));
      if (parsed != null) incoming.add(parsed);
    }
    if (incoming.isEmpty) return;

    setState(() {
      _mistakeQueue.insertAll(0, incoming);
      if (_mistakeQueue.length > _maxMistakeQueue) {
        _mistakeQueue.removeRange(_maxMistakeQueue, _mistakeQueue.length);
      }
    });
    await _persistMistakeQueue();
  }

  bool _shouldQueueMistakesFromResult(Map<String, dynamic> results) {
    final shouldRecord = results['recordResults'];
    if (shouldRecord is bool && !shouldRecord) return false;

    final mode = results['testMode'];
    if (mode is! String) return false;

    return mode == 'randomQuiz' ||
        mode == 'focusMode' ||
        mode == 'challenge' ||
        mode == 'timedExam';
  }

  Future<void> _loadPausedQuizSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_pausedQuizSessionPrefsKey);
      if (payload == null || payload.isEmpty) return;

      final decoded = jsonDecode(payload);
      final loaded = <String, _PausedQuizSession>{};
      var removedExpired = false;

      if (decoded is Map<String, dynamic>) {
        // Backward compatibility: older payload used a single paused session map.
        if (decoded.containsKey('questions')) {
          final parsed = _PausedQuizSession.fromJson(decoded);
          if (parsed != null) {
            if (_isBeforeCurrentDay(parsed.pausedAt)) {
              removedExpired = true;
            } else {
              loaded[parsed.testMode] = parsed;
            }
          }
        } else {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! Map) continue;
            final parsed =
                _PausedQuizSession.fromJson(Map<String, dynamic>.from(value));
            if (parsed != null) {
              if (_isBeforeCurrentDay(parsed.pausedAt)) {
                removedExpired = true;
              } else {
                loaded[parsed.testMode] = parsed;
              }
            }
          }
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final parsed =
              _PausedQuizSession.fromJson(Map<String, dynamic>.from(item));
          if (parsed != null) {
            if (_isBeforeCurrentDay(parsed.pausedAt)) {
              removedExpired = true;
              continue;
            }
            loaded[parsed.testMode] = parsed;
          }
        }
      }

      if (removedExpired) {
        if (loaded.isEmpty) {
          await prefs.remove(_pausedQuizSessionPrefsKey);
        } else {
          await prefs.setString(
            _pausedQuizSessionPrefsKey,
            jsonEncode(loaded.values.map((s) => s.toJson()).toList()),
          );
        }
      }

      if (loaded.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _pausedQuizSessions
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      debugPrint('Error loading paused session: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPausedQuizSessions = false;
        });
      }
    }
  }

  bool _isPausedSessionExpired(_PausedQuizSession session) {
    return _isBeforeCurrentDay(session.pausedAt);
  }

  Future<void> _purgeExpiredPausedSessionsIfNeeded() async {
    if (_pausedQuizSessions.isEmpty) return;

    final activeEntries = _pausedQuizSessions.entries
        .where((entry) => !_isPausedSessionExpired(entry.value))
        .toList();

    if (activeEntries.length == _pausedQuizSessions.length) return;

    final nextSessions = <String, _PausedQuizSession>{
      for (final entry in activeEntries) entry.key: entry.value,
    };

    if (mounted) {
      setState(() {
        _pausedQuizSessions
          ..clear()
          ..addAll(nextSessions);
      });
    } else {
      _pausedQuizSessions
        ..clear()
        ..addAll(nextSessions);
    }

    await _persistPausedQuizSession();
  }

  Future<void> _persistPausedQuizSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pausedQuizSessions.isEmpty) {
        await prefs.remove(_pausedQuizSessionPrefsKey);
        unawaited(_syncAllProgressToRtdb());
        return;
      }
      await prefs.setString(
        _pausedQuizSessionPrefsKey,
        jsonEncode(_pausedQuizSessions.values.map((s) => s.toJson()).toList()),
      );
      unawaited(_syncAllProgressToRtdb());
    } catch (e) {
      debugPrint('Error persisting paused session: $e');
    }
  }

  Future<void> _savePausedSessionFromResult(Map<String, dynamic> result) async {
    if (_shouldQueueMistakesFromResult(result)) {
      await _appendMistakesFromResult(result);
    }

    final raw = result['resumeState'];
    if (raw is! Map) return;

    final parsed = _PausedQuizSession.fromJson(Map<String, dynamic>.from(raw));
    if (parsed == null) return;
    final session = parsed.copyWith(pausedAt: _currentClockTime());
    final modeKey = session.testMode;

    if (mounted) {
      setState(() {
        _pausedQuizSessions[modeKey] = session;
        currentScreen = 0;
      });
    }

    await _persistPausedQuizSession();
    if (mounted) {
      final modeLabel = _modeLabel(modeKey);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$modeLabel paused. Continue anytime from Study Hub.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearPausedQuizSession([String? testMode]) async {
    if (_pausedQuizSessions.isEmpty) return;

    var changed = false;

    if (mounted) {
      setState(() {
        if (testMode == null) {
          changed = _pausedQuizSessions.isNotEmpty;
          _pausedQuizSessions.clear();
        } else {
          changed = _pausedQuizSessions.remove(testMode) != null;
        }
      });
    } else {
      if (testMode == null) {
        changed = _pausedQuizSessions.isNotEmpty;
        _pausedQuizSessions.clear();
      } else {
        changed = _pausedQuizSessions.remove(testMode) != null;
      }
    }

    if (!changed) return;
    await _persistPausedQuizSession();
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'randomQuiz':
        return 'Random Quiz';
      case 'focusMode':
        return 'Focus Mode';
      case 'challenge':
        return 'Challenge Mode';
      case 'timedExam':
        return 'Timed Exam';
      case 'quickPractice':
        return 'Quick Practice';
      case 'reviewMistakes':
        return 'Review Mistakes';
      case 'previous':
        return 'Saved Session';
      default:
        return mode;
    }
  }

  String _buildGenerationModeLabel({
    required bool isFocusMode,
    String? focusCategory,
    String defaultLabel = 'RANDOM QUIZ',
  }) {
    if (!isFocusMode) {
      return defaultLabel;
    }

    final normalizedCategory = focusCategory?.trim();
    if (normalizedCategory == null || normalizedCategory.isEmpty) {
      return 'FOCUS MODE';
    }

    return 'FOCUS MODE\n$normalizedCategory';
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
  // DAILY GENERATION USAGE TRACKING (Access Rate Limiting)
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
    return _dateKeyFor(_currentClockTime());
  }

  String? _normalizeClaimDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  String? _preferTodayClaimDate(String? currentValue, String? localValue) {
    final todayKey = _getTodayDateString();
    final normalizedCurrent = _normalizeClaimDate(currentValue);
    final normalizedLocal = _normalizeClaimDate(localValue);

    if (normalizedLocal == todayKey) {
      return normalizedLocal;
    }

    return normalizedCurrent ?? normalizedLocal;
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

      final now = _currentClockTime();
      final todayStr = _currentDayStart().toIso8601String();
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
        // Program interest
        'selectedProgramInterest': programInterest,
        'hasChosenProgramInterest': !_showFirstTimeFlow,
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
        // Daily task rewards and progress
        'dailyTaskResetDate': _getTodayDateString(),
        'dailyTaskSessionsCompleted': _dailyTaskSessionsCompleted,
        'dailyTaskHighScoreAchieved': _dailyTaskHighScoreAchieved,
        'dailyTaskFocusCompleted': _dailyTaskFocusCompleted,
        'dailyTaskChallengeCompleted': _dailyTaskChallengeCompleted,
        'dailyTaskTimedCompleted': _dailyTaskTimedCompleted,
        'dailyTaskQuestionsAnswered': _dailyTaskQuestionsAnswered,
        'lastEightSessionRewardClaimDate': _lastEightSessionRewardClaimDate,
        'lastHighScoreRewardClaimDate': _lastHighScoreRewardClaimDate,
        'lastFocusRewardClaimDate': _lastFocusRewardClaimDate,
        'lastChallengeRewardClaimDate': _lastChallengeRewardClaimDate,
        'lastTimedExamRewardClaimDate': _lastTimedExamRewardClaimDate,
        'lastThirtyAnswersRewardClaimDate': _lastThirtyAnswersRewardClaimDate,
        // Paused sessions so continue flow survives app data clear/reinstall
        'pausedQuizSessions':
            _pausedQuizSessions.values.map((s) => s.toJson()).toList(),
        // Compact quiz activity history for 10-day screen (capped + pruned)
        'quizActivityRecords': _quizActivityRecords
            .map((record) => {
                  'd': record.date.toIso8601String(),
                  'm': record.mode,
                  'q': record.questionCount,
                  'c': record.correctCount,
                  'p': record.scorePercent,
                  'e': record.elapsedSeconds,
                  't': record.timedOutCount,
                  'cc': record.categoryCorrect,
                  'ct': record.categoryTotal,
                })
            .toList(),
        // Daily reset tracking (prevents re-reset after app data clear)
        'lastCategoryScoreResetDate': todayStr,
        // Sync timestamp
        'lastSyncTime': now.toIso8601String(),
      };

      await _rtdb
          .ref('devices/$_deviceId/progress')
          .set(progressData)
          .timeout(const Duration(seconds: 8));

      debugPrint('Synced all progress to RTDB (device)');
    } catch (e) {
      debugPrint('Could not sync progress to RTDB: $e');
    }
  }

  /// Shared merge logic used by both device-RTDB and user-RTDB restore.
  /// Applies max-wins strategy for all fields.
  void _mergeRtdbProgressData(Map<dynamic, dynamic> data) {
    final todayOnly = _currentDayStart();

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
        if (_isSameCalendarDay(remoteDate, todayOnly)) {
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

    // --- Program interest ---
    final remoteProgramInterest = (data['selectedProgramInterest'] ??
        data['selectedEligibility']) as String?;
    final remoteHasChosen = (data['hasChosenProgramInterest'] as bool?) ??
        (data['hasChosenEligibility'] as bool?) ??
        false;
    if (remoteHasChosen && _showFirstTimeFlow) {
      if (remoteProgramInterest != null) {
        programInterest = _normalizeSpecialization(remoteProgramInterest);
      }
      _showFirstTimeFlow = false;
    }

    final remoteNickname =
        _normalizeNickname((data['nickname'] as String?) ?? '');
    if (remoteNickname.isNotEmpty) {
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
    final remoteRemaining =
        (data['remainingFreeTests'] as num?)?.toInt() ?? _dailySessionTarget;
    final remoteResetDate = data['lastFreeTestResetDate'] as String?;
    if (remoteResetDate != null) {
      final resetDate = DateTime.tryParse(remoteResetDate);
      if (resetDate != null) {
        if (_isSameCalendarDay(resetDate, todayOnly)) {
          remainingFreeTests = min(remainingFreeTests, remoteRemaining);
        } else {
          remainingFreeTests = _dailySessionTarget;
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

    final remoteStreakRewardDate =
        _normalizeClaimDate(data['lastStreakRewardClaimDate'] as String?);
    if (remoteStreakRewardDate != null && remoteStreakRewardDate.isNotEmpty) {
      _lastStreakRewardClaimDate = remoteStreakRewardDate;
    }

    // --- Daily task rewards/progress (same-day only) ---
    final remoteDailyTaskResetDate = data['dailyTaskResetDate'] as String?;
    if (remoteDailyTaskResetDate == _getTodayDateString()) {
      _dailyTaskSessionsCompleted = max(
        _dailyTaskSessionsCompleted,
        (data['dailyTaskSessionsCompleted'] as num?)?.toInt() ?? 0,
      );
      _dailyTaskHighScoreAchieved = _dailyTaskHighScoreAchieved ||
          (data['dailyTaskHighScoreAchieved'] as bool? ?? false);
      _dailyTaskFocusCompleted = max(
        _dailyTaskFocusCompleted,
        (data['dailyTaskFocusCompleted'] as num?)?.toInt() ?? 0,
      );
      _dailyTaskChallengeCompleted = max(
        _dailyTaskChallengeCompleted,
        (data['dailyTaskChallengeCompleted'] as num?)?.toInt() ?? 0,
      );
      _dailyTaskTimedCompleted = max(
        _dailyTaskTimedCompleted,
        (data['dailyTaskTimedCompleted'] as num?)?.toInt() ?? 0,
      );
      _dailyTaskQuestionsAnswered = max(
        _dailyTaskQuestionsAnswered,
        (data['dailyTaskQuestionsAnswered'] as num?)?.toInt() ?? 0,
      );

      final remoteEightDate = _normalizeClaimDate(
        data['lastEightSessionRewardClaimDate'] as String?,
      );
      if (remoteEightDate != null && remoteEightDate.isNotEmpty) {
        _lastEightSessionRewardClaimDate = remoteEightDate;
      }
      final remoteHighScoreDate = _normalizeClaimDate(
        data['lastHighScoreRewardClaimDate'] as String?,
      );
      if (remoteHighScoreDate != null && remoteHighScoreDate.isNotEmpty) {
        _lastHighScoreRewardClaimDate = remoteHighScoreDate;
      }
      final remoteFocusDate =
          _normalizeClaimDate(data['lastFocusRewardClaimDate'] as String?);
      if (remoteFocusDate != null && remoteFocusDate.isNotEmpty) {
        _lastFocusRewardClaimDate = remoteFocusDate;
      }
      final remoteChallengeDate = _normalizeClaimDate(
        data['lastChallengeRewardClaimDate'] as String?,
      );
      if (remoteChallengeDate != null && remoteChallengeDate.isNotEmpty) {
        _lastChallengeRewardClaimDate = remoteChallengeDate;
      }
      final remoteTimedDate = _normalizeClaimDate(
        data['lastTimedExamRewardClaimDate'] as String?,
      );
      if (remoteTimedDate != null && remoteTimedDate.isNotEmpty) {
        _lastTimedExamRewardClaimDate = remoteTimedDate;
      }
      final remoteThirtyDate = _normalizeClaimDate(
        data['lastThirtyAnswersRewardClaimDate'] as String?,
      );
      if (remoteThirtyDate != null && remoteThirtyDate.isNotEmpty) {
        _lastThirtyAnswersRewardClaimDate = remoteThirtyDate;
      }
    }

    // --- Paused sessions ---
    final remotePausedRaw = data['pausedQuizSessions'];
    if (remotePausedRaw is List) {
      for (final item in remotePausedRaw) {
        if (item is! Map) continue;
        final parsed =
            _PausedQuizSession.fromJson(Map<String, dynamic>.from(item));
        if (parsed == null) continue;
        if (_isBeforeCurrentDay(parsed.pausedAt)) continue;
        _pausedQuizSessions[parsed.testMode] = parsed;
      }
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
      final todayKey = _getTodayDateString();
      final localDailyTaskResetDate = prefs.getString('dailyTaskResetDate');
      final hasLocalDailyTaskStateForToday =
          localDailyTaskResetDate == todayKey;

      if (hasLocalDailyTaskStateForToday) {
        _dailyTaskSessionsCompleted = max(
          _dailyTaskSessionsCompleted,
          prefs.getInt('dailyTaskSessionsCompleted') ?? 0,
        );
        _dailyTaskHighScoreAchieved = _dailyTaskHighScoreAchieved ||
            (prefs.getBool('dailyTaskHighScoreAchieved') ?? false);
        _dailyTaskFocusCompleted = max(
          _dailyTaskFocusCompleted,
          prefs.getInt('dailyTaskFocusCompleted') ?? 0,
        );
        _dailyTaskChallengeCompleted = max(
          _dailyTaskChallengeCompleted,
          prefs.getInt('dailyTaskChallengeCompleted') ?? 0,
        );
        _dailyTaskTimedCompleted = max(
          _dailyTaskTimedCompleted,
          prefs.getInt('dailyTaskTimedCompleted') ?? 0,
        );
        _dailyTaskQuestionsAnswered = max(
          _dailyTaskQuestionsAnswered,
          prefs.getInt('dailyTaskQuestionsAnswered') ?? 0,
        );
      }

      _lastStreakRewardClaimDate = _preferTodayClaimDate(
        _lastStreakRewardClaimDate,
        prefs.getString('lastStreakRewardClaimDate'),
      );
      _lastEightSessionRewardClaimDate = _preferTodayClaimDate(
        _lastEightSessionRewardClaimDate,
        prefs.getString('lastEightSessionRewardClaimDate'),
      );
      _lastHighScoreRewardClaimDate = _preferTodayClaimDate(
        _lastHighScoreRewardClaimDate,
        prefs.getString('lastHighScoreRewardClaimDate'),
      );
      _lastFocusRewardClaimDate = _preferTodayClaimDate(
        _lastFocusRewardClaimDate,
        prefs.getString('lastFocusRewardClaimDate'),
      );
      _lastChallengeRewardClaimDate = _preferTodayClaimDate(
        _lastChallengeRewardClaimDate,
        prefs.getString('lastChallengeRewardClaimDate'),
      );
      _lastTimedExamRewardClaimDate = _preferTodayClaimDate(
        _lastTimedExamRewardClaimDate,
        prefs.getString('lastTimedExamRewardClaimDate'),
      );
      _lastThirtyAnswersRewardClaimDate = _preferTodayClaimDate(
        _lastThirtyAnswersRewardClaimDate,
        prefs.getString('lastThirtyAnswersRewardClaimDate'),
      );

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
      await prefs.setString(_selectedProgramInterestPrefsKey, programInterest);
      await prefs.setBool(
        _hasChosenProgramInterestPrefsKey,
        !_showFirstTimeFlow,
      );
      await _removeLegacyEligibilityPrefs(prefs);
      await prefs.setString('user_nickname', _nickname);
      await prefs.setBool('mute_all_sounds', _muteAllSounds);
      await prefs.setInt('completedSessions', completedSessions);
      final now = _currentClockTime();
      final remoteLastSessionDate = data['lastSessionDate'] as String?;
      if (remoteLastSessionDate != null && remoteLastSessionDate.isNotEmpty) {
        await prefs.setString('lastSessionDate', remoteLastSessionDate);
      } else {
        await prefs.setString(
            'lastSessionDate', _startOfDay(now).toIso8601String());
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
          _normalizeClaimDate(_lastStreakRewardClaimDate!)!,
        );
      }
      await prefs.setString('dailyTaskResetDate', todayKey);
      await prefs.setInt(
          'dailyTaskSessionsCompleted', _dailyTaskSessionsCompleted);
      await prefs.setBool(
          'dailyTaskHighScoreAchieved', _dailyTaskHighScoreAchieved);
      await prefs.setInt('dailyTaskFocusCompleted', _dailyTaskFocusCompleted);
      await prefs.setInt(
          'dailyTaskChallengeCompleted', _dailyTaskChallengeCompleted);
      await prefs.setInt('dailyTaskTimedCompleted', _dailyTaskTimedCompleted);
      await prefs.setInt(
          'dailyTaskQuestionsAnswered', _dailyTaskQuestionsAnswered);
      if (_lastEightSessionRewardClaimDate != null) {
        await prefs.setString(
          'lastEightSessionRewardClaimDate',
          _normalizeClaimDate(_lastEightSessionRewardClaimDate!)!,
        );
      }
      if (_lastHighScoreRewardClaimDate != null) {
        await prefs.setString(
          'lastHighScoreRewardClaimDate',
          _normalizeClaimDate(_lastHighScoreRewardClaimDate!)!,
        );
      }
      if (_lastFocusRewardClaimDate != null) {
        await prefs.setString(
          'lastFocusRewardClaimDate',
          _normalizeClaimDate(_lastFocusRewardClaimDate!)!,
        );
      }
      if (_lastChallengeRewardClaimDate != null) {
        await prefs.setString(
          'lastChallengeRewardClaimDate',
          _normalizeClaimDate(_lastChallengeRewardClaimDate!)!,
        );
      }
      if (_lastTimedExamRewardClaimDate != null) {
        await prefs.setString(
          'lastTimedExamRewardClaimDate',
          _normalizeClaimDate(_lastTimedExamRewardClaimDate!)!,
        );
      }
      if (_lastThirtyAnswersRewardClaimDate != null) {
        await prefs.setString(
          'lastThirtyAnswersRewardClaimDate',
          _normalizeClaimDate(_lastThirtyAnswersRewardClaimDate!)!,
        );
      }
      if (_pausedQuizSessions.isEmpty) {
        await prefs.remove(_pausedQuizSessionPrefsKey);
      } else {
        await prefs.setString(
          _pausedQuizSessionPrefsKey,
          jsonEncode(
              _pausedQuizSessions.values.map((s) => s.toJson()).toList()),
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
        await prefs.setString(
            'lastCategoryScoreResetDate', _startOfDay(now).toIso8601String());
      }

      debugPrint('Restored all progress from RTDB');
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
          final today = _currentDayStart();

          if (lastResetDateStr != null) {
            final lastResetDate = DateTime.parse(lastResetDateStr);

            if (!mounted) return;
            setState(() {
              if (_isBeforeCurrentDay(lastResetDate)) {
                // New day - reset to configured daily target
                remainingFreeTests = _dailySessionTarget;
              } else {
                // Same day - restore from server
                remainingFreeTests =
                    (data['remaining'] as int?) ?? _dailySessionTarget;
              }
            });

            // Update server date if new day
            if (_isBeforeCurrentDay(lastResetDate)) {
              await ref.update({
                'remaining': _dailySessionTarget,
                'lastResetDate': today.toIso8601String(),
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('remainingFreeTests', _dailySessionTarget);
              await prefs.setString(
                  'lastFreeTestResetDate', today.toIso8601String());
            }
          } else {
            await ref.update({
              'remaining': _dailySessionTarget,
              'lastResetDate': today.toIso8601String(),
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('remainingFreeTests', _dailySessionTarget);
            await prefs.setString(
                'lastFreeTestResetDate', today.toIso8601String());
          }

          debugPrint('Loaded free tests from Realtime DB');
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
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDailyFreeTests = false;
        });
      }
    }
  }

  /// Initialize free tests in Realtime DB (first time)
  Future<void> _initializeRealtimeDbFreeTests() async {
    try {
      _deviceId ??= await _deviceService.getDeviceId();
      if (_deviceId == null) return;

      final today = _currentDayStart();
      final db = _rtdb;
      final ref = db.ref('devices/$_deviceId/freeTests');

      await ref.set({
        'remaining': _dailySessionTarget,
        'lastResetDate': today.toIso8601String(),
        'createdAt': _currentClockTime().toIso8601String(),
      });

      if (!mounted) return;
      setState(() => remainingFreeTests = _dailySessionTarget);

      debugPrint('Initialized free tests in Realtime DB');
    } catch (e) {
      debugPrint('Error initializing Realtime DB: $e');
    }
  }

  /// Load daily free tests from local storage (fallback)
  Future<void> _loadDailyFreeTestsLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastResetDateStr = prefs.getString('lastFreeTestResetDate');
      final today = _currentDayStart();

      if (lastResetDateStr == null) {
        await prefs.setString('lastFreeTestResetDate', today.toIso8601String());
        if (!mounted) return;
        setState(() => remainingFreeTests = _dailySessionTarget);
        return;
      }

      final lastResetDate = DateTime.parse(lastResetDateStr);

      if (!mounted) return;
      setState(() {
        if (_isBeforeCurrentDay(lastResetDate)) {
          remainingFreeTests = _dailySessionTarget;
        } else {
          remainingFreeTests =
              prefs.getInt('remainingFreeTests') ?? _dailySessionTarget;
        }
      });

      if (_isBeforeCurrentDay(lastResetDate)) {
        await prefs.setInt('remainingFreeTests', _dailySessionTarget);
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
      final todayOnly = _currentDayStart().toIso8601String();
      final lastResetDate =
          prefs.getString('lastFreeTestResetDate') ?? todayOnly;
      final db = _rtdb;
      await db.ref('devices/$_deviceId/freeTests').update({
        'remaining': remainingFreeTests,
        'lastResetDate': lastResetDate,
      });

      debugPrint('Synced free tests to Realtime DB');
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
        'English': 0.25,
        'Mathematics': 0.25,
        'Logical Reasoning': 0.25,
        'Mental Ability / Abstract': 0.25,
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

      debugPrint('Loaded category scores from local storage (merged)');
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
      final today = _currentDayStart();

      if (lastSessionDateStr == null) {
        // First time â€” only set date, don't reset completedSessions
        // (may already be restored from RTDB/Firestore)
        await prefs.setString('lastSessionDate', today.toIso8601String());
        return;
      }

      final lastSessionDate = DateTime.parse(lastSessionDateStr);

      if (!mounted) return;
      setState(() {
        if (_isBeforeCurrentDay(lastSessionDate)) {
          // New day - reset to 0
          completedSessions = 0;
        } else {
          // Same day - merge with higher value
          final localSessions = prefs.getInt('completedSessions') ?? 0;
          completedSessions = max(completedSessions, localSessions);
        }
      });

      // Update the session date if it's a new day
      if (_isBeforeCurrentDay(lastSessionDate)) {
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
  }

  bool get _canClaimEightSessionRewardToday =>
      !_isLoadingDailyTaskRewards &&
      _dailyTaskSessionsCompleted >= 8 &&
      _lastEightSessionRewardClaimDate != _getTodayDateString();

  bool get _canClaimHighScoreRewardToday =>
      !_isLoadingDailyTaskRewards &&
      _dailyTaskHighScoreAchieved &&
      _lastHighScoreRewardClaimDate != _getTodayDateString();

  bool get _canClaimFocusRewardToday =>
      !_isLoadingDailyTaskRewards &&
      _dailyTaskFocusCompleted >= 1 &&
      _lastFocusRewardClaimDate != _getTodayDateString();

  bool get _canClaimChallengeRewardToday =>
      !_isLoadingDailyTaskRewards &&
      _dailyTaskChallengeCompleted >= 1 &&
      _lastChallengeRewardClaimDate != _getTodayDateString();

  bool get _canClaimTimedExamRewardToday =>
      !_isLoadingDailyTaskRewards &&
      _dailyTaskTimedCompleted >= 1 &&
      _lastTimedExamRewardClaimDate != _getTodayDateString();

  bool get _canClaimThirtyAnswersRewardToday =>
      !_isLoadingDailyTaskRewards &&
      _dailyTaskQuestionsAnswered >= 30 &&
      _lastThirtyAnswersRewardClaimDate != _getTodayDateString();

  int get _claimableSessionsCountNow {
    if (_isLoadingDailyTaskRewards) return 0;
    var count = 0;
    count += _extraSessionAdChances;
    if (_canClaimStreakRewardToday) count++;
    if (_canClaimEightSessionRewardToday) count++;
    if (_canClaimFocusRewardToday) count++;
    if (_canClaimChallengeRewardToday) count++;
    if (_canClaimTimedExamRewardToday) count++;
    if (_canClaimThirtyAnswersRewardToday) count++;
    if (_canClaimHighScoreRewardToday) count++;
    return count;
  }

  Future<void> _loadDailyTaskRewardState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _getTodayDateString();
      final savedDate = prefs.getString('dailyTaskResetDate') ?? today;
      final hasInMemoryDailyTaskStateForToday =
          _dailyTaskSessionsCompleted > 0 ||
              _dailyTaskHighScoreAchieved ||
              _dailyTaskFocusCompleted > 0 ||
              _dailyTaskChallengeCompleted > 0 ||
              _dailyTaskTimedCompleted > 0 ||
              _dailyTaskQuestionsAnswered > 0 ||
              _lastStreakRewardClaimDate == today ||
              _lastEightSessionRewardClaimDate == today ||
              _lastHighScoreRewardClaimDate == today ||
              _lastFocusRewardClaimDate == today ||
              _lastChallengeRewardClaimDate == today ||
              _lastTimedExamRewardClaimDate == today ||
              _lastThirtyAnswersRewardClaimDate == today;

      if (savedDate != today) {
        if (hasInMemoryDailyTaskStateForToday) {
          await _persistDailyTaskRewardState();
          return;
        }

        await prefs.setString('dailyTaskResetDate', today);
        await prefs.setInt('dailyTaskSessionsCompleted', 0);
        await prefs.setBool('dailyTaskHighScoreAchieved', false);
        await prefs.setInt('dailyTaskFocusCompleted', 0);
        await prefs.setInt('dailyTaskChallengeCompleted', 0);
        await prefs.setInt('dailyTaskTimedCompleted', 0);
        await prefs.setInt('dailyTaskQuestionsAnswered', 0);
        await prefs.remove('lastStreakRewardClaimDate');
        await prefs.remove('lastEightSessionRewardClaimDate');
        await prefs.remove('lastHighScoreRewardClaimDate');
        await prefs.remove('lastFocusRewardClaimDate');
        await prefs.remove('lastChallengeRewardClaimDate');
        await prefs.remove('lastTimedExamRewardClaimDate');
        await prefs.remove('lastThirtyAnswersRewardClaimDate');
        if (!mounted) return;
        setState(() {
          _dailyTaskSessionsCompleted = 0;
          _dailyTaskHighScoreAchieved = false;
          _dailyTaskFocusCompleted = 0;
          _dailyTaskChallengeCompleted = 0;
          _dailyTaskTimedCompleted = 0;
          _dailyTaskQuestionsAnswered = 0;
          _lastStreakRewardClaimDate = null;
          _lastEightSessionRewardClaimDate = null;
          _lastHighScoreRewardClaimDate = null;
          _lastFocusRewardClaimDate = null;
          _lastChallengeRewardClaimDate = null;
          _lastTimedExamRewardClaimDate = null;
          _lastThirtyAnswersRewardClaimDate = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _dailyTaskSessionsCompleted = max(
          _dailyTaskSessionsCompleted,
          prefs.getInt('dailyTaskSessionsCompleted') ?? 0,
        );
        _dailyTaskHighScoreAchieved = _dailyTaskHighScoreAchieved ||
            (prefs.getBool('dailyTaskHighScoreAchieved') ?? false);
        _dailyTaskFocusCompleted = max(
          _dailyTaskFocusCompleted,
          prefs.getInt('dailyTaskFocusCompleted') ?? 0,
        );
        _dailyTaskChallengeCompleted = max(
          _dailyTaskChallengeCompleted,
          prefs.getInt('dailyTaskChallengeCompleted') ?? 0,
        );
        _dailyTaskTimedCompleted = max(
          _dailyTaskTimedCompleted,
          prefs.getInt('dailyTaskTimedCompleted') ?? 0,
        );
        _dailyTaskQuestionsAnswered = max(
          _dailyTaskQuestionsAnswered,
          prefs.getInt('dailyTaskQuestionsAnswered') ?? 0,
        );
        _lastStreakRewardClaimDate = _preferTodayClaimDate(
          _lastStreakRewardClaimDate,
          prefs.getString('lastStreakRewardClaimDate'),
        );
        _lastEightSessionRewardClaimDate = _preferTodayClaimDate(
          _lastEightSessionRewardClaimDate,
          prefs.getString('lastEightSessionRewardClaimDate'),
        );
        _lastHighScoreRewardClaimDate = _preferTodayClaimDate(
          _lastHighScoreRewardClaimDate,
          prefs.getString('lastHighScoreRewardClaimDate'),
        );
        _lastFocusRewardClaimDate = _preferTodayClaimDate(
          _lastFocusRewardClaimDate,
          prefs.getString('lastFocusRewardClaimDate'),
        );
        _lastChallengeRewardClaimDate = _preferTodayClaimDate(
          _lastChallengeRewardClaimDate,
          prefs.getString('lastChallengeRewardClaimDate'),
        );
        _lastTimedExamRewardClaimDate = _preferTodayClaimDate(
          _lastTimedExamRewardClaimDate,
          prefs.getString('lastTimedExamRewardClaimDate'),
        );
        _lastThirtyAnswersRewardClaimDate = _preferTodayClaimDate(
          _lastThirtyAnswersRewardClaimDate,
          prefs.getString('lastThirtyAnswersRewardClaimDate'),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDailyTaskRewards = false;
        });
      }
    }
  }

  Future<void> _persistDailyTaskRewardState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dailyTaskResetDate', _getTodayDateString());
    await prefs.setInt(
        'dailyTaskSessionsCompleted', _dailyTaskSessionsCompleted);
    await prefs.setBool(
        'dailyTaskHighScoreAchieved', _dailyTaskHighScoreAchieved);
    await prefs.setInt('dailyTaskFocusCompleted', _dailyTaskFocusCompleted);
    await prefs.setInt(
        'dailyTaskChallengeCompleted', _dailyTaskChallengeCompleted);
    await prefs.setInt('dailyTaskTimedCompleted', _dailyTaskTimedCompleted);
    await prefs.setInt(
        'dailyTaskQuestionsAnswered', _dailyTaskQuestionsAnswered);

    if (_lastStreakRewardClaimDate == null) {
      await prefs.remove('lastStreakRewardClaimDate');
    } else {
      await prefs.setString(
        'lastStreakRewardClaimDate',
        _normalizeClaimDate(_lastStreakRewardClaimDate)!,
      );
    }

    if (_lastEightSessionRewardClaimDate == null) {
      await prefs.remove('lastEightSessionRewardClaimDate');
    } else {
      await prefs.setString(
        'lastEightSessionRewardClaimDate',
        _normalizeClaimDate(_lastEightSessionRewardClaimDate)!,
      );
    }

    if (_lastHighScoreRewardClaimDate == null) {
      await prefs.remove('lastHighScoreRewardClaimDate');
    } else {
      await prefs.setString(
        'lastHighScoreRewardClaimDate',
        _normalizeClaimDate(_lastHighScoreRewardClaimDate)!,
      );
    }

    if (_lastFocusRewardClaimDate == null) {
      await prefs.remove('lastFocusRewardClaimDate');
    } else {
      await prefs.setString(
        'lastFocusRewardClaimDate',
        _normalizeClaimDate(_lastFocusRewardClaimDate)!,
      );
    }

    if (_lastChallengeRewardClaimDate == null) {
      await prefs.remove('lastChallengeRewardClaimDate');
    } else {
      await prefs.setString(
        'lastChallengeRewardClaimDate',
        _normalizeClaimDate(_lastChallengeRewardClaimDate)!,
      );
    }

    if (_lastTimedExamRewardClaimDate == null) {
      await prefs.remove('lastTimedExamRewardClaimDate');
    } else {
      await prefs.setString(
        'lastTimedExamRewardClaimDate',
        _normalizeClaimDate(_lastTimedExamRewardClaimDate)!,
      );
    }

    if (_lastThirtyAnswersRewardClaimDate == null) {
      await prefs.remove('lastThirtyAnswersRewardClaimDate');
    } else {
      await prefs.setString(
        'lastThirtyAnswersRewardClaimDate',
        _normalizeClaimDate(_lastThirtyAnswersRewardClaimDate)!,
      );
    }

    if (_isOnline) {
      unawaited(_syncAllProgressToRtdb());
    }
  }

  Future<void> _persistClaimedDailyRewardDate(
    String storageKey,
    String todayKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dailyTaskResetDate', todayKey);
    await prefs.setString(storageKey, todayKey);
  }

  Future<void> _claimFourSessionTaskReward() async {
    if (!_canClaimStreakRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastStreakRewardClaimDate = todayKey;
    });

    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        '$_dailySessionTarget-session reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _claimEightSessionTaskReward() async {
    if (!_canClaimEightSessionRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastEightSessionRewardClaimDate = todayKey;
    });

    await _persistClaimedDailyRewardDate(
      'lastEightSessionRewardClaimDate',
      todayKey,
    );
    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        '8-session reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _claimHighScoreTaskReward() async {
    if (!_canClaimHighScoreRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastHighScoreRewardClaimDate = todayKey;
    });

    await _persistClaimedDailyRewardDate(
      'lastHighScoreRewardClaimDate',
      todayKey,
    );
    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        'High-score reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _claimFocusTaskReward() async {
    if (!_canClaimFocusRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastFocusRewardClaimDate = todayKey;
    });

    await _persistClaimedDailyRewardDate(
      'lastFocusRewardClaimDate',
      todayKey,
    );
    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        'Focus reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _claimChallengeTaskReward() async {
    if (!_canClaimChallengeRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastChallengeRewardClaimDate = todayKey;
    });

    await _persistClaimedDailyRewardDate(
      'lastChallengeRewardClaimDate',
      todayKey,
    );
    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        'Challenge reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _claimTimedExamTaskReward() async {
    if (!_canClaimTimedExamRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastTimedExamRewardClaimDate = todayKey;
    });

    await _persistClaimedDailyRewardDate(
      'lastTimedExamRewardClaimDate',
      todayKey,
    );
    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        'Timed exam reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _claimThirtyAnswersTaskReward() async {
    if (!_canClaimThirtyAnswersRewardToday) return;

    final todayKey = _getTodayDateString();
    final claimedWhileOnline = _isOnline;
    setState(() {
      remainingFreeTests++;
      _lastThirtyAnswersRewardClaimDate = todayKey;
    });

    await _persistClaimedDailyRewardDate(
      'lastThirtyAnswersRewardClaimDate',
      todayKey,
    );
    await _persistDailyFreeTests();
    await _persistDailyTaskRewardState();
    if (claimedWhileOnline) {
      await _syncAllProgressToRtdb();
    } else {
      _showOfflineProgressSavedMessage(
        'Answer-count reward claimed: +1 free session.',
      );
    }
  }

  Future<void> _saveProgramInterestPreference(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeSpecialization(value);
    await prefs.setString(_selectedProgramInterestPrefsKey, normalized);
    await prefs.setBool(_hasChosenProgramInterestPrefsKey, true);
    await _removeLegacyEligibilityPrefs(prefs);

    setState(() {
      programInterest = normalized;
      _showFirstTimeFlow = false;
      _ensurePnleCategoryScores();
    });

    unawaited(_primeMissingCachesAsNeeded());
    if (_seedPoolReady) {
      unawaited(_refillSeedPoolsIfNeeded());
      unawaited(_refreshPoolWarmupStatus());
    }

    _syncAllProgressToRtdb();
  }

  Future<void> _handleSpecializationSelection(String value) async {
    await _saveProgramInterestPreference(value);
  }

  String _normalizeSpecialization(String? value) {
    if (value == null || value.isEmpty) return 'General ACET';
    switch (value) {
      case 'Nursing':
        return 'English Priority';
      case 'Engineering':
        return 'Mathematics Priority';
      case 'Business':
        return 'Logical Reasoning Priority';
      case 'Arts':
        return 'English Priority';
      case 'Science':
        return 'Mental Ability Priority';
    }
    if (_acetStudyPreferences.contains(value)) return value;
    return 'General ACET';
  }

  // =========================
  // ADMOB
  // =========================
  String _rewardedAdUnitId() {
    return AdMobIds.rewarded;
  }

  String _bannerAdUnitId() {
    return AdMobIds.banner;
  }

  String _menuInterstitialAdUnitId() {
    return AdMobIds.interstitial;
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          debugPrint(
            'Rewarded ad failed to load (${error.code}: ${error.message})',
          );
        },
      ),
    );
  }

  void _loadMenuInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _menuInterstitialAdUnitId(),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _menuInterstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            'Menu interstitial ad failed to load (${error.code}: ${error.message})',
          );
        },
      ),
    );
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId(),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          if (mounted) {
            setState(() {
              _isBannerAdLoaded = false;
            });
          }
          debugPrint(
            'Menu banner ad failed to load (${error.code}: ${error.message})',
          );
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
    unawaited(_primeMissingCachesAsNeeded());
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
    final todayOnly = _currentDayStart();

    if (lastResetStr != null) {
      final lastReset = DateTime.parse(lastResetStr);
      if (_isSameCalendarDay(lastReset, todayOnly)) {
        return; // Already reset today
      }
    }

    // New day â€” reset category scores
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
            content: Text('You earned 1 extra quiz! Keep it up!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  List<Question> _quickPracticeFromSavedPool() {
    final pool = _savedSessions.expand((session) => session.questions).toList();
    if (pool.isEmpty) return const [];

    final random = Random();
    return List<Question>.generate(5, (_) {
      final picked = pool[random.nextInt(pool.length)];
      return picked.shuffled();
    });
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
      'imageAssetPath': q.imageAssetPath,
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

  // =========================
  // TEST GENERATION
  // =========================
  Future<bool> _generateTest(
      {bool isFocusMode = false, String? focusCategory}) async {
    await _ensureSeedPoolReadyForGeneration();
    _usedCachedRandomForLastGeneration = false;

    // Primary/Fallback uses Gemini-first; all other users go straight to DeepSeek pre-generation flow.
    final useGemini = hasUnlimitedAccess || hasGraceAccess;

    // Use state variables if not passed as parameters
    final useFocusMode = isFocusMode || _isFocusMode;
    final category = focusCategory ?? _focusCategory;
    final useTimedMode = !useFocusMode && _activeGenerationMode == 'timedExam';

    final prompt = useFocusMode && category != null
        ? _buildFocusPrompt(category)
        : (useTimedMode ? _buildTimedModePrompt() : _buildPrompt());
    final deepSeekPrompt = useFocusMode && category != null
        ? _buildFastFocusPrompt(category)
        : (useTimedMode ? _buildFastTimedModePrompt() : _buildFastPrompt());

    // Build category map for Focus Mode if applicable
    Map<int, String>? categoryMap;
    if (useFocusMode && category != null) {
      categoryMap = _buildFocusCategoryMap(category);
    }

    if (useFocusMode && category != null) {
      final seededQuestions = await _takeSeedQuestions(
        'focusMode',
        categoryMap!,
      );
      if (seededQuestions.length >= 15) {
        debugPrint('[SeedPool] Focus mode served from pool ($category).');
        _generatedQuestions = seededQuestions.take(15).toList();
        _generatedQuestions =
            _generatedQuestions.map((q) => q.shuffled()).toList();
        _isFocusMode = false;
        _focusCategory = null;
        return true;
      }
      await _ensureSeedPoolBucketsForRequest(
        mode: 'focusMode',
        categoryMap: categoryMap,
      );

      final refilledSeedQuestions = await _takeSeedQuestions(
        'focusMode',
        categoryMap,
      );
      if (refilledSeedQuestions.length >= 15) {
        debugPrint('[SeedPool] Focus mode served after targeted refill.');
        _generatedQuestions = refilledSeedQuestions.take(15).toList();
        _generatedQuestions =
            _generatedQuestions.map((q) => q.shuffled()).toList();
        _isFocusMode = false;
        _focusCategory = null;
        return true;
      }
    } else {
      final seedMode =
          _activeGenerationMode == 'timedExam' ? 'timedExam' : 'randomQuiz';
      final randomLikeMap = _buildRandomCategoryMap();
      final seededQuestions = await _takeSeedQuestions(
        seedMode,
        randomLikeMap,
      );
      if (seededQuestions.length >= 15) {
        debugPrint('[SeedPool] $seedMode served from pool.');
        _generatedQuestions = seededQuestions.take(15).toList();
        _generatedQuestions =
            _generatedQuestions.map((q) => q.shuffled()).toList();
        _isFocusMode = false;
        _focusCategory = null;
        return true;
      }
      await _ensureSeedPoolBucketsForRequest(
        mode: seedMode,
        categoryMap: randomLikeMap,
      );

      final refilledSeedQuestions = await _takeSeedQuestions(
        seedMode,
        randomLikeMap,
      );
      if (refilledSeedQuestions.length >= 15) {
        debugPrint('[SeedPool] $seedMode served after targeted refill.');
        _generatedQuestions = refilledSeedQuestions.take(15).toList();
        _generatedQuestions =
            _generatedQuestions.map((q) => q.shuffled()).toList();
        _isFocusMode = false;
        _focusCategory = null;
        return true;
      }
    }

    if (useGemini) {
      debugPrint(
          '[SeedPool] Falling back to live generation (Gemini-first flow).');
      if (GEMINI_API_KEY.trim().isEmpty) {
        return false;
      }
      try {
        final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
        _generatedQuestions = await service.generateQuestions(
          prompt,
          programInterest,
          categoryMap: categoryMap,
        );
      } catch (e) {
        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          return false;
        }

        final service = _buildDeepSeekService(fastMode: false);
        _generatedQuestions = await service.generateQuestions(
          prompt,
          programInterest,
          categoryMap: categoryMap,
        );
      }
    } else {
      debugPrint('[SeedPool] Falling back to live generation (DeepSeek flow).');
      if (useFocusMode && category != null) {
        final cached = _cachedFocusQuestions[category];
        if (cached != null && cached.length >= 15) {
          _generatedQuestions = cached.take(15).toList();
          _cachedFocusQuestions.remove(category);
          unawaited(_persistFocusAndChallengeCaches());
          unawaited(_primeMissingCachesAsNeeded());
        } else {
          try {
            if (DEEPSEEK_API_KEY.trim().isEmpty) {
              throw Exception('DeepSeek unavailable');
            }
            final service = _buildDeepSeekService(fastMode: true);
            _generatedQuestions = await service.generateQuestions(
              deepSeekPrompt,
              programInterest,
              categoryMap: categoryMap,
            );
          } catch (_) {
            if (GEMINI_API_KEY.trim().isEmpty) {
              return false;
            }
            final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
            _generatedQuestions = await service.generateQuestions(
              prompt,
              programInterest,
              categoryMap: categoryMap,
            );
          }
        }
      } else {
        var servedFromCache = false;
        if ((_cachedRandomQuizQuestions?.length ?? 0) >= 15) {
          final cachedQuestions = _cachedRandomQuizQuestions!;
          final cachedVisualCount = cachedQuestions
              .where((q) => (q.imageAssetPath?.isNotEmpty ?? false))
              .length;
          if (cachedVisualCount > 1) {
            await _clearRandomQuizCache();
          } else {
            _usedCachedRandomForLastGeneration = true;
            if (_cachedRandomQuizCoverage != null) {
              _currentTestCoverage =
                  Map<String, String>.from(_cachedRandomQuizCoverage!);
            }
            _generatedQuestions = cachedQuestions.take(15).toList();
            servedFromCache = true;
          }
        }

        if (!servedFromCache) {
          try {
            if (DEEPSEEK_API_KEY.trim().isEmpty) {
              throw Exception('DeepSeek unavailable');
            }
            final service = _buildDeepSeekService(fastMode: true);
            _generatedQuestions = await service.generateQuestions(
              deepSeekPrompt,
              programInterest,
              categoryMap: categoryMap,
            );
          } catch (_) {
            if (GEMINI_API_KEY.trim().isEmpty) {
              return false;
            }
            final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
            _generatedQuestions = await service.generateQuestions(
              prompt,
              programInterest,
              categoryMap: categoryMap,
            );
          }
        }
      }
    }

    // Shuffle choices to avoid patterns in correct answers
    _generatedQuestions = _generatedQuestions.map((q) => q.shuffled()).toList();

    // Increment daily usage counter for access-enabled users
    if ((hasUnlimitedAccess || hasGraceAccess) &&
        _generatedQuestions.isNotEmpty) {
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
    final categories = _categoriesForProgramInterest();
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
    final categories = _categoriesForProgramInterest();

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

  Map<int, String> _buildRandomCategoryMap() {
    final categories = _categoriesForProgramInterest();
    if (categories.isEmpty) return {};

    final categoryMap = <int, String>{};
    final base = 15 ~/ categories.length;
    final remainder = 15 % categories.length;
    int questionNumber = 1;

    for (int i = 0; i < categories.length; i++) {
      final count = base + (i < remainder ? 1 : 0);
      for (int j = 0; j < count && questionNumber <= 15; j++) {
        categoryMap[questionNumber] = categories[i];
        questionNumber++;
      }
    }

    return categoryMap;
  }

  Future<List<Question>> _takeSeedQuestions(
    String mode,
    Map<int, String> categoryMap,
  ) async {
    if (!_seedPoolReady || categoryMap.isEmpty) {
      return const [];
    }

    final questions = await _seedPoolService.takeQuestions(
      mode: mode,
      categoryMap: categoryMap,
    );
    if (questions.isNotEmpty) {
      unawaited(_refillSeedPoolsIfNeeded());
    }
    return questions;
  }

  Future<void> _ensureSeedPoolReadyForGeneration() async {
    if (_seedPoolReady) return;
    try {
      await _seedPoolService.ensureInitialized();
      if (!mounted) {
        _seedPoolReady = true;
        return;
      }
      setState(() {
        _seedPoolReady = true;
      });
      unawaited(_refreshPoolWarmupStatus());
    } catch (e) {
      debugPrint('Seed pool readiness check skipped: $e');
    }
  }

  Future<void> _ensureSeedPoolBucketsForRequest({
    required String mode,
    required Map<int, String> categoryMap,
  }) async {
    if (!_seedPoolReady || categoryMap.isEmpty || _isRefillingSeedPool) {
      return;
    }
    if (GEMINI_API_KEY.trim().isEmpty && DEEPSEEK_API_KEY.trim().isEmpty) {
      return;
    }

    final targetCategories = categoryMap.values.toSet();

    _isRefillingSeedPool = true;
    try {
      final deficits =
          await _seedPoolService.getDeficits(threshold: 29, targetSize: 30);

      final modePrefix = '$mode::';
      for (final entry in deficits.entries) {
        if (!entry.key.startsWith(modePrefix) || entry.value <= 0) {
          continue;
        }

        final category = entry.key.substring(modePrefix.length);
        if (!targetCategories.contains(category)) {
          continue;
        }

        int remaining = entry.value;
        final generated = <Question>[];

        while (remaining > 0) {
          final batchSize = remaining > 8 ? 8 : remaining;
          final batch = await _generateSeedRefillBatch(
            mode: mode,
            category: category,
            count: batchSize,
          );
          if (batch.isEmpty) {
            break;
          }
          generated.addAll(batch);
          remaining -= batch.length;
        }

        if (generated.isNotEmpty) {
          await _seedPoolService.addQuestions(
            mode,
            category,
            generated,
            targetSize: 30,
          );
        }
      }
    } catch (e) {
      debugPrint('Targeted seed refill skipped: $e');
    } finally {
      _isRefillingSeedPool = false;
      unawaited(_refreshPoolWarmupStatus());
    }
  }

  Future<void> _refillSeedPoolsIfNeeded() async {
    if (!_seedPoolReady || _isRefillingSeedPool) return;
    if (GEMINI_API_KEY.trim().isEmpty && DEEPSEEK_API_KEY.trim().isEmpty) {
      return;
    }

    _isRefillingSeedPool = true;
    try {
      final deficits =
          await _seedPoolService.getDeficits(threshold: 29, targetSize: 30);

      for (final entry in deficits.entries) {
        if (entry.value <= 0) continue;

        final parts = entry.key.split('::');
        if (parts.length != 2) continue;

        final mode = parts[0];
        final category = parts[1];
        int remaining = entry.value;
        final generated = <Question>[];

        while (remaining > 0) {
          final batchSize = remaining > 8 ? 8 : remaining;
          final batch = await _generateSeedRefillBatch(
            mode: mode,
            category: category,
            count: batchSize,
          );
          if (batch.isEmpty) break;
          generated.addAll(batch);
          remaining -= batch.length;
        }

        if (generated.isNotEmpty) {
          await _seedPoolService.addQuestions(
            mode,
            category,
            generated,
            targetSize: 30,
          );
        }
      }
    } catch (e) {
      debugPrint('Seed pool refill skipped: $e');
    } finally {
      _isRefillingSeedPool = false;
      unawaited(_refreshPoolWarmupStatus());
    }
  }

  Future<List<Question>> _generateSeedRefillBatch({
    required String mode,
    required String category,
    required int count,
  }) async {
    if (count <= 0) return const [];

    final categoryMap = <int, String>{
      for (int i = 1; i <= count; i++) i: category,
    };
    final prompt = _buildSeedRefillPrompt(mode, category, count);

    List<Question> generated = const [];
    if (DEEPSEEK_API_KEY.trim().isNotEmpty) {
      final service = _buildDeepSeekService(fastMode: true, tokenCap: 2200);
      generated = await service.generateQuestions(
        prompt,
        programInterest,
        categoryMap: categoryMap,
      );
    } else if (GEMINI_API_KEY.trim().isNotEmpty) {
      final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
      generated = await service.generateQuestions(
        prompt,
        programInterest,
        categoryMap: categoryMap,
      );
    }

    if (generated.isEmpty) return const [];

    final normalized = <Question>[];
    for (int i = 0; i < generated.length; i++) {
      final q = generated[i];
      if (q.choices.length < 4 || q.answer.isEmpty) continue;
      normalized.add(
        Question(
          number: i + 1,
          category: category,
          question: q.question,
          choices: q.choices.take(4).toList(),
          answer: q.answer.toUpperCase(),
          explanation: q.explanation,
          source: q.source ?? 'seed_refill',
        ),
      );
    }

    return normalized;
  }

  String _buildSeedRefillPrompt(String mode, String category, int count) {
    final modeInstruction = switch (mode) {
      'focusMode' =>
        'Focus mode style: precise and targeted in one category, medium-to-hard difficulty.',
      'challenge' =>
        'Challenge style: hard but fair, analytical reasoning required, no trick wording.',
      'timedExam' =>
        'Timed exam style: concise stems, time-pressure friendly phrasing, medium-to-hard reasoning.',
      _ =>
        'Random quiz style: mixed difficulty with clear wording and strong fundamentals.',
    };

    return _examConfigService.buildSeedRefillPrompt(
      examId: _activeExamId,
      mode: mode,
      category: category,
      count: count,
      fallbackModeInstruction: modeInstruction,
      fallbackTemplate:
          'Generate exactly {{count}} multiple-choice questions for ACET practice.\n\nCategory: {{category}}\n{{modeInstruction}}\n\nConstraints:\n- Return strict JSON array only (no markdown):\n[\n  {\n    "number": 1,\n    "category": "{{category}}",\n    "question": "...",\n    "choices": ["A", "B", "C", "D"],\n    "answer": "A",\n    "explanation": "2-3 sentence concise rationale",\n    "source": "seed_refill"\n  }\n]\n- Exactly 4 choices per question.\n- One correct answer only, answer must be A/B/C/D.\n- Keep questions age-appropriate for Filipino SHS and college admission prep.\n- Avoid duplicates and avoid requiring images or tables.',
    );
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
      final categories = _categoriesForProgramInterest();
      if (categories.isEmpty) return;

      final focusCategory = categories[Random().nextInt(categories.length)];
      final prompt = _buildFastChallengeModePrompt(focusCategory);
      final categoryMap = _buildChallengeCategoryMap(focusCategory);

      final service = _buildDeepSeekService(fastMode: true, tokenCap: 2200);
      final questions = await service.generateQuestions(
        prompt,
        programInterest,
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

    final categories = _categoriesForProgramInterest();

    for (final category in categories) {
      selected[category] = _pickRandomKeyArea(category);
    }

    return selected;
  }

  Map<String, String> _generateFocusModeCoverage(String focusCategory) {
    final Map<String, String> selected = {};
    final categories = _categoriesForProgramInterest();

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

    final pooledQuestions = _quickPracticeFromSavedPool();
    if (pooledQuestions.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quick Practice needs saved tests with available questions.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final results = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionScreen(
          questions: pooledQuestions,
          hasUnlimitedAccess: hasUnlimitedAccess || hasGraceAccess,
          strictTimingEnabled: _strictTimingEnabled,
          recordResults: false,
          testMode: 'quickPractice',
          zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
        ),
      ),
    );

    if (results != null && mounted) {
      if (results is Map<String, dynamic> && results['nextAction'] == 'pause') {
        await _savePausedSessionFromResult(results);
        return;
      }
      await _updateTestResults(results);
    }
  }

  Future<void> _resumePausedSession(_PausedQuizSession session) async {
    if (_isPausedSessionExpired(session)) {
      await _clearPausedQuizSession(session.testMode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'That paused session expired at midnight and was cleared.',
              style: GoogleFonts.outfit(),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final creditsBeforeResume = remainingFreeTests;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionScreen(
          questions: session.questions,
          hasUnlimitedAccess: hasUnlimitedAccess || hasGraceAccess,
          strictTimingEnabled: _strictTimingEnabled,
          recordResults: session.recordResults,
          testMode: session.testMode,
          zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
          initialIndex: session.currentIndex,
          initialCorrectCount: session.correctCount,
          initialElapsedSeconds: session.elapsedSeconds,
          initialAttempts: session.assessmentAttempts,
        ),
      ),
    );

    if (mounted && remainingFreeTests < creditsBeforeResume) {
      setState(() {
        remainingFreeTests = creditsBeforeResume;
      });
      unawaited(_persistDailyFreeTests());
      unawaited(_syncAllProgressToRtdb());
    }

    if (!mounted || result == null) return;
    if (result is Map<String, dynamic> && result['nextAction'] == 'pause') {
      await _savePausedSessionFromResult(result);
      return;
    }

    await _clearPausedQuizSession(session.testMode);

    if (result is Map<String, dynamic>) {
      final nextAction = result['nextAction'];
      await _updateTestResults(result);
      if (nextAction == 'menu') {
        setState(() {
          currentScreen = session.testMode == 'reviewMistakes' ? 0 : 2;
        });
      }
    }
  }

  Future<void> _showContinueSessionsDialog() async {
    if (_isLoadingPausedQuizSessions) return;

    await _purgeExpiredPausedSessionsIfNeeded();
    if (!mounted) return;
    if (_pausedQuizSessions.isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_menuPastelPanel, _menuPastelLeafSoft, 0.18)!,
                _menuPastelPanel,
                Color.lerp(_menuPastelPanel, _menuPastelYellow, 0.12)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _menuPastelGlassBorder),
            boxShadow: [
              BoxShadow(
                color: _menuPastelLeaf.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Continue Session',
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isLoadingPausedQuizSessions
                    ? 'Retrieving your unfinished sessions...'
                    : 'Choose an unfinished mode to resume.',
                style: GoogleFonts.outfit(
                  color: _menuPastelTextSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (_isLoadingPausedQuizSessions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: _menuPastelLeaf,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Retrieving your unfinished sessions...',
                          style: GoogleFonts.outfit(
                            color: _menuPastelTextSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: _pausedQuizSessions.entries.map((entry) {
                      final mode = entry.key;
                      final session = entry.value;
                      final progress =
                          '${session.currentIndex + 1}/${session.questions.length}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: _menuPastelLeaf,
                        ),
                        title: Text(
                          _modeLabel(mode),
                          style: GoogleFonts.outfit(
                            color: _menuPastelText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Progress: $progress',
                          style: GoogleFonts.outfit(
                            color: _menuPastelTextSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          await _resumePausedSession(session);
                        },
                      );
                    }).toList(),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _menuPastelCream,
                    foregroundColor: _menuPastelText,
                    side: const BorderSide(color: _menuPastelGlassBorder),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startReviewMistakesSession() async {
    if (_mistakeQueue.isEmpty) return;

    final selected = _mistakeQueue.take(15).toList()..shuffle();
    final reviewQuestions =
        selected.map((record) => record.question.shuffled()).toList();
    if (reviewQuestions.isEmpty) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionScreen(
          questions: reviewQuestions,
          hasUnlimitedAccess: hasUnlimitedAccess || hasGraceAccess,
          strictTimingEnabled: _strictTimingEnabled,
          recordResults: false,
          testMode: 'reviewMistakes',
          zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result is Map<String, dynamic> && result['nextAction'] == 'pause') {
      await _savePausedSessionFromResult(result);
      return;
    }

    final consumed = min(15, _mistakeQueue.length);
    if (consumed > 0) {
      setState(() {
        _mistakeQueue.removeRange(0, consumed);
      });
      unawaited(_persistMistakeQueue());
    }

    if (result is Map<String, dynamic>) {
      final nextAction = result['nextAction'];
      if (nextAction == 'playAgain') {
        await _startReviewMistakesSession();
        return;
      }
      if (nextAction == 'menu' && mounted) {
        setState(() {
          currentScreen = 0;
        });
      }
    }
  }

  void _showReviewMistakesDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_menuPastelPanel, _menuPastelLeafSoft, 0.18)!,
                _menuPastelPanel,
                Color.lerp(_menuPastelPanel, _menuPastelYellow, 0.14)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _menuPastelGlassBorder),
            boxShadow: [
              BoxShadow(
                color: _menuPastelLeaf.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Review Mistakes',
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLoadingMistakeQueue
                    ? 'Retrieving saved mistakes...'
                    : '${_mistakeQueue.length} missed questions saved',
                style: GoogleFonts.outfit(
                  color: _menuPastelTextSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoadingMistakeQueue)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        color: _menuPastelLeaf,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Retrieving saved mistakes...',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: _menuPastelTextSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_mistakeQueue.isEmpty)
                Text(
                  'No mistakes saved yet. Finish quizzes to build your review queue.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _mistakeQueue.length.clamp(0, 6),
                    itemBuilder: (context, index) {
                      final item = _mistakeQueue[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.timedOut
                              ? Icons.timer_off_rounded
                              : Icons.cancel_outlined,
                          color: const Color(0xFFBE8E75),
                          size: 18,
                        ),
                        title: Text(
                          item.question.category,
                          style: GoogleFonts.outfit(
                            color: _menuPastelText,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          item.question.question,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: _menuPastelTextSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _menuPastelCream,
                        foregroundColor: _menuPastelText,
                        side: const BorderSide(color: _menuPastelGlassBorder),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _mistakeQueue.isEmpty
                          ? null
                          : () async {
                              setState(() {
                                _mistakeQueue.clear();
                              });
                              await _persistMistakeQueue();
                              if (mounted) Navigator.pop(context);
                            },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFF7E8E2),
                        foregroundColor: const Color(0xFFBE8E75),
                        side: const BorderSide(color: Color(0xFFE2C3B6)),
                      ),
                      child: Text(
                        'Clear',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _mistakeQueue.isEmpty
                          ? null
                          : () async {
                              Navigator.pop(context);
                              await _startReviewMistakesSession();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _menuPastelLeaf,
                        foregroundColor: _menuPastelCream,
                      ),
                      child: Text(
                        'Start',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Challenge Mode (10 advanced questions)
  Future<void> _startChallengeMode() async {
    if (_isLaunchingChallengeMode) return;

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

    _isLaunchingChallengeMode = true;
    var showedPreparingDialog = false;
    try {
      if ((_cachedChallengeQuestions?.length ?? 0) < 10 &&
          _isPrimingChallengeCache) {
        showedPreparingDialog = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black54,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: PnleTheme.bgBottom.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Preparing Challenge Mode...',
                    style: GoogleFonts.outfit(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        );
        await _waitForChallengeCachePrime();
        if (showedPreparingDialog &&
            mounted &&
            Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
          showedPreparingDialog = false;
        }
        if (!mounted) return;
      }

      await _launchChallengeMode();
    } finally {
      if (showedPreparingDialog &&
          mounted &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _isLaunchingChallengeMode = false;
    }
  }

  Future<void> _startOrResumeMode({
    required String mode,
    required Future<void> Function() onStartNew,
  }) async {
    await _purgeExpiredPausedSessionsIfNeeded();
    if (!mounted) return;
    final existing = _pausedQuizSessions[mode];
    if (existing == null) {
      await onStartNew();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_menuPastelPanel, _menuPastelLeafSoft, 0.2)!,
                _menuPastelPanel,
                Color.lerp(_menuPastelPanel, _menuPastelYellow, 0.18)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _menuPastelGlassBorder, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: _menuPastelLeaf.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _modeLabel(mode),
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You already have an unfinished session (${existing.currentIndex + 1}/${existing.questions.length}).',
                style: GoogleFonts.outfit(
                  color: _menuPastelTextSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Paused sessions reset at midnight with daily tasks.',
                style: GoogleFonts.outfit(
                  color: _menuPastelTextSoft.withValues(alpha: 0.86),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'continue'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _menuPastelGlassBorder,
                        ),
                        backgroundColor: _menuPastelCream,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Continue',
                        style: GoogleFonts.outfit(
                          color: _menuPastelText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, 'new'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _menuPastelLeaf,
                        foregroundColor: _menuPastelCream,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Start New',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'continue') {
      await _resumePausedSession(existing);
      return;
    }

    await _clearPausedQuizSession(mode);
    await onStartNew();
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
    if ((_cachedChallengeQuestions?.length ?? 0) < 10) {
      final categories = _categoriesForProgramInterest();
      if (categories.isNotEmpty) {
        final focusCategory = categories[Random().nextInt(categories.length)];
        final challengeMap = _buildChallengeCategoryMap(focusCategory);
        final seededQuestions = await _takeSeedQuestions(
          'challenge',
          challengeMap,
        );
        if (seededQuestions.length >= 10 && mounted) {
          debugPrint('[SeedPool] challenge served from pool.');
          setState(() {
            _cachedChallengeQuestions = seededQuestions.take(10).toList();
          });
          unawaited(_persistFocusAndChallengeCaches());
        } else {
          await _ensureSeedPoolBucketsForRequest(
            mode: 'challenge',
            categoryMap: challengeMap,
          );
        }
      }
    }

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

      if (!mounted) return;

      final results = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionScreen(
            questions: cachedQuestions,
            hasUnlimitedAccess: hasUnlimitedAccess || hasGraceAccess,
            strictTimingEnabled: _strictTimingEnabled,
            recordResults: false,
            testMode: 'challenge',
            zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
          ),
        ),
      );

      if (results != null && mounted) {
        if (results is Map<String, dynamic> &&
            results['nextAction'] == 'pause') {
          await _savePausedSessionFromResult(results);
          return;
        }
        await _updateTestResults(results);
      }
      return;
    }

    // Show simple loading dialog
    debugPrint('[SeedPool] challenge falling back to live generation.');
    if (!mounted) return;
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
                color: PnleTheme.warning.withValues(alpha: 0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: PnleTheme.warning, size: 18),
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
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(PnleTheme.warning),
              ),
              const SizedBox(height: 14),
              Text(
                'Preparing advanced questions...',
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
      // Primary/Fallback uses Gemini-first; all other users use DeepSeek generation flow.
      final useGemini = hasUnlimitedAccess || hasGraceAccess;
      // Generate random category focus for challenge
      final categories = _categoriesForProgramInterest();
      final focusCategory = categories[Random().nextInt(categories.length)];
      final prompt = useGemini
          ? _buildChallengeModePrompt(focusCategory)
          : _buildFastChallengeModePrompt(focusCategory);

      final categoryMap = _buildChallengeCategoryMap(focusCategory);

      late final List<Question> questions;
      if (useGemini) {
        if (GEMINI_API_KEY.trim().isEmpty) {
          throw Exception(
              'Challenge mode is temporarily unavailable without a configured API key.');
        }
        try {
          final service = QuestionGenerationService(apiKey: GEMINI_API_KEY);
          questions = await service.generateQuestions(prompt, programInterest,
              categoryMap: categoryMap);
        } catch (e) {
          if (DEEPSEEK_API_KEY.trim().isEmpty) {
            throw Exception(
                'Challenge mode is temporarily unavailable while offline and no fallback key is configured.');
          }

          final service = _buildDeepSeekService(fastMode: false);
          questions = await service.generateQuestions(prompt, programInterest,
              categoryMap: categoryMap);
        }
      } else {
        if (DEEPSEEK_API_KEY.trim().isEmpty) {
          throw Exception(
              'Challenge mode is temporarily unavailable while offline and no fallback key is configured.');
        }
        final service = _buildDeepSeekService(fastMode: true, tokenCap: 2200);
        questions = await service.generateQuestions(prompt, programInterest,
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
              hasUnlimitedAccess: hasUnlimitedAccess || hasGraceAccess,
              strictTimingEnabled: _strictTimingEnabled,
              recordResults: false,
              testMode: 'challenge',
              zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
            ),
          ),
        );

        if (results != null && mounted) {
          if (results is Map<String, dynamic> &&
              results['nextAction'] == 'pause') {
            await _savePausedSessionFromResult(results);
            return;
          }
          await _updateTestResults(results);
        }

        unawaited(_primeChallengeCacheIfEligible(force: true));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Unable to prepare challenge mode: ${e.toString()}')),
        );
      }
    }
  }

  List<String> _categoriesForProgramInterest() {
    return pnleCategories;
  }

  List<_QuizActivityRecord> _recentTimedExamRecords({int count = 6}) {
    return _quizActivityRecords
        .where((record) => record.mode == 'timedExam')
        .take(count)
        .toList();
  }

  AcetAssessment _fallbackAssessmentFromRecord(_QuizActivityRecord record) {
    final averageTime = record.questionCount > 0
        ? record.elapsedSeconds / record.questionCount
        : 0.0;
    final unansweredAnswers =
        record.timedOutCount.clamp(0, record.questionCount);
    final wrongAnswers = max(
      0,
      record.questionCount - record.correctCount - unansweredAnswers,
    );
    final speedFactor = (1.15 - ((averageTime - 10) * 0.02)).clamp(0.70, 1.05);
    final categoryStats = <String, AcetCategoryAssessment>{};

    for (final entry in record.categoryTotal.entries) {
      final category = entry.key;
      final total = entry.value;
      final correct = record.categoryCorrect[category] ?? 0;
      final accuracy = total > 0 ? (correct / total) * 100 : 0.0;
      categoryStats[category] = AcetCategoryAssessment(
        category: category,
        correctAnswers: correct,
        totalQuestions: total,
        accuracyPercent: accuracy,
        averageTimePerQuestionSeconds: averageTime,
        statusLabel: _acetAssessmentService.categoryStatusLabel(
          accuracyPercent: accuracy,
          averageTimeSeconds: averageTime,
        ),
      );
    }

    return AcetAssessment(
      totalQuestions: record.questionCount,
      correctAnswers: record.correctCount,
      wrongAnswers: wrongAnswers,
      unansweredAnswers: unansweredAnswers,
      timedOutCount: record.timedOutCount,
      accuracyPercent: record.scorePercent,
      averageTimePerQuestionSeconds: averageTime,
      efficiencyScore: (record.scorePercent * speedFactor).clamp(0.0, 100.0),
      readinessLabel: record.scorePercent >= 80 && averageTime <= 25
          ? 'ACET Ready'
          : (record.scorePercent >= 70 && averageTime <= 27
              ? 'Competitive'
              : (record.scorePercent >= 55 ? 'Developing' : 'Not Ready')),
      fastAnswerCount: 0,
      moderateAnswerCount: 0,
      slowAnswerCount: 0,
      questionsPerMinute: record.elapsedSeconds > 0
          ? (record.questionCount * 60) / record.elapsedSeconds
          : 0.0,
      insightMessage: '',
      recommendedFocusCategory: '',
      perCategoryStats: categoryStats,
    );
  }

  List<AcetAssessment> _recentAssessments({int count = 10, String? mode}) {
    final records = _quizActivityRecords
        .where((record) => mode == null || record.mode == mode)
        .take(count)
        .toList();
    return records
        .map((record) =>
            record.assessment ?? _fallbackAssessmentFromRecord(record))
        .toList();
  }

  AcetAssessment? _recentAssessmentSummary({int count = 10, String? mode}) {
    final assessments = _recentAssessments(count: count, mode: mode);
    if (assessments.isEmpty) return null;
    return _acetAssessmentService.mergeAssessments(assessments);
  }

  Color _readinessColorForLabel(String label) {
    switch (label) {
      case 'ACET Ready':
        return PnleTheme.success;
      case 'Competitive':
        return PnleTheme.info;
      case 'Developing':
        return PnleTheme.warning;
      default:
        return PnleTheme.danger;
    }
  }

  Map<String, dynamic> _timedReadinessMetrics({int count = 6}) {
    final summary = _recentAssessmentSummary(count: count, mode: 'timedExam');
    if (summary == null) {
      return {
        'hasData': false,
        'score': 0.0,
        'accuracy': 0.0,
        'pace': 0.0,
        'focus': 0.0,
        'sessionCount': 0,
        'label': 'No Timed Data',
        'summary':
            'Finish a few Timed Exam sessions to measure exam-speed readiness separately from content mastery.',
        'color': PnleTheme.neutral,
      };
    }

    final label = summary.readinessLabel;
    final color = _readinessColorForLabel(label);
    final averageTime = summary.averageTimePerQuestionSeconds;
    final pace =
        (100 - ((averageTime - 15).clamp(0.0, 20.0) * 3.2)).clamp(35.0, 100.0);
    final focus =
        (100 - ((summary.timedOutCount * 12).toDouble())).clamp(35.0, 100.0);
    final sessionCount = _recentTimedExamRecords(count: count).length;

    String summaryText;
    switch (label) {
      case 'ACET Ready':
        summaryText =
            'Recent timed runs show balanced speed and accuracy for ACET pressure.';
        break;
      case 'Competitive':
        summaryText =
            'Your timed performance is competitive, but a little more speed discipline can still raise efficiency.';
        break;
      case 'Developing':
        summaryText =
            'The foundation is building, but timed efficiency still needs work before full ACET pace feels stable.';
        break;
      default:
        summaryText =
            'Timed sets are still breaking down under pressure. Shorter speed drills will help before full runs.';
    }

    return {
      'hasData': true,
      'score': summary.efficiencyScore,
      'accuracy': summary.accuracyPercent,
      'pace': pace,
      'focus': focus,
      'sessionCount': sessionCount,
      'label': label,
      'summary': summaryText,
      'color': color,
    };
  }

  double _categoryPercent(String category) {
    final summary = _recentAssessmentSummary();
    final stat = summary?.perCategoryStats[category];
    if (stat != null) return stat.accuracyPercent;

    final data = categoryScores[category];
    if (data == null) return 0;
    final correct = (data['correct'] as num?)?.toInt() ?? 0;
    final total = (data['total'] as num?)?.toInt() ?? 0;
    if (total <= 0) return 0;
    return (correct / total) * 100;
  }

  int _targetForCategory(String category) {
    return _acetReadinessThresholds[category] ?? 70;
  }

  String _readinessLabel() {
    return _recentAssessmentSummary()?.readinessLabel ?? 'Not Ready';
  }

  Color _readinessColor() {
    return _readinessColorForLabel(_readinessLabel());
  }

  List<String> _recommendedKeyAreasForCategory(
    String category, {
    int count = 3,
  }) {
    final topics = keyAreas[category] ?? const <String>[];
    if (topics.isEmpty) return const <String>[];

    final now = DateTime.now();
    final seed =
        now.year * 10000 + now.month * 100 + now.day + category.hashCode;
    final shuffled = List<String>.from(topics)..shuffle(Random(seed));
    return shuffled.take(min(count, shuffled.length)).toList();
  }

  String _readinessPrimaryFeedback() {
    final summary = _recentAssessmentSummary();
    if (summary == null || summary.totalQuestions == 0) {
      return 'Finish a few full sessions so the app can assess your ACET speed, accuracy, and efficiency.';
    }

    final focusCategory = _recommendedFocusCategory();
    final focusStat = summary.perCategoryStats[focusCategory];
    final keyAreasToReview =
        _recommendedKeyAreasForCategory(focusCategory).join(', ');
    final keyAreaLine = keyAreasToReview.isEmpty
        ? ''
        : ' Recommended key areas to review now: $keyAreasToReview.';

    if (focusStat == null) {
      return summary.insightMessage;
    }

    return '${summary.insightMessage} ${focusStat.category} is currently at ${focusStat.accuracyPercent.toStringAsFixed(1)}% accuracy and ${focusStat.averageTimePerQuestionSeconds.toStringAsFixed(1)}s average time.$keyAreaLine';
  }

  String _recommendedFocusCategory() {
    final summary = _recentAssessmentSummary();
    if (summary != null && summary.totalQuestions > 0) {
      if (summary.recommendedFocusCategory.isNotEmpty) {
        return summary.recommendedFocusCategory;
      }

      final weakestStat =
          summary.perCategoryStats.values.fold<AcetCategoryAssessment?>(
        null,
        (current, candidate) {
          if (current == null) return candidate;
          final currentScore = current.accuracyPercent -
              (current.averageTimePerQuestionSeconds * 1.5);
          final candidateScore = candidate.accuracyPercent -
              (candidate.averageTimePerQuestionSeconds * 1.5);
          return candidateScore < currentScore ? candidate : current;
        },
      );

      if (weakestStat != null) {
        return weakestStat.category;
      }
    }

    final weakestCategory = _getWeakestCategory();
    return weakestCategory.isEmpty ? 'English' : weakestCategory;
  }

  Map<String, dynamic> _estimatedCompetitivenessBand() {
    final summary = _recentAssessmentSummary();
    if (summary == null || summary.totalQuestions == 0) {
      return {
        'label': 'Insufficient Data',
        'tier': 'Need More Sessions',
        'color': PnleTheme.neutral,
      };
    }

    final estimateScore = ((summary.efficiencyScore * 0.65) +
            (summary.accuracyPercent * 0.20) +
            ((100 -
                    summary.averageTimePerQuestionSeconds.clamp(0.0, 40.0) *
                        2) *
                0.15))
        .clamp(0.0, 100.0);

    if (estimateScore >= 85) {
      return {
        'label': 'ACET Ready',
        'tier': 'High Efficiency',
        'color': PnleTheme.success,
      };
    }
    if (estimateScore >= 72) {
      return {
        'label': 'Competitive',
        'tier': 'Balanced Pace',
        'color': PnleTheme.info,
      };
    }
    if (estimateScore >= 58) {
      return {
        'label': 'Developing',
        'tier': 'Needs Sharper Pace',
        'color': PnleTheme.warning,
      };
    }

    return {
      'label': 'Not Ready',
      'tier': 'Rebuild Fundamentals',
      'color': PnleTheme.danger,
    };
  }

  String _smartFeedbackSummary() {
    final summary = _recentAssessmentSummary();
    if (summary == null || summary.totalQuestions == 0) {
      return 'Finish a few sessions to unlock ACET-specific speed and efficiency feedback.';
    }

    final strong = summary.perCategoryStats.values
        .where((stat) =>
            stat.statusLabel == 'Strong' || stat.statusLabel == 'Good')
        .map((stat) => stat.category)
        .toList();
    final weak = summary.perCategoryStats.values
        .where((stat) =>
            stat.statusLabel == 'Needs Speed' ||
            stat.statusLabel == 'Needs Accuracy' ||
            stat.statusLabel == 'Weak')
        .map((stat) => stat.category)
        .toList();

    if (weak.isEmpty) {
      return 'Your recent ACET sessions are balanced. Protect that mix of speed and accuracy under pressure.';
    }
    if (strong.isEmpty) {
      return 'Your main ACET gap is in ${weak.join(', ')}. Prioritize timed repetition in those categories.';
    }
    return 'Strong areas: ${strong.join(', ')}. Priority repairs: ${weak.join(', ')}.';
  }

  String _microTipForCategory(String category) {
    switch (category) {
      case 'Mathematics':
        return 'Tip: Translate the question into numbers early so you can spend your time solving, not rereading.';
      case 'Logical Reasoning':
        return 'Tip: Lock the given facts first, then test each choice against them instead of chasing assumptions.';
      case 'Mental Ability / Abstract':
        return 'Tip: Check for more than one active pattern rule before committing to a sequence or matrix answer.';
      case 'English':
      default:
        return 'Tip: Read for structure first, then eliminate choices that distort tone, logic, or grammar.';
    }
  }

  Map<String, dynamic> _sessionInsights(Map<String, dynamic> results) {
    final assessmentRaw = results['assessment'];
    if (assessmentRaw is Map) {
      final assessment =
          AcetAssessment.fromJson(Map<String, dynamic>.from(assessmentRaw));
      final speedLabel = assessment.averageTimePerQuestionSeconds <= 15
          ? 'Fast'
          : (assessment.averageTimePerQuestionSeconds <= 25
              ? 'Moderate'
              : 'Slow');
      final focusLabel = assessment.timedOutCount >= 3
          ? 'Low focus'
          : (assessment.timedOutCount >= 1 ? 'Moderate focus' : 'Strong focus');

      return {
        'sessionTotal': assessment.totalQuestions,
        'sessionAccuracy': assessment.accuracyPercent,
        'elapsedSeconds': (assessment.averageTimePerQuestionSeconds *
                assessment.totalQuestions)
            .round(),
        'secondsPerQuestion': assessment.averageTimePerQuestionSeconds,
        'questionsPerMinute': assessment.questionsPerMinute,
        'timedOutCount': assessment.timedOutCount,
        'speedLabel': speedLabel,
        'focusLabel': focusLabel,
        'behaviorMessage': assessment.insightMessage,
        'efficiencyScore': assessment.efficiencyScore,
        'readinessLabel': assessment.readinessLabel,
        'recommendedFocusCategory': assessment.recommendedFocusCategory,
        'assessment': assessment,
      };
    }

    final correctRaw = results['correctCount'];
    final totalRaw = results['totalCount'];
    final elapsedRaw = results['elapsedSeconds'];
    final mistakesRaw = results['mistakes'];

    int sessionTotal = 0;
    int sessionCorrect = 0;

    if (totalRaw is Map) {
      sessionTotal = totalRaw.values
          .whereType<num>()
          .fold<int>(0, (sum, value) => sum + value.toInt());
    }
    if (correctRaw is Map) {
      sessionCorrect = correctRaw.values
          .whereType<num>()
          .fold<int>(0, (sum, value) => sum + value.toInt());
    }

    final elapsedSeconds =
        (elapsedRaw is num ? elapsedRaw.toInt() : 0).clamp(0, 7200);
    final effectiveElapsed = elapsedSeconds > 0
        ? elapsedSeconds
        : (sessionTotal > 0 ? sessionTotal * 35 : 0);
    final sessionAccuracy =
        sessionTotal > 0 ? (sessionCorrect / sessionTotal) * 100 : 0.0;
    final secondsPerQuestion = sessionTotal > 0 && effectiveElapsed > 0
        ? effectiveElapsed / sessionTotal
        : 0.0;
    final questionsPerMinute =
        effectiveElapsed > 0 ? (sessionTotal * 60) / effectiveElapsed : 0.0;

    int timedOutCount = 0;
    if (mistakesRaw is List) {
      for (final item in mistakesRaw) {
        if (item is Map && item['timedOut'] == true) {
          timedOutCount++;
        }
      }
    }

    final speedLabel = secondsPerQuestion > 50
        ? 'Too slow'
        : (secondsPerQuestion < 25 ? 'Too fast' : 'Balanced');

    final focusLabel = timedOutCount >= 3
        ? 'Low focus'
        : (timedOutCount >= 1 ? 'Moderate focus' : 'Strong focus');

    final behaviorMessage = secondsPerQuestion > 50
        ? 'You spent too long on several items. In ACET, this can cost multiple answer opportunities.'
        : (secondsPerQuestion < 25 && sessionAccuracy < 70
            ? 'You moved very fast but accuracy dropped. Slow down slightly on hard items.'
            : 'Your pacing is close to exam pace. Maintain skip-and-return discipline.');

    return {
      'sessionTotal': sessionTotal,
      'sessionAccuracy': sessionAccuracy,
      'elapsedSeconds': elapsedSeconds,
      'secondsPerQuestion': secondsPerQuestion,
      'questionsPerMinute': questionsPerMinute,
      'timedOutCount': timedOutCount,
      'speedLabel': speedLabel,
      'focusLabel': focusLabel,
      'behaviorMessage': behaviorMessage,
    };
  }

  Widget _buildCourseReadinessCard() {
    final categories = _categoriesForProgramInterest();
    final totalAvg = _calculateTotalAverage();
    final readiness = _readinessLabel();
    final readinessColor = _readinessColor();
    final competitiveness = _estimatedCompetitivenessBand();
    final competitivenessColor = competitiveness['color'] as Color;
    final timedReadiness = _timedReadinessMetrics();
    final timedReadinessColor = timedReadiness['color'] as Color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: readinessColor.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, color: _menuPastelText, size: 18),
              const SizedBox(width: 8),
              Text(
                'Study Preference',
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showSpecializationSelectionDialog,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _menuPastelCream,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _menuPastelGlassBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      programInterest.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: _menuPastelText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.edit_rounded,
                      color: _menuPastelTextSoft,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.flag_rounded, color: _menuPastelText, size: 18),
              const SizedBox(width: 8),
              Text(
                'ACET Readiness',
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: readinessColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: readinessColor.withValues(alpha: 0.42)),
            ),
            child: Text(
              readiness.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: readinessColor,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _menuPastelCream,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _menuPastelGlassBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.score_rounded,
                  color: totalAvg >= 65
                      ? PnleTheme.success
                      : (totalAvg >= 50
                          ? PnleTheme.warning
                          : PnleTheme.dangerSoft),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Accuracy',
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${totalAvg.toStringAsFixed(1)}%',
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: timedReadinessColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: timedReadinessColor.withValues(alpha: 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      color: timedReadinessColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Timed Efficiency',
                      style: GoogleFonts.outfit(
                        color: _menuPastelTextSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timedReadiness['hasData'] as bool
                          ? '${(timedReadiness['score'] as double).toStringAsFixed(1)}%'
                          : 'Pending',
                      style: GoogleFonts.outfit(
                        color: _menuPastelText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  timedReadiness['summary'] as String,
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Category Snapshot',
            style: GoogleFonts.outfit(
              color: _menuPastelText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...categories.map(_buildReadinessMiniCategory),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: competitivenessColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: competitivenessColor.withValues(alpha: 0.48),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.leaderboard_rounded,
                  color: competitivenessColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${competitiveness['label']} • ${competitiveness['tier']}',
                    style: GoogleFonts.outfit(
                      color: _menuPastelText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _readinessPrimaryFeedback(),
            style: GoogleFonts.outfit(
              color: _menuPastelText,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These readiness bands are in-app ACET estimates based on your recent accuracy, speed, and efficiency. They are not official admission cutoffs.',
            style: GoogleFonts.outfit(
              color: _menuPastelTextSoft,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessMiniCategory(String category) {
    final data = categoryScores[category]!;
    final correct = data['correct'] as int;
    final total = data['total'] as int;
    final percent = total > 0 ? (correct / total) * 100 : 0.0;
    final target = _targetForCategory(category);
    final meetsTarget = percent >= target;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${percent.toStringAsFixed(0)}% / $target%',
                style: GoogleFonts.outfit(
                  color:
                      meetsTarget ? _menuPastelLeaf : const Color(0xFFB78368),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: _menuPastelLeafSoft.withValues(alpha: 0.7),
              color: meetsTarget ? PnleTheme.success : PnleTheme.warning,
            ),
          ),
        ],
      ),
    );
  }

  String _getWeakestCategory() {
    final categories = _categoriesForProgramInterest();
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
      return '${_getGreeting()} there!';
    }
    return '${_getGreeting()} $name!';
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

  Future<void> _startTimedExamMode() async {
    _isFocusMode = false;
    _focusCategory = null;
    _currentTestCoverage = _generateTestCoverage();
    _showGenerationDialog(
      modeLabel: 'TIMED EXAM',
      launchTestMode: 'timedExam',
      sourceMode: 'timedExam',
    );
  }

  void _showGenerationDialog({
    String? modeLabel,
    String launchTestMode = 'randomQuiz',
    String? sourceMode,
  }) {
    final bool activeIsFocusMode = _isFocusMode;
    final String? activeFocusCategory = _focusCategory;
    final Map<String, String>? activeCoverage = _currentTestCoverage == null
        ? null
        : Map<String, String>.from(_currentTestCoverage!);

    final effectiveTestMode = activeIsFocusMode ? 'focusMode' : launchTestMode;
    final effectiveSourceMode =
        activeIsFocusMode ? 'focusMode' : (sourceMode ?? launchTestMode);

    _activeGenerationMode = effectiveTestMode;

    final effectiveModeLabel = modeLabel ??
        _buildGenerationModeLabel(
          isFocusMode: activeIsFocusMode,
          focusCategory: activeFocusCategory,
        );

    _isStartingGeneratedSession = false;

    unawaited(() async {
      final preparedLocally = await _tryPrepareLocalSessionForGeneration(
        useFocusMode: activeIsFocusMode,
        focusCategory: activeFocusCategory,
        effectiveTestMode: effectiveTestMode,
      );
      if (!preparedLocally || !mounted) {
        if (mounted) {
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

                  unawaited(_primeMissingCachesAsNeeded());
                },
                hasUnlimitedAccess: hasUnlimitedAccess,
                isFocusMode: activeIsFocusMode,
                focusCategory: activeFocusCategory,
                modeLabel: effectiveModeLabel,
                onStart: () async {
                  await _startPreparedGeneratedSession(
                    activeIsFocusMode: activeIsFocusMode,
                    activeFocusCategory: activeFocusCategory,
                    activeCoverage: activeCoverage,
                    effectiveSourceMode: effectiveSourceMode,
                    effectiveTestMode: effectiveTestMode,
                    dialogContext: dialogContext,
                  );
                },
              );
            },
          );
        }
        return;
      }

      await _startPreparedGeneratedSession(
        activeIsFocusMode: activeIsFocusMode,
        activeFocusCategory: activeFocusCategory,
        activeCoverage: activeCoverage,
        effectiveSourceMode: effectiveSourceMode,
        effectiveTestMode: effectiveTestMode,
      );
    }());
  }

  Future<bool> _tryPrepareLocalSessionForGeneration({
    required bool useFocusMode,
    required String? focusCategory,
    required String effectiveTestMode,
  }) async {
    await _ensureSeedPoolReadyForGeneration();
    _usedCachedRandomForLastGeneration = false;

    if (useFocusMode && focusCategory != null) {
      final categoryMap = _buildFocusCategoryMap(focusCategory);
      final seededQuestions = await _takeSeedQuestions(
        'focusMode',
        categoryMap,
      );
      if (seededQuestions.length >= 15) {
        debugPrint(
            '[SeedPool] Focus mode served locally before showing loading dialog.');
        _generatedQuestions =
            seededQuestions.take(15).map((q) => q.shuffled()).toList();
        return true;
      }

      final cachedFocus = _cachedFocusQuestions[focusCategory];
      if (cachedFocus != null && cachedFocus.length >= 15) {
        debugPrint(
            '[SeedPool] Focus mode served from local cache before showing loading dialog.');
        _generatedQuestions =
            cachedFocus.take(15).map((q) => q.shuffled()).toList();
        _cachedFocusQuestions.remove(focusCategory);
        unawaited(_persistFocusAndChallengeCaches());
        return true;
      }
      return false;
    }

    final seedMode =
        effectiveTestMode == 'timedExam' ? 'timedExam' : 'randomQuiz';
    final randomLikeMap = _buildRandomCategoryMap();

    final seededQuestions = await _takeSeedQuestions(
      seedMode,
      randomLikeMap,
    );
    if (seededQuestions.length >= 15) {
      debugPrint(
          '[SeedPool] $seedMode served locally before showing loading dialog.');
      _generatedQuestions =
          seededQuestions.take(15).map((q) => q.shuffled()).toList();
      return true;
    }

    if ((_cachedRandomQuizQuestions?.length ?? 0) >= 15) {
      final cachedQuestions = _cachedRandomQuizQuestions!;
      final cachedVisualCount = cachedQuestions
          .where((q) => (q.imageAssetPath?.isNotEmpty ?? false))
          .length;
      if (cachedVisualCount > 1) {
        // Legacy visual-test cache should not be reused for normal random mode.
        await _clearRandomQuizCache();
      } else {
        debugPrint(
            '[SeedPool] Random cache served locally before showing loading dialog.');
        _usedCachedRandomForLastGeneration = true;
        if (_cachedRandomQuizCoverage != null) {
          _currentTestCoverage =
              Map<String, String>.from(_cachedRandomQuizCoverage!);
        }
        _generatedQuestions =
            cachedQuestions.take(15).map((q) => q.shuffled()).toList();
        return true;
      }
    }

    return false;
  }

  bool _isVisualInjectionEligibleMode(String testMode) {
    return testMode == 'randomQuiz' ||
        testMode == 'focusMode' ||
        testMode == 'challenge' ||
        testMode == 'timedExam';
  }

  bool _sessionHasAbstractReasoning(List<Question> questions) {
    return questions
        .any((q) => q.category.trim() == 'Mental Ability / Abstract');
  }

  String _resolveVisualAbstractAssetPath() {
    final randomModeConfig = _examConfigService.getModeConfig(
      _activeExamId,
      'randomQuiz',
    );
    final configured = randomModeConfig?.localQuestionAssetPath;
    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }
    return _defaultVisualAbstractAssetPath;
  }

  Future<List<Question>> _loadVisualAbstractPool() async {
    final cached = _visualAbstractQuestionPool;
    if (cached != null) {
      return cached;
    }

    try {
      final loaded = await _localVisualQuestionService.loadQuestions(
        assetPath: _resolveVisualAbstractAssetPath(),
      );
      _visualAbstractQuestionPool = loaded;
      return loaded;
    } catch (e) {
      debugPrint('[VisualPool] Failed to load visual pool: $e');
      _visualAbstractQuestionPool = const <Question>[];
      return _visualAbstractQuestionPool!;
    }
  }

  Future<void> _loadUsedVisualAbstractPoolIds() async {
    if (_usedVisualAbstractPoolLoaded) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_usedVisualAbstractPoolIdsPrefsKey);
      if (payload != null && payload.isNotEmpty) {
        final decoded = jsonDecode(payload);
        if (decoded is List) {
          _usedVisualAbstractPoolIds
            ..clear()
            ..addAll(decoded.whereType<String>().map((e) => e.trim()));
        }
      }
    } catch (e) {
      debugPrint('[VisualPool] Failed to load used IDs: $e');
      _usedVisualAbstractPoolIds.clear();
    }

    _usedVisualAbstractPoolLoaded = true;
  }

  Future<void> _persistUsedVisualAbstractPoolIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(_usedVisualAbstractPoolIds.toList());
      await prefs.setString(_usedVisualAbstractPoolIdsPrefsKey, payload);
    } catch (e) {
      debugPrint('[VisualPool] Failed to persist used IDs: $e');
    }
  }

  String _visualPoolIdForQuestion(Question question) {
    final imagePath = question.imageAssetPath?.trim();
    if (imagePath != null && imagePath.isNotEmpty) {
      return imagePath;
    }
    return 'visual-${question.number}-${question.question.hashCode}';
  }

  Future<Question?> _pickVisualAbstractQuestionForSession() async {
    final pool = await _loadVisualAbstractPool();
    if (pool.isEmpty) {
      debugPrint('[VisualPool] Selection skipped: pool is empty.');
      return null;
    }

    await _loadUsedVisualAbstractPoolIds();

    var available = pool
        .where(
          (q) =>
              !_usedVisualAbstractPoolIds.contains(_visualPoolIdForQuestion(q)),
        )
        .toList(growable: false);

    if (available.isEmpty) {
      debugPrint(
        '[VisualPool] All items were used. Resetting used set before next pick.',
      );
      _usedVisualAbstractPoolIds.clear();
      await _persistUsedVisualAbstractPoolIds();
      available = List<Question>.from(pool);
    }

    if (available.isEmpty) {
      return null;
    }

    final random = Random(DateTime.now().microsecondsSinceEpoch);
    final selected = available[random.nextInt(available.length)];
    final selectedId = _visualPoolIdForQuestion(selected);

    _usedVisualAbstractPoolIds.add(selectedId);
    await _persistUsedVisualAbstractPoolIds();

    debugPrint(
      '[VisualPool] Selected item id=$selectedId number=${selected.number} used=${_usedVisualAbstractPoolIds.length}/${pool.length} remaining=${pool.length - _usedVisualAbstractPoolIds.length}',
    );

    return selected;
  }

  Future<void> _injectVisualAbstractQuestionIfNeeded({
    required String effectiveTestMode,
  }) async {
    if (_generatedQuestions.isEmpty) {
      return;
    }

    if (!_isVisualInjectionEligibleMode(effectiveTestMode)) {
      return;
    }

    if (!_sessionHasAbstractReasoning(_generatedQuestions)) {
      return;
    }

    final existingVisualCount = _generatedQuestions
        .where((q) => (q.imageAssetPath?.isNotEmpty ?? false))
        .length;
    if (existingVisualCount > 0) {
      return;
    }

    final abstractIndexes = <int>[];
    for (var i = 0; i < _generatedQuestions.length; i++) {
      final question = _generatedQuestions[i];
      if (question.category.trim() == 'Mental Ability / Abstract') {
        abstractIndexes.add(i);
      }
    }
    if (abstractIndexes.isEmpty) {
      return;
    }

    final visual = await _pickVisualAbstractQuestionForSession();
    if (visual == null) {
      debugPrint(
        '[VisualPool] Injection skipped for mode=$effectiveTestMode: no visual item selected.',
      );
      return;
    }

    final random = Random(DateTime.now().millisecondsSinceEpoch);
    final targetIndex = abstractIndexes[random.nextInt(abstractIndexes.length)];
    final originalQuestion = _generatedQuestions[targetIndex];
    final selectedId = _visualPoolIdForQuestion(visual);

    final injected = Question(
      number: originalQuestion.number,
      category: 'Mental Ability / Abstract',
      question: visual.question,
      imageAssetPath: visual.imageAssetPath,
      choices: visual.choices,
      answer: visual.answer,
      explanation: visual.explanation,
      source: visual.source,
    ).shuffled();

    _generatedQuestions[targetIndex] = injected;

    debugPrint(
      '[VisualPool] Injected mode=$effectiveTestMode id=$selectedId atIndex=$targetIndex replacingQuestionNumber=${originalQuestion.number}',
    );
  }

  Future<void> _startPreparedGeneratedSession({
    required bool activeIsFocusMode,
    required String? activeFocusCategory,
    required Map<String, String>? activeCoverage,
    required String effectiveSourceMode,
    required String effectiveTestMode,
    BuildContext? dialogContext,
  }) async {
    if (_isStartingGeneratedSession) {
      return;
    }

    _isStartingGeneratedSession = true;
    try {
      if (!_consumeFreeSessionAllowance()) {
        return;
      }

      if (_usedCachedRandomForLastGeneration) {
        await _clearRandomQuizCache();
      }

      if (!mounted) return;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }

      await _injectVisualAbstractQuestionIfNeeded(
        effectiveTestMode: effectiveTestMode,
      );

      _addSavedSession(
        _generatedQuestions,
        activeCoverage,
        sourceMode: effectiveSourceMode,
      );

      _isFocusMode = false;
      _focusCategory = null;

      unawaited(_primeMissingCachesAsNeeded());

      final results = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionScreen(
            questions: _generatedQuestions,
            hasUnlimitedAccess: hasUnlimitedAccess || hasGraceAccess,
            strictTimingEnabled: _strictTimingEnabled,
            recordResults: true,
            testMode: effectiveTestMode,
            zeroAdSessionsRemaining: _zeroAdSessionsRemaining,
          ),
        ),
      );

      if (results is Map<String, dynamic> && mounted) {
        if (results['nextAction'] == 'pause') {
          await _savePausedSessionFromResult(results);
          return;
        }

        final nextAction = results['nextAction'];
        await _updateTestResults(results);
        if (nextAction == 'playAgain') {
          if (effectiveTestMode == 'timedExam') {
            _startTimedExamMode();
            return;
          }
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
      } else if (results == 'playAgain' && mounted) {
        if (effectiveTestMode == 'timedExam') {
          _startTimedExamMode();
          return;
        }
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
        setState(() {
          currentScreen = 2;
        });
      } else if (results != null && mounted) {
        await _updateTestResults(results);
      }
    } finally {
      _isStartingGeneratedSession = false;
    }
  }

  bool _consumeFreeSessionAllowance() {
    final now = DateTime.now();
    if (_lastSessionConsumeAt != null &&
        now.difference(_lastSessionConsumeAt!) <
            const Duration(milliseconds: 700)) {
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
    _lastSessionConsumeAt = now;
    unawaited(_persistDailyFreeTests());
    if (_isOnline) {
      unawaited(_syncAllProgressToRtdb());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Offline session started. Your local session credit was saved and will sync when internet reconnects.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Decrement zero-ad sessions for Random Quiz / Focus Mode
    if (_zeroAdSessionsRemaining > 0) {
      _zeroAdSessionsRemaining--;
      _persistZeroAdSessions();
      if (_zeroAdSessionsRemaining <= 0) {
        unawaited(_primeMissingCachesAsNeeded());
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
    final resolvedTitle = switch (sourceMode) {
      'challenge' => 'Challenge Mode',
      'timedExam' => 'Timed Exam',
      _ => title,
    };
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(_menuPastelPanel, _menuPastelLeafSoft, 0.2)!,
                      _menuPastelPanel,
                      Color.lerp(_menuPastelPanel, _menuPastelYellow, 0.16)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _menuPastelGlassBorder,
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _menuPastelLeaf.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
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
                            color: _menuPastelLeafSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _menuPastelLeaf.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Icon(
                            Icons.history_rounded,
                            color: _menuPastelLeaf,
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
                                  color: _menuPastelText,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              ),
                              Text(
                                _isLoadingSavedSessions
                                    ? 'Retrieving saved tests...'
                                    : '${_savedSessions.length}/$_maxSavedSessions tests saved',
                                style: GoogleFonts.outfit(
                                  color: _menuPastelTextSoft,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
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
                              color: _menuPastelCream,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _menuPastelGlassBorder,
                              ),
                            ),
                            child: Icon(
                              Icons.close,
                              color: _menuPastelTextSoft,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(
                      color: _menuPastelGlassBorder,
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 20),
                    // Notice about saved tests
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7EFCF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFD9C59C),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: const Color(0xFFB28D4B),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saved tests are stored locally. They will be deleted if you reinstall the app or clear app data.',
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Content
                    if (_isLoadingSavedSessions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(
                              color: _menuPastelLeaf,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Retrieving saved tests...',
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please wait while local saved tests are loaded.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: _menuPastelTextSoft,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_savedSessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 64,
                              color: _menuPastelTextSoft.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No saved tests yet',
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Complete a quiz to save it here',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: _menuPastelTextSoft,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
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
                                  color:
                                      PnleTheme.danger.withValues(alpha: 0.8),
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
                                          hasUnlimitedAccess:
                                              hasUnlimitedAccess ||
                                                  hasGraceAccess,
                                          strictTimingEnabled:
                                              _strictTimingEnabled,
                                          recordResults: false,
                                          testMode: 'previous',
                                          zeroAdSessionsRemaining:
                                              _zeroAdSessionsRemaining,
                                        ),
                                      ),
                                    );

                                    if (result is Map<String, dynamic> &&
                                        mounted) {
                                      if (result['nextAction'] == 'pause') {
                                        await _savePausedSessionFromResult(
                                            result);
                                        return;
                                      }

                                      await _updateTestResults(result);

                                      if (result['nextAction'] == 'playAgain') {
                                        final reshuffledQuestions = session
                                            .questions
                                            .map((q) => q.shuffled())
                                            .toList();
                                        await startTest(reshuffledQuestions);
                                      } else if (result['nextAction'] ==
                                          'menu') {
                                        setState(() {
                                          currentScreen = 2; // 2 = Quiz
                                        });
                                      }
                                    }
                                    // Backward compatibility with older result strings
                                    else if (result == 'playAgain' && mounted) {
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
                                        _menuPastelCream,
                                        Color.lerp(
                                          _menuPastelCream,
                                          _menuPastelLeafSoft,
                                          0.2,
                                        )!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _menuPastelGlassBorder,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _menuPastelLeaf.withValues(
                                          alpha: 0.07,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
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
                                                color: _menuPastelText,
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
                                                    color: _menuPastelTextSoft,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Icon(
                                                  Icons.access_time_rounded,
                                                  size: 14,
                                                  color: _menuPastelTextSoft,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  timeAgo,
                                                  style: GoogleFonts.outfit(
                                                    color: _menuPastelTextSoft,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: _menuPastelLeaf,
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
      case 'timedExam':
        return Icons.timer_rounded;
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
        return PnleTheme.dangerSoft;
      case 'challenge':
        return PnleTheme.warning;
      case 'timedExam':
        return PnleTheme.info;
      case 'quickPractice':
        return PnleTheme.glowB;
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

  Future<void> _updateTestResults(
    dynamic results, {
    bool showInsightsDialog = false,
  }) async {
    if (results is! Map<String, dynamic>) return;

    if (_shouldQueueMistakesFromResult(results)) {
      await _appendMistakesFromResult(results);
    }

    final resultMode = results['testMode'] as String?;
    final storedMode = resultMode ?? 'randomQuiz';
    final dynamicCorrectCount = results['correctCount'];
    final dynamicTotalCount = results['totalCount'];
    final assessmentRaw = results['assessment'];
    final sessionAssessment = assessmentRaw is Map
        ? AcetAssessment.fromJson(Map<String, dynamic>.from(assessmentRaw))
        : null;
    final insights = _sessionInsights(results);
    final elapsedSeconds = (insights['elapsedSeconds'] as num).toInt();
    final timedOutCount = insights['timedOutCount'] as int;

    if (resultMode != null &&
        {'randomQuiz', 'focusMode', 'challenge', 'timedExam'}
            .contains(resultMode) &&
        dynamicCorrectCount is Map &&
        dynamicTotalCount is Map) {
      final sessionTotal = dynamicTotalCount.values
          .whereType<num>()
          .fold<int>(0, (sum, value) => sum + value.toInt());
      final sessionCorrect = dynamicCorrectCount.values
          .whereType<num>()
          .fold<int>(0, (sum, value) => sum + value.toInt());
      final sessionPercent =
          sessionTotal > 0 ? (sessionCorrect / sessionTotal) * 100 : 0;

      setState(() {
        _dailyTaskSessionsCompleted++;
        if (resultMode == 'focusMode') {
          _dailyTaskFocusCompleted++;
        }
        if (resultMode == 'challenge') {
          _dailyTaskChallengeCompleted++;
        }
        if (resultMode == 'timedExam') {
          _dailyTaskTimedCompleted++;
        }
        _dailyTaskQuestionsAnswered += sessionTotal;
        if (sessionPercent >= 95) {
          _dailyTaskHighScoreAchieved = true;
        }
      });
      unawaited(_persistDailyTaskRewardState());
    }

    final shouldRecord = results['recordResults'];
    if (shouldRecord is bool && !shouldRecord) return;

    final correctCount = <String, int>{};
    if (dynamicCorrectCount is Map) {
      for (final entry in dynamicCorrectCount.entries) {
        if (entry.key is String && entry.value is num) {
          correctCount[entry.key as String] = (entry.value as num).toInt();
        }
      }
    }

    final totalCount = <String, int>{};
    if (dynamicTotalCount is Map) {
      for (final entry in dynamicTotalCount.entries) {
        if (entry.key is String && entry.value is num) {
          totalCount[entry.key as String] = (entry.value as num).toInt();
        }
      }
    }

    if (correctCount.isEmpty || totalCount.isEmpty) return;

    // Only the first daily-target sessions affect today's readiness bucket,
    // but all sessions must still be recorded for 10-day analytics.
    final countsTowardDailyReadiness = completedSessions < _dailySessionTarget;

    var shouldUpdateStreak = false;
    final hadChallengeUnlock = _hasUnlockedAdvancedModes;

    setState(() {
      if (countsTowardDailyReadiness) {
        // Increment completed sessions
        completedSessions++;

        // Accumulate category scores across the daily-target cap.
        correctCount.forEach((category, correct) {
          if (categoryScores.containsKey(category)) {
            final currentCorrect = categoryScores[category]!['correct'] as int;
            final maxTotal = categoryScores[category]!['total'] as int;
            final updatedCorrect = currentCorrect + correct;

            categoryScores[category]!['correct'] =
                updatedCorrect > maxTotal ? maxTotal : updatedCorrect;
          }
        });

        // Only update streak when user reaches the configured daily goal.
        if (completedSessions == _dailySessionTarget) {
          shouldUpdateStreak = true;
        }
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
      final sessionCategoryCorrect = <String, int>{
        for (final entry in correctCount.entries) entry.key: entry.value,
      };
      final sessionCategoryTotal = <String, int>{
        for (final entry in totalCount.entries) entry.key: entry.value,
      };

      _quizActivityRecords.insert(
        0,
        _QuizActivityRecord(
          date: DateTime.now(),
          mode: storedMode,
          questionCount: sessionQuestions,
          correctCount: sessionCorrect,
          scorePercent: sessionPercent,
          elapsedSeconds: elapsedSeconds,
          timedOutCount: timedOutCount,
          categoryCorrect: sessionCategoryCorrect,
          categoryTotal: sessionCategoryTotal,
          assessment: sessionAssessment,
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
      unawaited(_primeMissingCachesAsNeeded());
    }

    if (resultMode != null && resultMode.isNotEmpty) {
      unawaited(_clearPausedQuizSession(resultMode));
    } else {
      unawaited(_clearPausedQuizSession());
    }

    if (mounted && showInsightsDialog) {
      unawaited(_showReadinessFeedbackDialog(results));
    }
  }

  Future<void> _showReadinessFeedbackDialog(
      Map<String, dynamic> results) async {
    if (!mounted) return;

    final categories = _categoriesForProgramInterest();
    final readiness = _readinessLabel();
    final readinessColor = _readinessColor();
    final weakestCategory = _getWeakestCategory();
    final tipCategory =
        weakestCategory.isNotEmpty ? weakestCategory : 'English';
    final competitiveness = _estimatedCompetitivenessBand();
    final competitivenessColor = competitiveness['color'] as Color;
    final timedReadiness = _timedReadinessMetrics();
    final timedReadinessColor = timedReadiness['color'] as Color;
    final insights = _sessionInsights(results);
    final sessionAccuracy = (insights['sessionAccuracy'] as num).toDouble();
    final secondsPerQuestion =
        (insights['secondsPerQuestion'] as num).toDouble();
    final questionsPerMinute =
        (insights['questionsPerMinute'] as num).toDouble();
    final timedOutCount = insights['timedOutCount'] as int;
    final speedLabel = insights['speedLabel'] as String;
    final focusLabel = insights['focusLabel'] as String;
    final behaviorMessage = insights['behaviorMessage'] as String;
    final compact = MediaQuery.of(context).size.width <= 380;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 20,
            compact ? 16 : 18,
            compact ? 16 : 20,
            compact ? 14 : 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_menuPastelPanel, _menuPastelLeafSoft, 0.18)!,
                _menuPastelPanel,
                Color.lerp(_menuPastelPanel, _menuPastelYellow, 0.16)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _menuPastelGlassBorder, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: _menuPastelLeaf.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ACET Performance Update',
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 18 : 20,
                  ),
                ),
                SizedBox(height: compact ? 10 : 12),
                Text(
                  'Study Preference: ${programInterest.toUpperCase()} (optional)',
                  style: GoogleFonts.outfit(
                    color: _menuPastelLeaf,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 13,
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
                Container(
                  padding: EdgeInsets.all(compact ? 10 : 12),
                  decoration: BoxDecoration(
                    color: _menuPastelCream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _menuPastelGlassBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category Performance Snapshot',
                        style: GoogleFonts.outfit(
                          color: _menuPastelText,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 11 : 12,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      ...categories.map((category) {
                        final score = _categoryPercent(category);
                        final target = _targetForCategory(category);
                        final met = score >= target;
                        return Padding(
                          padding: EdgeInsets.only(bottom: compact ? 8 : 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      category,
                                      style: GoogleFonts.outfit(
                                        color: _menuPastelText,
                                        fontSize: compact ? 11 : 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${score.toStringAsFixed(0)}% / $target%',
                                    style: GoogleFonts.outfit(
                                      color: met
                                          ? _menuPastelAccentDeep
                                          : const Color(0xFFBE8E75),
                                      fontSize: compact ? 11 : 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 5 : 6),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final barWidth = constraints.maxWidth;
                                  final targetOffset =
                                      (barWidth * (target / 100)).clamp(
                                    0.0,
                                    barWidth,
                                  );
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        height: compact ? 6 : 8,
                                        decoration: BoxDecoration(
                                          color: _menuPastelLeafSoft.withValues(
                                              alpha: 0.72),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor:
                                            (score / 100).clamp(0.0, 1.0),
                                        child: Container(
                                          height: compact ? 6 : 8,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: met
                                                  ? const [
                                                      Color(0xFF7EA468),
                                                      Color(0xFFA6C0D4),
                                                    ]
                                                  : const [
                                                      Color(0xFFE1B79F),
                                                      Color(0xFFC9BADF),
                                                    ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: targetOffset - 1,
                                        top: compact ? -1 : -2,
                                        bottom: compact ? -1 : -2,
                                        child: Container(
                                          width: 2,
                                          decoration: BoxDecoration(
                                            color: _menuPastelTextSoft,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
                if (!compact)
                  ...categories.map((category) {
                    final score = _categoryPercent(category);
                    final target = _targetForCategory(category);
                    final met = score >= target;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '$category: ${score.toStringAsFixed(0)}% / $target% ${met ? 'OK' : 'LOW'}',
                        style: GoogleFonts.outfit(
                          color: met
                              ? _menuPastelAccentDeep
                              : const Color(0xFFBE8E75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                if (!compact) const SizedBox(height: 10),
                Text(
                  readiness.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: readinessColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _readinessPrimaryFeedback(),
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Smart Feedback',
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _smartFeedbackSummary(),
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: timedReadinessColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: timedReadinessColor.withValues(alpha: 0.48),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.timer_rounded,
                            color: timedReadinessColor,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              timedReadiness['label'] as String,
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            timedReadiness['hasData'] as bool
                                ? '${(timedReadiness['score'] as double).toStringAsFixed(1)}%'
                                : 'Pending',
                            style: GoogleFonts.outfit(
                              color: _menuPastelText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        timedReadiness['summary'] as String,
                        style: GoogleFonts.outfit(
                          color: _menuPastelTextSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: competitivenessColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: competitivenessColor.withValues(alpha: 0.48),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.query_stats_rounded,
                        color: competitivenessColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${competitiveness['label']} • ${competitiveness['tier']}',
                          style: GoogleFonts.outfit(
                            color: _menuPastelText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Session Intelligence',
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Speed: $speedLabel (${secondsPerQuestion.toStringAsFixed(1)}s/question, ${questionsPerMinute.toStringAsFixed(2)} q/min)\nAccuracy: ${sessionAccuracy.toStringAsFixed(1)}%\nFocus: $focusLabel ($timedOutCount timeouts)',
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  behaviorMessage,
                  style: GoogleFonts.outfit(
                    color: PnleTheme.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _microTipForCategory(tipCategory),
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF7293AE),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'These readiness bands are in-app ACET estimates based on your recent accuracy, speed, and efficiency. They are not official admission cutoffs.',
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: compact ? 12 : 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _menuPastelLeaf,
                      foregroundColor: _menuPastelCream,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _remainingSessionsTodayText() {
    if (_isLoadingDailyFreeTests) {
      return 'Retrieving sessions...';
    }
    return '$remainingFreeTests ${remainingFreeTests == 1 ? 'session' : 'sessions'} left today';
  }

  Future<void> _showMoreSessionsDialog() async {
    Timer? dialogTicker;
    var isDialogRefreshing = false;

    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<bool> ensureOnlineForDialogAction(String actionName) async {
              if (_isOnline) return true;
              await showDialog<void>(
                context: context,
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
                    'Please reconnect to the internet to $actionName.',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'OK',
                        style: GoogleFonts.outfit(color: PnleTheme.accent),
                      ),
                    ),
                  ],
                ),
              );
              return false;
            }

            Future<void> refreshDialog({bool forcePersist = false}) async {
              if (isDialogRefreshing) return;
              isDialogRefreshing = true;
              try {
                await _processExtraSessionAdRefill(forcePersist: forcePersist);
                if (context.mounted) {
                  setDialogState(() {});
                }
              } finally {
                isDialogRefreshing = false;
              }
            }

            dialogTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (!context.mounted) {
                dialogTicker?.cancel();
                dialogTicker = null;
                return;
              }
              unawaited(refreshDialog());
            });

            final rewardsLoading =
                _isLoadingDailyTaskRewards || _isLoadingDailyFreeTests;
            final canWatchAd =
                !rewardsLoading && _isOnline && _extraSessionAdChances > 0;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _menuPastelPanel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _menuPastelGlassBorder, width: 1.3),
                ),
                child: SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.82,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Get More Sessions TODAY',
                                  style: GoogleFonts.outfit(
                                    color: _menuPastelText,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Daily tasks reset every day.',
                                  style: GoogleFonts.outfit(
                                    color: _menuPastelTextSoft,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _sessionTaskTile(
                                  icon: Icons.play_circle_fill_rounded,
                                  title: 'Watch ads for +1 session',
                                  subtitle:
                                      'Chances: $_extraSessionAdChances/$_maxExtraSessionAdChances • Next refill: ${_extraSessionCountdownText()}',
                                  actionLabel: 'Watch',
                                  enabled: canWatchAd,
                                  onAction: () async {
                                    if (!await ensureOnlineForDialogAction(
                                      'watch an ad for a bonus session',
                                    )) {
                                      return;
                                    }
                                    await _watchRewardedAdForExtraQuiz();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.local_fire_department_rounded,
                                  title:
                                      'Complete $_dailySessionTarget sessions today',
                                  subtitle:
                                      '$completedSessions/$_dailySessionTarget completed',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : completedSessions < _dailySessionTarget
                                          ? 'Locked'
                                          : _canClaimStreakRewardToday
                                              ? 'Claim'
                                              : 'Claimed',
                                  enabled: !rewardsLoading &&
                                      _canClaimStreakRewardToday,
                                  claimed: !rewardsLoading &&
                                      completedSessions >=
                                          _dailySessionTarget &&
                                      !_canClaimStreakRewardToday &&
                                      _lastStreakRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimFourSessionTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.military_tech_rounded,
                                  title: 'Complete 8 sessions today',
                                  subtitle:
                                      '$_dailyTaskSessionsCompleted/8 completed',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : _canClaimEightSessionRewardToday
                                          ? 'Claim'
                                          : (_lastEightSessionRewardClaimDate ==
                                                  _getTodayDateString()
                                              ? 'Claimed'
                                              : 'Locked'),
                                  enabled: !rewardsLoading &&
                                      _canClaimEightSessionRewardToday,
                                  claimed: !rewardsLoading &&
                                      !_canClaimEightSessionRewardToday &&
                                      _lastEightSessionRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimEightSessionTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.gps_fixed_rounded,
                                  title: 'Finish 1 Focus Mode session',
                                  subtitle:
                                      '$_dailyTaskFocusCompleted/1 completed',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : _canClaimFocusRewardToday
                                          ? 'Claim'
                                          : (_lastFocusRewardClaimDate ==
                                                  _getTodayDateString()
                                              ? 'Claimed'
                                              : 'Locked'),
                                  enabled: !rewardsLoading &&
                                      _canClaimFocusRewardToday,
                                  claimed: !rewardsLoading &&
                                      !_canClaimFocusRewardToday &&
                                      _lastFocusRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimFocusTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.emoji_events_rounded,
                                  title: 'Finish 1 Challenge Mode session',
                                  subtitle:
                                      '$_dailyTaskChallengeCompleted/1 completed',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : _canClaimChallengeRewardToday
                                          ? 'Claim'
                                          : (_lastChallengeRewardClaimDate ==
                                                  _getTodayDateString()
                                              ? 'Claimed'
                                              : 'Locked'),
                                  enabled: !rewardsLoading &&
                                      _canClaimChallengeRewardToday,
                                  claimed: !rewardsLoading &&
                                      !_canClaimChallengeRewardToday &&
                                      _lastChallengeRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimChallengeTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.timer_rounded,
                                  title: 'Finish 1 Timed Exam session',
                                  subtitle:
                                      '$_dailyTaskTimedCompleted/1 completed',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : _canClaimTimedExamRewardToday
                                          ? 'Claim'
                                          : (_lastTimedExamRewardClaimDate ==
                                                  _getTodayDateString()
                                              ? 'Claimed'
                                              : 'Locked'),
                                  enabled: !rewardsLoading &&
                                      _canClaimTimedExamRewardToday,
                                  claimed: !rewardsLoading &&
                                      !_canClaimTimedExamRewardToday &&
                                      _lastTimedExamRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimTimedExamTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.format_list_numbered_rounded,
                                  title: 'Answer 30 questions today',
                                  subtitle:
                                      '$_dailyTaskQuestionsAnswered/30 answered',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : _canClaimThirtyAnswersRewardToday
                                          ? 'Claim'
                                          : (_lastThirtyAnswersRewardClaimDate ==
                                                  _getTodayDateString()
                                              ? 'Claimed'
                                              : 'Locked'),
                                  enabled: !rewardsLoading &&
                                      _canClaimThirtyAnswersRewardToday,
                                  claimed: !rewardsLoading &&
                                      !_canClaimThirtyAnswersRewardToday &&
                                      _lastThirtyAnswersRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimThirtyAnswersTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sessionTaskTile(
                                  icon: Icons.verified_rounded,
                                  title:
                                      'Score 95%+ in Random/Focus/Challenge/Timed',
                                  subtitle: _dailyTaskHighScoreAchieved
                                      ? 'Qualified today'
                                      : 'Need 95% or higher',
                                  actionLabel: rewardsLoading
                                      ? '...'
                                      : _canClaimHighScoreRewardToday
                                          ? 'Claim'
                                          : (_lastHighScoreRewardClaimDate ==
                                                  _getTodayDateString()
                                              ? 'Claimed'
                                              : 'Locked'),
                                  enabled: !rewardsLoading &&
                                      _canClaimHighScoreRewardToday,
                                  claimed: !rewardsLoading &&
                                      !_canClaimHighScoreRewardToday &&
                                      _lastHighScoreRewardClaimDate ==
                                          _getTodayDateString(),
                                  onAction: () async {
                                    await _claimHighScoreTaskReward();
                                    await refreshDialog(forcePersist: true);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Close',
                              style: GoogleFonts.outfit(
                                color: _menuPastelTextSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      dialogTicker?.cancel();
    }
  }

  Widget _sessionTaskTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required bool enabled,
    bool claimed = false,
    required Future<void> Function() onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _menuPastelCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _menuPastelGlassBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: _menuPastelLeaf, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          claimed
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _menuPastelLeafSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _menuPastelAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: _menuPastelLeaf,
                    size: 20,
                  ),
                )
              : ElevatedButton(
                  onPressed: enabled ? () => onAction() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        enabled ? _menuPastelLeafSoft : _menuPastelPanel,
                    foregroundColor:
                        enabled ? _menuPastelText : _menuPastelTextSoft,
                    disabledBackgroundColor: _menuPastelPanel,
                    disabledForegroundColor: _menuPastelTextSoft,
                    side: BorderSide(
                      color: enabled
                          ? _menuPastelAccent.withValues(alpha: 0.35)
                          : _menuPastelGlassBorder,
                    ),
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
    );
  }

  // =========================
  // UI
  // =========================
  static const Color _menuPastelMint = Color(0xFFD7EACB);
  static const Color _menuPastelCream = Color(0xFFFCF6EB);
  static const Color _menuPastelYellow = Color(0xFFF1E6A7);
  static const Color _menuPastelSeafoam = Color(0xFFC9E1BD);
  static const Color _menuPastelAccent = Color(0xFF95B97F);
  static const Color _menuPastelAccentDeep = Color(0xFF6F8F60);
  static const Color _menuPastelText = Color(0xFF5A7652);
  static const Color _menuPastelTextSoft = Color(0xFF8AA081);
  static const Color _menuPastelGlassFill = Color(0xEAFBF7EE);
  static const Color _menuPastelGlassBorder = Color(0xA4C5D6AE);
  static const Color _menuPastelPanel = Color(0xFFF9F3E7);
  static const Color _menuPastelLeaf = Color(0xFF7EA468);
  static const Color _menuPastelLeafSoft = Color(0xFFDDEBCE);

  Widget _buildPastelMenuBackdrop() {
    return Container(color: _menuPastelCream);
  }

  @override
  Widget build(BuildContext context) {
    // Set status bar to be transparent with dark icons for the pastel surface
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: _menuPastelCream,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildPastelMenuBackdrop(),
                _buildScreen(),
              ],
            ),
          ),
          // Banner Ad (only for free users) - positioned at bottom above nav bar
          if (!hasUnlimitedAccess &&
              !hasGraceAccess &&
              _isBannerAdLoaded &&
              _bannerAd != null)
            Container(
              color: _menuPastelCream,
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: SizedBox(
                height: 50,
                child: Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
              ),
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
      strictTimingEnabled: _strictTimingEnabled,
      onNicknameChanged: (nickname) async {
        await _saveNickname(nickname);
      },
      onMuteAllSoundsChanged: (muted) async {
        await _setMuteAllSounds(muted);
      },
      onNotificationsChanged: (enabled) async {
        return _setNotificationsEnabled(enabled);
      },
      onStrictTimingChanged: (enabled) async {
        await _setStrictTimingEnabled(enabled);
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _menuPastelPanel,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: _menuPastelGlassBorder,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x16809D6A),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _buildNormalHomeFlow(),
      ),
    );
  }

  // ignore: unused_element
  void _showSpecializationSelectionDialog() {
    final specializations = List<String>.from(_acetStudyPreferences);

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
                Color.lerp(_menuPastelPanel, _menuPastelLeafSoft, 0.2)!,
                _menuPastelPanel,
                Color.lerp(_menuPastelPanel, _menuPastelYellow, 0.18)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _menuPastelGlassBorder,
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: _menuPastelLeaf.withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
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
                        'Optional: choose a study preference',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: _menuPastelText,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: 0.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This only adjusts emphasis and coaching. It does not lock your quiz coverage.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: _menuPastelTextSoft,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          decoration: TextDecoration.none,
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

                      // Optional study-interest clusters. They guide messaging only.
                      switch (spec) {
                        case 'General ACET':
                          description =
                              'Balanced practice across all four ACET categories';
                          icon = Icons.school_rounded;
                          break;
                        case 'English Priority':
                          description =
                              'Use this if you want extra emphasis on grammar, vocabulary, and reading accuracy';
                          icon = Icons.spellcheck_rounded;
                          break;
                        case 'Mathematics Priority':
                          description =
                              'Use this if you want extra emphasis on quantitative speed and accuracy';
                          icon = Icons.calculate_rounded;
                          break;
                        case 'Logical Reasoning Priority':
                          description =
                              'Use this if you want more argument analysis, deduction, and inference practice';
                          icon = Icons.account_tree_rounded;
                          break;
                        case 'Mental Ability Priority':
                          description =
                              'Use this if you want more pattern, matrix, and abstract-rule practice';
                          icon = Icons.psychology_alt_rounded;
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
                                    _menuPastelCream,
                                    Color.lerp(
                                      _menuPastelCream,
                                      _menuPastelYellow,
                                      0.18,
                                    )!,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _menuPastelGlassBorder,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _menuPastelLeafSoft,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: _menuPastelLeaf,
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
                                            color: _menuPastelText,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          description,
                                          style: GoogleFonts.outfit(
                                            color: _menuPastelTextSoft,
                                            fontWeight: FontWeight.w400,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: _menuPastelTextSoft,
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
    );
  }

  Widget _startQuizScreen() {
    final totalAvg = _calculateTotalAverage();
    final categories = _categoriesForProgramInterest();
    final totalWarmupBuckets = categories.length * 4;
    final effectiveFocusCategory = _recommendedFocusCategory();
    // Use accumulated stats that persist across sessions
    final totalQuizzesTaken = accumulatedQuizzesCompleted;
    final totalQuestionsAnswered = accumulatedQuestionsAnswered;
    final bestScore = totalAvg;
    final isLoadingSessionAccess = _isLoadingDailyFreeTests;
    final canTakeQuiz = !isLoadingSessionAccess && remainingFreeTests > 0;
    final isFocusModeLocked =
        !_hasUnlockedAdvancedModes || effectiveFocusCategory.isEmpty;
    final isChallengeModeLocked = !_hasUnlockedAdvancedModes;

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
                  color: _menuPastelCream,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _menuPastelGlassBorder),
                ),
                child: Column(
                  children: [
                    Text(
                      'YOUR STATS',
                      style: GoogleFonts.outfit(
                        color: _menuPastelText,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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
                          color: _menuPastelGlassBorder,
                        ),
                        _quickStat(
                          icon: Icons.question_answer_rounded,
                          value: '$totalQuestionsAnswered',
                          label: 'Questions',
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: _menuPastelGlassBorder,
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
                    color: const Color(0xFFF8E8E3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: PnleTheme.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: PnleTheme.dangerSoft, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline: locally seeded quiz sessions still work. Rewards, syncing, and online explanations resume after reconnecting.',
                          style: GoogleFonts.outfit(
                            color: _menuPastelText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_showPoolWarmupIndicator)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _poolWarmupComplete
                        ? const Color(0xFFEAF5E1)
                        : const Color(0xFFF8F0D8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _poolWarmupComplete
                          ? PnleTheme.success.withValues(alpha: 0.35)
                          : PnleTheme.warning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _poolWarmupComplete
                            ? Icons.verified_rounded
                            : Icons.hourglass_bottom_rounded,
                        color: _poolWarmupComplete
                            ? PnleTheme.success
                            : PnleTheme.warning,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          !_poolWarmupChecked
                              ? 'Checking offline question pool status...'
                              : (_poolWarmupComplete
                                  ? (_isOnline
                                      ? 'Offline pool warmed up: local question sets are ready for Random Quiz, Focus Mode, and Timed Exam. Challenge Mode may still use online generation.'
                                      : 'Offline pool warmed up. Random Quiz, Focus Mode, and Timed Exam can start from local question sets while syncing waits for internet.')
                                  : 'Offline pool warm-up in progress: $_poolWarmupReadyBuckets/$totalWarmupBuckets buckets ready.'),
                          style: GoogleFonts.outfit(
                            color: _menuPastelText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _dismissPoolWarmupIndicator,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            color: _menuPastelTextSoft,
                            size: 16,
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
                  color: const Color(0xFFF5EFDE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _menuPastelAccent.withValues(alpha: 0.42),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: PnleTheme.warning, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Today\'s Progress',
                          style: GoogleFonts.outfit(
                            color: _menuPastelText,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _menuPastelCream,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _menuPastelGlassBorder,
                        ),
                      ),
                      child: Text(
                        'Study Preference: ${programInterest.toUpperCase()}',
                        style: GoogleFonts.outfit(
                          color: _menuPastelText,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sessions: $completedSessions/$_dailySessionTarget',
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Streak: $currentStreak ${currentStreak == 1 ? 'day' : 'days'}',
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _menuPastelLeafSoft,
                            border: Border.all(
                              color: _menuPastelAccent.withValues(alpha: 0.35),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _remainingSessionsTodayText(),
                            style: GoogleFonts.outfit(
                              color: _menuPastelText,
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

              Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5E8C8),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: const Color(0xFFD9C59C), width: 1.2),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isLoadingDailyTaskRewards ||
                                _isLoadingDailyFreeTests
                            ? null
                            : _showMoreSessionsDialog,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.flag_rounded,
                                color: Color(0xFF533700),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Get More Sessions TODAY',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF533700),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      _isLoadingDailyTaskRewards ||
                                              _isLoadingDailyFreeTests
                                          ? 'Retrieving today\'s rewards...'
                                          : 'Daily tasks and claimable rewards',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF6D4B11),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_claimableSessionsCountNow > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _menuPastelLeafSoft,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _menuPastelAccent.withValues(
                                          alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    '+$_claimableSessionsCountNow',
                                    style: GoogleFonts.outfit(
                                      color: _menuPastelText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 9,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF6D4B11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Quiz Mode Selection Header (moved up to avoid scrolling)
              Text(
                'SELECT QUIZ MODE',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
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
                    ? _modeFadeGradientWithColors(
                        const Color(0xFFDCEBCF),
                        const Color(0xFFC9DDB6),
                      )
                    : _modeFadeGradientWithColors(
                        const Color(0xFFF3E6DA),
                        const Color(0xFFE8D6C9),
                        strength: 0.72,
                      ),
                accentColor: const Color(0xFF7CA66C),
                iconBackgroundColor: const Color(0xFF9FC88A),
                onTap: canTakeQuiz
                    ? () async {
                        await _startOrResumeMode(
                          mode: 'randomQuiz',
                          onStartNew: () async {
                            try {
                              if (!mounted) return;
                              final hasPregeneratedRandom =
                                  (_cachedRandomQuizQuestions?.length ?? 0) >=
                                          15 &&
                                      _cachedRandomQuizCoverage != null;
                              final coverage = hasPregeneratedRandom
                                  ? Map<String, String>.from(
                                      _cachedRandomQuizCoverage!)
                                  : _generateTestCoverage();
                              FocusScope.of(context).unfocus();
                              _showTestCoverageDialog(coverage);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error: ${e.toString()}')),
                              );
                            }
                          },
                        );
                      }
                    : () => _showMoreSessionsDialog(),
                isPrimary: true,
                badge: isLoadingSessionAccess
                    ? '...'
                    : (canTakeQuiz ? null : 'NO CREDITS'),
                isLocked: false,
              ),
              const SizedBox(height: 12),

              // 2. Focus Mode
              _quizModeCard(
                icon: Icons.center_focus_strong_rounded,
                title: 'Focus Mode',
                description: effectiveFocusCategory.isNotEmpty
                    ? 'Target: $effectiveFocusCategory'
                    : 'Adaptive focus practice',
                gradient: _modeFadeGradientWithColors(
                  const Color(0xFFE8DDF1),
                  const Color(0xFFD8CAE6),
                  strength: 0.9,
                ),
                accentColor: const Color(0xFF8C79A8),
                iconBackgroundColor: const Color(0xFFB6A4CE),
                onTap: (canTakeQuiz &&
                        _hasUnlockedAdvancedModes &&
                        effectiveFocusCategory.isNotEmpty)
                    ? () async {
                        await _startOrResumeMode(
                          mode: 'focusMode',
                          onStartNew: () async {
                            try {
                              final coverage = _generateFocusModeCoverage(
                                  effectiveFocusCategory);
                              _showTestCoverageDialog(
                                coverage,
                                isFocusMode: true,
                                focusCategory: effectiveFocusCategory,
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error: ${e.toString()}')),
                              );
                            }
                          },
                        );
                      }
                    : (!_hasUnlockedAdvancedModes ||
                            effectiveFocusCategory.isEmpty)
                        ? null
                        : () => _showMoreSessionsDialog(),
                badge: !canTakeQuiz
                    ? (isLoadingSessionAccess ? '...' : 'NO CREDITS')
                    : (_hasUnlockedAdvancedModes
                        ? null
                        : '$_lifetimeRandomQuizzesCompleted/$_advancedModeUnlockRequirement'),
                isLocked: isFocusModeLocked,
              ),
              const SizedBox(height: 12),

              // 3. Quick Practice
              _quizModeCard(
                icon: Icons.flash_on_rounded,
                title: 'Quick Practice',
                description: _isLoadingSavedSessions
                    ? 'Retrieving saved tests...'
                    : '5 questions • Perfect for breaks',
                gradient: _modeFadeGradientWithColors(
                  const Color(0xFFF6E2D7),
                  const Color(0xFFEFCFC0),
                  strength: 0.8,
                ),
                accentColor: const Color(0xFFBE8E75),
                iconBackgroundColor: const Color(0xFFE1B79F),
                onTap: _isLoadingSavedSessions
                    ? null
                    : (_hasSavedTestsData ? () => _startQuickPractice() : null),
                badge: _isLoadingSavedSessions
                    ? '...'
                    : (_hasSavedTestsData ? null : 'LOCKED'),
                isLocked: !_isLoadingSavedSessions && !_hasSavedTestsData,
              ),
              const SizedBox(height: 12),

              // 4. Challenge Mode
              _quizModeCard(
                icon: Icons.emoji_events_rounded,
                title: 'Challenge Mode',
                description:
                    'Advanced mixed-difficulty simulation • Does not count toward daily session objective',
                gradient: _modeFadeGradientWithColors(
                  const Color(0xFFF4E2BA),
                  const Color(0xFFE7CF9B),
                  strength: 0.86,
                ),
                accentColor: const Color(0xFFB28D4B),
                iconBackgroundColor: const Color(0xFFD8BD79),
                onTap: (canTakeQuiz && _hasUnlockedAdvancedModes)
                    ? () => _startOrResumeMode(
                          mode: 'challenge',
                          onStartNew: _startChallengeMode,
                        )
                    : (_hasUnlockedAdvancedModes
                        ? () => _showMoreSessionsDialog()
                        : null),
                badge: !canTakeQuiz
                    ? (isLoadingSessionAccess ? '...' : 'NO CREDITS')
                    : (_hasUnlockedAdvancedModes
                        ? null
                        : '$_lifetimeRandomQuizzesCompleted/$_advancedModeUnlockRequirement'),
                isLocked: isChallengeModeLocked,
              ),
              const SizedBox(height: 12),

              // 5. Timed Exam
              _quizModeCard(
                icon: Icons.timer_rounded,
                title: 'Timed Exam',
                description:
                    'Exam pressure mode • strict timer with auto-next on timeout',
                gradient: _modeFadeGradientWithColors(
                  const Color(0xFFDDEAF2),
                  const Color(0xFFCBDBE8),
                  strength: 0.86,
                ),
                accentColor: const Color(0xFF7293AE),
                iconBackgroundColor: const Color(0xFFA6C0D4),
                onTap: canTakeQuiz
                    ? () async {
                        await _startOrResumeMode(
                          mode: 'timedExam',
                          onStartNew: _startTimedExamMode,
                        );
                      }
                    : () => _showMoreSessionsDialog(),
                badge: isLoadingSessionAccess
                    ? '...'
                    : (canTakeQuiz ? null : 'NO CREDITS'),
                isLocked: false,
              ),
              const SizedBox(height: 12),

              // 5. Load Saved Test
              if (_isLoadingSavedSessions || _savedSessions.isNotEmpty)
                _quizModeCard(
                  icon: Icons.history_rounded,
                  title: 'Load Saved Test',
                  description: _isLoadingSavedSessions
                      ? 'Retrieving saved tests...'
                      : '${_savedSessions.length} saved ${_savedSessions.length == 1 ? 'test' : 'tests'} available',
                  gradient: _modeFadeGradientWithColors(
                    const Color(0xFFEEDFE4),
                    const Color(0xFFE0CFD6),
                    strength: 0.74,
                  ),
                  accentColor: const Color(0xFFAA7E8F),
                  iconBackgroundColor: const Color(0xFFD7B2BF),
                  onTap: _isLoadingSavedSessions ? null : _showSavedTestsDialog,
                  badge: _isLoadingSavedSessions
                      ? '...'
                      : '${_savedSessions.length}',
                  isLocked: false,
                ),

              if (_isLoadingSavedSessions || _savedSessions.isNotEmpty)
                const SizedBox(height: 24),
              const SizedBox(height: 24),
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
        Icon(icon, color: _menuPastelLeaf, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: _menuPastelText,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: _menuPastelTextSoft,
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
    Color accentColor = _menuPastelAccent,
    Color iconBackgroundColor = _menuPastelLeaf,
    VoidCallback? onTap,
    bool isPrimary = false,
    String? badge,
    bool isLocked = false,
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
                        const Color(0xFFF0ECE3),
                        const Color(0xFFE8E3D8),
                      ],
                    )
                  : gradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLocked
                    ? _menuPastelAccent.withValues(alpha: 0.18)
                    : accentColor.withValues(alpha: 0.34),
                width: isPrimary ? 2 : 1,
              ),
              boxShadow: isPrimary && !isLocked
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.16),
                        blurRadius: 10,
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
                        ? _menuPastelLeafSoft.withValues(alpha: 0.65)
                        : iconBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_rounded : icon,
                    color: isLocked ? _menuPastelTextSoft : Colors.white,
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
                                color: _menuPastelText,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (badge != null)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _menuPastelPanel,
                                    border: Border.all(
                                      color: accentColor.withValues(alpha: 0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    badge,
                                    style: GoogleFonts.outfit(
                                      color: _menuPastelText,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
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
                          color: _menuPastelTextSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLocked)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: accentColor,
                    size: 18,
                  ),
              ],
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
    final start = Color.lerp(_menuPastelCream, from, 0.14) ?? _menuPastelCream;
    final mid = Color.lerp(_menuPastelPanel, to, 0.16) ?? _menuPastelPanel;
    final end =
        Color.lerp(_menuPastelLeafSoft, to, 0.08) ?? _menuPastelLeafSoft;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        start.withValues(alpha: 0.98),
        mid.withValues(alpha: 0.98),
        end.withValues(alpha: 0.98 - (0.04 * (1 - s))),
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
        color: _menuPastelCream,
        border: Border(
          top: BorderSide(
            color: _menuPastelAccent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1488A36F),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: _menuPastelText,
        unselectedItemColor: _menuPastelTextSoft,
        selectedLabelStyle: GoogleFonts.outfit(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: GoogleFonts.outfit(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.15,
        ),
        currentIndex: currentScreen,
        type: BottomNavigationBarType.fixed,
        items: List.generate(
          navItems.length,
          (index) {
            final isSelected = currentScreen == index;
            return BottomNavigationBarItem(
              icon: isSelected
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EFD9),
                        border: Border.all(
                          color: _menuPastelAccent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x1290AB79),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        navItems[index]['icon'] as IconData,
                        size: 24,
                        color: _menuPastelText,
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        navItems[index]['icon'] as IconData,
                        size: 24,
                        color: _menuPastelTextSoft,
                      ),
                    ),
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
      unawaited(_refreshPoolWarmupStatus());
    }
  }

  Widget _dailyPerformanceScreen() {
    final hasData =
        categoryScores.values.any((data) => (data['total'] as int) > 0);

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _menuPastelPanel,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: _menuPastelGlassBorder,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x16809D6A),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ListView(
            key: const PageStorageKey('daily_performance_screen'),
            controller: _dailyScrollController,
            children: [
              const SizedBox(height: 8),
              Text(
                'Daily Progress',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
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
                  color: _menuPastelTextSoft,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              _objectiveCard(
                text:
                    'Complete $_dailySessionTarget new sessions today to finish your daily assessment.',
                progress:
                    (completedSessions / _dailySessionTarget).clamp(0.0, 1.0),
                trailing: '$completedSessions/$_dailySessionTarget',
              ),
              const SizedBox(height: 24),
              _buildCourseReadinessCard(),
              const SizedBox(height: 16),
              if (!hasData) ...[
                const SizedBox(height: 40),
                Icon(
                  Icons.insert_chart_outlined_rounded,
                  size: 80,
                  color: _menuPastelTextSoft.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 16),
                Text(
                  'No data yet',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: _menuPastelText,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start your first quiz today to\ntrack your progress!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: _menuPastelTextSoft,
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
              const SizedBox(height: 16),
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

  String _formatShortMonthDay(DateTime date) {
    const months = [
      'Jan.',
      'Feb.',
      'Mar.',
      'Apr.',
      'May.',
      'Jun.',
      'Jul.',
      'Aug.',
      'Sep.',
      'Oct.',
      'Nov.',
      'Dec.'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Widget _historyScreen() {
    return _historyInsightsScreen();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<Map<String, dynamic>> _buildTenDayActivity() {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final activity = <DateTime, Map<String, dynamic>>{};

    for (int i = 9; i >= 0; i--) {
      final day = _dateOnly(now.subtract(Duration(days: i)));
      activity[day] = {
        'quizzes': 0,
        'questions': 0,
        'correct': 0,
        'percentSum': 0,
        'categoryCorrect': <String, int>{},
        'categoryTotal': <String, int>{},
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

      final dayCategoryCorrect =
          activity[day]!['categoryCorrect'] as Map<String, int>;
      final dayCategoryTotal =
          activity[day]!['categoryTotal'] as Map<String, int>;
      for (final category in record.categoryTotal.keys) {
        dayCategoryCorrect[category] = (dayCategoryCorrect[category] ?? 0) +
            (record.categoryCorrect[category] ?? 0);
        dayCategoryTotal[category] =
            (dayCategoryTotal[category] ?? 0) + record.categoryTotal[category]!;
      }
    }

    final todayData = activity[today];
    final fallbackSessions =
        max(completedSessions, _dailyTaskSessionsCompleted);
    if (todayData != null &&
        ((todayData['quizzes'] ?? 0) == 0 ||
            (todayData['quizzes'] as int? ?? 0) < fallbackSessions) &&
        fallbackSessions > 0) {
      final fallbackQuestions = fallbackSessions * 15;
      final fallbackCorrect = categoryScores.values.fold<int>(
        0,
        (sum, value) => sum + ((value['correct'] as int?) ?? 0),
      );
      final fallbackPercent = fallbackQuestions > 0
          ? (fallbackCorrect / fallbackQuestions) * 100
          : 0.0;

      todayData['quizzes'] = fallbackSessions;
      todayData['questions'] = fallbackQuestions;
      todayData['correct'] = fallbackCorrect;
      todayData['percentSum'] = fallbackPercent * fallbackSessions;
      todayData['categoryCorrect'] = <String, int>{
        for (final entry in categoryScores.entries)
          entry.key: (entry.value['correct'] as int?) ?? 0,
      };
      todayData['categoryTotal'] = <String, int>{
        for (final entry in categoryScores.entries)
          entry.key: (entry.value['total'] as int?) ?? 0,
      };
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
            'categoryCorrect':
                entry.value['categoryCorrect'] ?? <String, int>{},
            'categoryTotal': entry.value['categoryTotal'] ?? <String, int>{},
          },
        )
        .toList();
  }

  Widget _buildStudyHubAction({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: enabled ? _menuPastelCream : const Color(0xFFF9F5EC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? _menuPastelAccent.withValues(alpha: 0.54)
                  : _menuPastelTextSoft.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x1288A672),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: enabled ? _menuPastelLeaf : _menuPastelLeafSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: enabled
                      ? Colors.white
                      : _menuPastelTextSoft.withValues(alpha: 0.7),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: enabled
                            ? _menuPastelText
                            : _menuPastelTextSoft.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: enabled
                            ? _menuPastelTextSoft
                            : _menuPastelTextSoft.withValues(alpha: 0.65),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudyHubMetric({
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _menuPastelLeafSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _menuPastelAccent.withValues(alpha: 0.36)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.outfit(
                color: _menuPastelText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: _menuPastelTextSoft,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudyHubCard() {
    final hasPaused = _pausedQuizSessions.isNotEmpty;
    String pausedProgress = 'No paused session';
    if (_isLoadingPausedQuizSessions) {
      pausedProgress = 'Retrieving unfinished sessions...';
    } else if (hasPaused && _pausedQuizSessions.length == 1) {
      final single = _pausedQuizSessions.values.first;
      pausedProgress =
          '${_modeLabel(single.testMode)} • ${single.currentIndex + 1}/${single.questions.length}';
    } else if (hasPaused) {
      final count = _pausedQuizSessions.length;
      pausedProgress = '$count unfinished modes available';
    }

    final mistakeCount = _mistakeQueue.length;
    final mistakesSubtitle = _isLoadingMistakeQueue
        ? 'Retrieving saved mistakes...'
        : '$mistakeCount saved for review';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFF7F1E3),
        border: Border.all(color: _menuPastelGlassBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0x128DA774),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.hub_rounded,
                color: _menuPastelLeaf,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Study Hub',
                style: GoogleFonts.outfit(
                  color: _menuPastelText,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Jump right back into active study tasks.',
            style: GoogleFonts.outfit(
              color: _menuPastelTextSoft,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStudyHubMetric(
                value: '$completedSessions/$_dailySessionTarget',
                label: 'Today',
              ),
              const SizedBox(width: 8),
              _buildStudyHubMetric(
                value: '$currentStreak',
                label: 'Streak',
              ),
              const SizedBox(width: 8),
              _buildStudyHubMetric(
                value: '$accumulatedQuizzesCompleted',
                label: 'Total Quizzes',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStudyHubAction(
            icon: Icons.play_circle_fill_rounded,
            label: 'Continue Session',
            subtitle: pausedProgress,
            onTap: !_isLoadingPausedQuizSessions && hasPaused
                ? _showContinueSessionsDialog
                : null,
          ),
          const SizedBox(height: 10),
          _buildStudyHubAction(
            icon: Icons.fact_check_rounded,
            label: 'Review Mistakes',
            subtitle: mistakesSubtitle,
            onTap: !_isLoadingMistakeQueue && mistakeCount > 0
                ? _showReviewMistakesDialog
                : null,
          ),
          const SizedBox(height: 10),
          _buildStudyHubAction(
            icon: Icons.bolt_rounded,
            label: 'Start Quiz',
            subtitle: _remainingSessionsTodayText(),
            onTap: () {
              setState(() {
                currentScreen = 2;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNormalHomeFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          _getGreetingWithName(),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _menuPastelText,
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: 1.1,
            shadows: [
              Shadow(
                color: Colors.white.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _getDailyMotivationalQuote(),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _menuPastelTextSoft,
            fontWeight: FontWeight.w500,
            fontSize: 14,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2EAB9),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: _menuPastelAccent.withValues(alpha: 0.56)),
            boxShadow: [
              BoxShadow(
                color: const Color(0x1290AB79),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_fire_department_rounded,
                      color: Color(0xFFBEA94F), size: 24),
                  const SizedBox(width: 12),
                  Text(
                    '$currentStreak day streak!',
                    style: GoogleFonts.outfit(
                      color: _menuPastelText,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 24),
        _buildStudyHubCard(),
        const SizedBox(height: 24),
        if (accumulatedQuizzesCompleted > 0) const SizedBox(height: 14),
      ],
    );
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

  Widget _historyInsightsScreen() {
    final tenDayActivity = _buildTenDayActivity();
    final activeDays =
        tenDayActivity.where((day) => (day['quizzes'] as int) > 0).length;
    final totalQuizzes = tenDayActivity.fold<int>(
      0,
      (sum, day) => sum + (day['quizzes'] as int),
    );
    final strongDays = tenDayActivity
        .where((day) => _calculateDayAcetPerformanceIndex(day) >= 82)
        .length;

    return Stack(
      children: [
        SingleChildScrollView(
          key: const PageStorageKey('history_screen'),
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
                        color: _menuPastelText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your real activity over the last 10 days',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: _menuPastelTextSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Analysis uses ACET area weighting, session completion, and subject coverage.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: _menuPastelText,
                        fontWeight: FontWeight.w700,
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
                    _build10DayStatItem(
                        '$strongDays', 'Strong Days', Icons.flag_rounded),
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
                          color: PnleTheme.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Progress Analysis',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _menuPastelText,
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
                          'Daily ACET Performance Index',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _menuPastelText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildReadinessLineChart(tenDayActivity),
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
                        color: _menuPastelText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This index blends weighted accuracy, completion of your daily sessions, and coverage across the four ACET areas.',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: _menuPastelTextSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...tenDayActivity.reversed.map((day) {
                      final date = day['date'] as DateTime;
                      final quizzes = day['quizzes'] as int;
                      final questions = day['questions'] as int;
                      final correct = day['correct'] as int;
                      final hasActivity = quizzes > 0;
                      final dailyTarget = _dailySessionTarget;
                      final weightedAccuracy =
                          _calculateDayWeightedAcetAccuracy(day);
                      final performanceIndex =
                          _calculateDayAcetPerformanceIndex(day);
                      final coverageCount = _countPracticedAcetAreas(day);

                      // Calculate percentage and status
                      String statusText;
                      final statusColor = _dayAcetPerformanceBandColor(day);
                      if (!hasActivity) {
                        statusText = 'No session data for this day.';
                      } else if (quizzes < dailyTarget) {
                        final missingSessions = dailyTarget - quizzes;
                        final accuracyData = questions > 0
                            ? '${correct.clamp(0, questions)}/$questions correct'
                            : '${weightedAccuracy.toStringAsFixed(0)}% weighted accuracy so far';
                        statusText =
                            'In progress: $quizzes/$dailyTarget sessions. Need $missingSessions more for a full day read. Weighted accuracy: ${weightedAccuracy.toStringAsFixed(0)}%. Subtests touched: $coverageCount/4. Detail: $accuracyData.';
                      } else {
                        final accuracyData = questions > 0
                            ? '${correct.clamp(0, questions)}/$questions correct'
                            : '${weightedAccuracy.toStringAsFixed(0)}% weighted accuracy';
                        if (performanceIndex >= 82) {
                          statusText =
                              'Strong day: $dailyTarget/$dailyTarget sessions completed. Performance index ${performanceIndex.toStringAsFixed(0)}%. Weighted accuracy ${weightedAccuracy.toStringAsFixed(0)}%. Coverage: $coverageCount/4 ACET areas. Detail: $accuracyData.';
                        } else if (performanceIndex >= 74) {
                          statusText =
                              'On-track day: $dailyTarget/$dailyTarget sessions completed. Performance index ${performanceIndex.toStringAsFixed(0)}%. Weighted accuracy ${weightedAccuracy.toStringAsFixed(0)}%. Coverage: $coverageCount/4 ACET areas. Detail: $accuracyData.';
                        } else if (performanceIndex >= 66) {
                          statusText =
                              'Developing day: sessions completed, but the performance index is ${performanceIndex.toStringAsFixed(0)}%. Weighted accuracy ${weightedAccuracy.toStringAsFixed(0)}%. Coverage: $coverageCount/4 ACET areas. Detail: $accuracyData.';
                        } else {
                          statusText =
                              'Recovery day: sessions completed, but the performance index is ${performanceIndex.toStringAsFixed(0)}%. Weighted accuracy ${weightedAccuracy.toStringAsFixed(0)}%. Coverage: $coverageCount/4 ACET areas. Detail: $accuracyData.';
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _menuPastelCream,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasActivity
                                ? statusColor.withValues(alpha: 0.45)
                                : _menuPastelGlassBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatShortMonthDay(date),
                              style: GoogleFonts.outfit(
                                color: _menuPastelText,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusText,
                              style: GoogleFonts.outfit(
                                color: statusColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
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
  Widget _buildReadinessLineChart(List<Map<String, dynamic>> tenDayActivity) {
    final points = tenDayActivity
        .map((day) => _calculateDayAcetPerformanceIndex(day).clamp(0.0, 100.0))
        .toList();

    final labels = tenDayActivity
        .map((day) => (day['date'] as DateTime).day.toString())
        .toList();

    return SizedBox(
      height: 176,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              decoration: BoxDecoration(
                color: _menuPastelCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _menuPastelGlassBorder),
              ),
              child: CustomPaint(
                painter: _ReadinessLinePainter(points),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (label) => SizedBox(
                    width: 20,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: _menuPastelTextSoft,
                      ),
                    ),
                  ),
                )
                .toList(),
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
          color: _menuPastelLeaf,
          size: 16,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _menuPastelText,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: _menuPastelTextSoft,
            fontWeight: FontWeight.w600,
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
          color: _menuPastelCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _menuPastelGlassBorder),
        ),
        child: Column(
          children: [
            Icon(
              Icons.trending_up_rounded,
              color: _menuPastelTextSoft,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'No progress data yet',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _menuPastelText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Complete your first quiz to see your progress analysis',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: _menuPastelTextSoft,
              ),
            ),
          ],
        ),
      );
    }

    // Divide into first 5 days and last 5 days
    final firstHalf = tenDayActivity.take(5).toList();
    final secondHalf = tenDayActivity.skip(5).toList();

    final firstHalfIndex = firstHalf.isEmpty
        ? 0.0
        : firstHalf
                .map(_calculateDayAcetPerformanceIndex)
                .reduce((a, b) => a + b) /
            firstHalf.length;
    final secondHalfIndex = secondHalf.isEmpty
        ? 0.0
        : secondHalf
                .map(_calculateDayAcetPerformanceIndex)
                .reduce((a, b) => a + b) /
            secondHalf.length;

    final firstHalfActiveDays =
        firstHalf.where((day) => (day['quizzes'] as int) > 0).length;
    final secondHalfActiveDays =
        secondHalf.where((day) => (day['quizzes'] as int) > 0).length;

    final indexChange = firstHalfIndex > 0
        ? ((secondHalfIndex - firstHalfIndex) / firstHalfIndex * 100)
            .toStringAsFixed(1)
        : '0.0';

    final isImproving = secondHalfIndex >= firstHalfIndex;
    final trendIcon =
        isImproving ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final trendColor = isImproving ? PnleTheme.success : PnleTheme.danger;

    return Column(
      children: [
        // First vs Second Half Comparison
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _menuPastelCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _menuPastelGlassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'First 5 Days',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: _menuPastelTextSoft,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          firstHalfIndex.toStringAsFixed(0),
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _menuPastelText,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'index',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: _menuPastelTextSoft,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$firstHalfActiveDays active days',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: _menuPastelTextSoft,
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
                          secondHalfIndex.toStringAsFixed(0),
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: trendColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'index',
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
                          ? 'ACET trend is improving'
                          : 'ACET trend slipped slightly',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: trendColor,
                      ),
                    ),
                    Text(
                      '$indexChange% change in your ACET performance index from the first to the last 5 days',
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

  double _calculateDayWeightedAcetAccuracy(Map<String, dynamic> day) {
    final categoryCorrectRaw = day['categoryCorrect'];
    final categoryTotalRaw = day['categoryTotal'];

    if (categoryCorrectRaw is! Map || categoryTotalRaw is! Map) {
      return _calculateDayOverallAverage(day).clamp(0.0, 100.0);
    }

    final categories = _categoriesForProgramInterest();
    double weightedScore = 0.0;
    double weightSum = 0.0;

    for (final category in categories) {
      final total = (categoryTotalRaw[category] as num?)?.toInt() ?? 0;
      if (total <= 0) continue;

      final correct = (categoryCorrectRaw[category] as num?)?.toInt() ?? 0;
      final weight =
          (categoryScores[category]?['weight'] as num?)?.toDouble() ??
              (1 / categories.length);
      weightedScore += ((correct / total) * 100) * weight;
      weightSum += weight;
    }

    if (weightSum <= 0) {
      return _calculateDayOverallAverage(day).clamp(0.0, 100.0);
    }

    return (weightedScore / weightSum).clamp(0.0, 100.0);
  }

  int _countPracticedAcetAreas(Map<String, dynamic> day) {
    final categoryTotalRaw = day['categoryTotal'];
    if (categoryTotalRaw is! Map) return 0;

    return _categoriesForProgramInterest().where((category) {
      return ((categoryTotalRaw[category] as num?)?.toInt() ?? 0) > 0;
    }).length;
  }

  double _calculateDayAcetPerformanceIndex(Map<String, dynamic> day) {
    final weightedAccuracy = _calculateDayWeightedAcetAccuracy(day);
    final quizzes = (day['quizzes'] as int?) ?? 0;
    final completionRatio =
        (quizzes / _dailySessionTarget).clamp(0.0, 1.0).toDouble();
    final coverageRatio = (_countPracticedAcetAreas(day) / 4).clamp(0.0, 1.0);

    return (weightedAccuracy * 0.55) +
        (completionRatio * 100 * 0.25) +
        (coverageRatio * 100 * 0.20);
  }

  Color _dayAcetPerformanceBandColor(Map<String, dynamic> day) {
    final quizzes = (day['quizzes'] as int?) ?? 0;
    if (quizzes <= 0) {
      return _menuPastelTextSoft;
    }

    if (quizzes < _dailySessionTarget) {
      return PnleTheme.warning;
    }

    final index = _calculateDayAcetPerformanceIndex(day);
    if (index >= 82) return PnleTheme.success;
    if (index >= 74) return const Color(0xFF7BC4FF);
    if (index >= 66) return PnleTheme.accent;
    return PnleTheme.danger;
  }

  Widget _objectiveCard({
    required String text,
    required double progress,
    required String trailing,
    Color? trailingColor,
  }) {
    final barColor = Color.lerp(
      PnleTheme.warning,
      PnleTheme.success,
      progress.clamp(0.0, 1.0),
    );
    final percentage = (progress * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _menuPastelCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _menuPastelGlassBorder),
      ),
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
                    color: _menuPastelText,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (barColor ?? Colors.grey).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (barColor ?? Colors.grey).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$percentage%',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: barColor ?? _menuPastelText,
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
              backgroundColor: _menuPastelLeafSoft.withValues(alpha: 0.65),
              valueColor:
                  AlwaysStoppedAnimation<Color>(barColor ?? Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              trailing,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: trailingColor ?? _menuPastelTextSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTotalAverage() {
    double totalWeightedScore = 0.0;

    for (final cat in _categoriesForProgramInterest()) {
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

  Widget _glassContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 16,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: _menuPastelPanel,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: _menuPastelGlassBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1289A36F),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  void _showTestCoverageDialog(
    Map<String, String> coverage, {
    bool isFocusMode = false,
    String? focusCategory,
  }) {
    final modeAccent =
        isFocusMode ? const Color(0xFF8C79A8) : _menuPastelAccentDeep;
    final modeAccentSoft =
        isFocusMode ? const Color(0xFFF1EAF8) : _menuPastelLeafSoft;
    final modeBorder =
        isFocusMode ? const Color(0xFFD8CAE6) : _menuPastelGlassBorder;

    // Store the test coverage for use in prompt generation
    _currentTestCoverage = coverage;

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
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(_menuPastelPanel, modeAccentSoft, 0.35)!,
                  _menuPastelPanel,
                  const Color(0xFFF0F5EC),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: modeBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: modeAccent.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -14,
                  left: -8,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          modeAccentSoft.withValues(alpha: 0.68),
                          modeAccentSoft.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 82,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0x55E6EFF7),
                          Color(0x00E6EFF7),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 28,
                  bottom: 108,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0x55F6EDC9),
                          Color(0x00F6EDC9),
                        ],
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isFocusMode ? 'FOCUS MODE' : 'RANDOM QUIZ',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: _menuPastelText,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isFocusMode ? focusCategory ?? '' : 'Test Coverage',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: modeAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      if (isFocusMode) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: modeAccentSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: modeAccent.withValues(alpha: 0.28),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: modeAccent.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.gps_fixed,
                                  color: modeAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '10 questions from $focusCategory + 5 mixed questions',
                                  style: GoogleFonts.outfit(
                                    color: _menuPastelText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ...coverage.entries.map((e) => _coverageItem(
                            e.key,
                            e.value,
                            isFocusMode: isFocusMode,
                            focusCategory: focusCategory,
                          )),
                      const SizedBox(height: 24),
                      // CREATE TEST BUTTON
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              _menuPastelAccentDeep,
                              Color.lerp(
                                _menuPastelAccentDeep,
                                const Color(0xFFAAC29A),
                                0.45,
                              )!,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: modeAccent.withValues(alpha: 0.24),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (remainingFreeTests <= 0) {
                              await showDialog<void>(
                                context: dialogContext,
                                barrierColor: Colors.black87,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: _menuPastelPanel,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: const Color(0xFFD9C59C),
                                        width: 1.4,
                                      ),
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
                                              color: Color(0xFFB28D4B),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'No Session Credits',
                                                style: GoogleFonts.outfit(
                                                  color: _menuPastelText,
                                                  fontWeight: FontWeight.bold,
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
                                            color: _menuPastelTextSoft,
                                            height: 1.4,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: ElevatedButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: modeAccentSoft,
                                              foregroundColor: _menuPastelText,
                                              side: BorderSide(
                                                color: modeAccent.withValues(
                                                    alpha: 0.28),
                                              ),
                                              elevation: 0,
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
                              );
                              return;
                            }

                            if (!mounted) return;

                            // Close coverage dialog first, then open generation dialog on next frame.
                            Navigator.of(dialogContext).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _showGenerationDialog(
                                modeLabel: _buildGenerationModeLabel(
                                  isFocusMode: isFocusMode,
                                  focusCategory: focusCategory,
                                ),
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
                                  color: _menuPastelCream,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: _menuPastelCream,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
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
                            color: _menuPastelTextSoft,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
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

  Color _coverageAccentColor(String category, {bool isFocusCategory = false}) {
    if (isFocusCategory) return const Color(0xFF8C79A8);
    if (category.contains('English')) return _menuPastelAccentDeep;
    if (category.contains('Mathematics')) return const Color(0xFF7293AE);
    if (category.contains('Logical')) return const Color(0xFF9582AF);
    if (category.contains('Mental')) return const Color(0xFFB28D4B);
    return _menuPastelAccentDeep;
  }

  Color _coverageAccentSoft(String category, {bool isFocusCategory = false}) {
    if (isFocusCategory) return const Color(0xFFF1EAF8);
    if (category.contains('English')) return _menuPastelLeafSoft;
    if (category.contains('Mathematics')) return const Color(0xFFE8F0F7);
    if (category.contains('Logical')) return const Color(0xFFF1EAF8);
    if (category.contains('Mental')) return const Color(0xFFF7EFCF);
    return _menuPastelCream;
  }

  Widget _coverageItem(String category, String topic,
      {bool isFocusMode = false, String? focusCategory}) {
    final isFocusCategory = isFocusMode && category == focusCategory;
    final accentColor =
        _coverageAccentColor(category, isFocusCategory: isFocusCategory);
    final accentSoft =
        _coverageAccentSoft(category, isFocusCategory: isFocusCategory);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              _menuPastelCream,
              accentSoft,
              isFocusCategory ? 0.82 : 0.58,
            )!,
            _menuPastelCream,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocusCategory
              ? accentColor.withValues(alpha: 0.34)
              : _menuPastelGlassBorder,
          width: isFocusCategory ? 2 : 1,
        ),
        boxShadow: isFocusCategory
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.12),
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
              color: accentSoft,
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
                          color: _menuPastelText,
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
                          color: accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '10Q',
                          style: GoogleFonts.outfit(
                            color: accentColor,
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
                          color: _menuPastelTextSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
    return _buildFastPromptFromCoverage(_currentTestCoverage!);
  }

  String _buildFastPrompt() {
    if (_currentTestCoverage == null) {
      throw Exception('Test coverage not generated');
    }

    return _buildFastPromptFromCoverage(_currentTestCoverage!);
  }

  String _buildFastPromptFromCoverage(Map<String, String> coverage) {
    final englishTopic = coverage['English'] ?? 'General English topics';
    final mathTopic = coverage['Mathematics'] ?? 'General mathematics topics';
    final logicalReasoningTopic =
        coverage['Logical Reasoning'] ?? 'General logical reasoning topics';
    final mentalAbilityTopic = coverage['Mental Ability / Abstract'] ??
        'General mental ability and abstract topics';

    final questionCount = _examConfigService
            .getModeConfig(_activeExamId, 'randomQuiz')
            ?.questionCount ??
        15;

    return _examConfigService.renderPrompt(
      examId: _activeExamId,
      mode: 'randomQuiz',
      values: {
        'questionCount': '$questionCount',
        'englishTopic': englishTopic,
        'mathTopic': mathTopic,
        'logicalReasoningTopic': logicalReasoningTopic,
        'mentalAbilityTopic': mentalAbilityTopic,
      },
      fallbackTemplate:
          'Generate {{questionCount}} ACET-style multiple-choice questions as raw JSON only.\n\nFormat:\n{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}\n\nDistribution:\nQ1-4 English questions specifically about this key area: {{englishTopic}}\nQ5-8 Mathematics questions specifically about this key area: {{mathTopic}}\nQ9-12 Logical Reasoning questions specifically about this key area: {{logicalReasoningTopic}}\nQ13-15 Mental Ability / Abstract questions specifically about this key area: {{mentalAbilityTopic}}\n\nRules:\n- Exactly 4 choices per question\n- Correct answer must be one of A/B/C/D\n- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"\n- Do not generate meta-questions, topic-identification questions, or questions asking what skill or category is being tested\n- Each item must be a real exam-style question with a clear answer based on reasoning, interpretation, calculation, or pattern recognition\n- No direct recall or pure definition items; require interpretation, application, comparison, inference, computation, or pattern analysis\n- English items may include vocabulary, grammar, sentence logic, short reading, or editing\n- Mathematics items must involve arithmetic, algebra, geometry, word problems, or quantitative reasoning with actual solving required\n- Logical Reasoning items must involve analogies, deductions, sequences, conclusions, or conditional logic\n- Mental Ability / Abstract items must involve symbolic, numeric, alphabetic, matrix, or transformation patterns described in text\n- Choices must be short phrases or short clauses with balanced length and tone\n- At least one wrong choice must be as long as or longer than the correct choice\n- Use plausible distractors based on common student misconceptions\n- Avoid giveaway wording patterns\n- Do not make the correct answer obviously longest or shortest\n- Randomize answer letters across A/B/C/D without obvious streaks\n- Use Unicode math symbols only; no LaTeX or backslashes\n- No markdown, no asterisks, no extra text\n- Return JSON only',
    );
  }

  String _buildFocusPrompt(String focusCategory) {
    return _buildFastFocusPrompt(focusCategory);
  }

  String _buildFastFocusPrompt(String focusCategory) {
    final focusTopic = _currentTestCoverage?[focusCategory] ??
        _pickRandomKeyArea(focusCategory);

    final categories = _categoriesForProgramInterest();
    final otherCategories =
        categories.where((cat) => cat != focusCategory).toList();
    final otherText = otherCategories.map((cat) {
      final topic = _currentTestCoverage?[cat] ?? _pickRandomKeyArea(cat);
      return '$cat: $topic';
    }).join(' | ');

    final questionCount = _examConfigService
            .getModeConfig(_activeExamId, 'focusMode')
            ?.questionCount ??
        15;

    return _examConfigService.renderPrompt(
      examId: _activeExamId,
      mode: 'focusMode',
      values: {
        'questionCount': '$questionCount',
        'focusCategory': focusCategory,
        'focusTopic': focusTopic,
        'otherText': otherText,
      },
      fallbackTemplate:
          'Generate {{questionCount}} ACET-style multiple-choice questions as raw JSON only.\n\nFormat:\n{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}\n\nDistribution:\nQ1-10 focus category: {{focusCategory}}\nQ1-10 key area: {{focusTopic}}\nQ11-15 mixed from: {{otherText}}\n\nRules:\n- Exactly 4 choices per question\n- Correct answer must be one of A/B/C/D\n- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"\n- Do not generate meta-questions, topic-identification questions, or questions asking what skill or category is being tested\n- Each item must be a real exam-style question with a clear answer based on reasoning, interpretation, or calculation\n- Use practical ACET-style scenarios with application and analysis\n- Q1-10 must strongly match the focus category and focus topic while still being real exam items, not lesson labels\n- Q11-15 must be mixed supporting questions from the listed other categories\n- Keep wording concise and academically accurate\n- Keep choices similar in length and tone\n- Make distractors plausible based on common student misconceptions\n- Avoid giveaway wording like always, never, or obvious textbook clues\n- Vary stem style using analysis, inference, best answer, comparison, or problem-solving\n- Do not make the correct answer obviously longest or shortest by wording\n- Randomize answer letters across A/B/C/D without obvious streaks\n- Use Unicode math symbols only when needed; avoid LaTeX and backslashes\n- No markdown, no asterisks, no extra text\n- Return JSON only',
    );
  }

  String _buildChallengeModePrompt(String focusCategory) {
    return _buildFastChallengeModePrompt(focusCategory);
  }

  String _buildFastChallengeModePrompt(String focusCategory) {
    final englishTopic = _pickRandomKeyArea('English');
    final mathTopic = _pickRandomKeyArea('Mathematics');
    final logicalReasoningTopic = _pickRandomKeyArea('Logical Reasoning');
    final mentalAbilityTopic = _pickRandomKeyArea('Mental Ability / Abstract');

    final questionCount = _examConfigService
            .getModeConfig(_activeExamId, 'challenge')
            ?.questionCount ??
        15;

    return _examConfigService.renderPrompt(
      examId: _activeExamId,
      mode: 'challenge',
      values: {
        'questionCount': '$questionCount',
        'englishTopic': englishTopic,
        'mathTopic': mathTopic,
        'logicalReasoningTopic': logicalReasoningTopic,
        'mentalAbilityTopic': mentalAbilityTopic,
      },
      fallbackTemplate:
          'Generate {{questionCount}} hard ACET-style multiple-choice questions as raw JSON only.\n\nFormat:\n{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}\n\nDistribution:\nQ1-4 English questions specifically about this key area: {{englishTopic}}\nQ5-8 Mathematics questions specifically about this key area: {{mathTopic}}\nQ9-12 Logical Reasoning questions specifically about this key area: {{logicalReasoningTopic}}\nQ13-15 Mental Ability / Abstract questions specifically about this key area: {{mentalAbilityTopic}}\n\nRules:\n- Exactly 4 choices per question\n- Correct answer must be one of A/B/C/D\n- Never write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"\n- Do not generate meta-questions, topic-identification questions, or questions asking what skill or category is being tested\n- Each item must be a real exam-style question with one clearly correct answer\n- Challenge items must be harder than random mode and should require deeper analysis, multi-step reasoning, stronger inference, or more careful comparison\n- No direct recall or pure definition items\n- English items should emphasize difficult context clues, grammar traps, editing, sentence logic, and compact reading tasks\n- Mathematics items should emphasize multi-step arithmetic, algebra, geometry, or data tasks that require careful setup\n- Logical Reasoning items should emphasize layered deductions, assumptions, conclusions, argument evaluation, or elimination under constraints\n- Mental Ability / Abstract items should emphasize multi-rule patterns, matrix logic, transformations, symbolic mapping, or abstract sequence analysis\n- Keep wording concise but cognitively demanding\n- Choices must be similar in length and tone\n- At least one incorrect choice must be as long as or longer than the correct answer\n- Use plausible distractors based on common student misconceptions\n- Avoid giveaway wording patterns\n- Do not make the correct answer obviously longest or shortest\n- Randomize answer letters across A/B/C/D without obvious streaks\n- Use Unicode math symbols only; no LaTeX or backslashes\n- No markdown, no asterisks, no extra text\n- Return JSON only',
    );
  }

  String _buildTimedModePrompt() {
    if (_currentTestCoverage == null) {
      throw Exception('Test coverage not generated');
    }

    return _buildTimedModePromptFromCoverage(_currentTestCoverage!);
  }

  String _buildFastTimedModePrompt() {
    if (_currentTestCoverage == null) {
      throw Exception('Test coverage not generated');
    }

    return _buildTimedModePromptFromCoverage(_currentTestCoverage!);
  }

  String _buildTimedModePromptFromCoverage(Map<String, String> coverage) {
    final englishTopic = coverage['English'] ?? 'General English topics';
    final mathTopic = coverage['Mathematics'] ?? 'General mathematics topics';
    final logicalReasoningTopic =
        coverage['Logical Reasoning'] ?? 'General logical reasoning topics';
    final mentalAbilityTopic = coverage['Mental Ability / Abstract'] ??
        'General mental ability and abstract topics';

    final questionCount = _examConfigService
            .getModeConfig(_activeExamId, 'timedExam')
            ?.questionCount ??
        15;

    return _examConfigService.renderPrompt(
      examId: _activeExamId,
      mode: 'timedExam',
      values: {
        'questionCount': '$questionCount',
        'englishTopic': englishTopic,
        'mathTopic': mathTopic,
        'logicalReasoningTopic': logicalReasoningTopic,
        'mentalAbilityTopic': mentalAbilityTopic,
      },
      fallbackTemplate:
          'Generate {{questionCount}} timed-practice ACET-style multiple-choice questions as raw JSON only.\n\nFormat:\n{"questions":[{"number":1,"question":"...","choices":["A","B","C","D"],"answer":"A"}]}\n\nDistribution:\nQ1-4 English questions specifically about this key area: {{englishTopic}}\nQ5-8 Mathematics questions specifically about this key area: {{mathTopic}}\nQ9-12 Logical Reasoning questions specifically about this key area: {{logicalReasoningTopic}}\nQ13-15 Mental Ability / Abstract questions specifically about this key area: {{mentalAbilityTopic}}\n\nRules:\nExactly 4 choices per question\nCorrect answer must be one of A/B/C/D\nNever write combined-option choices like "A and B", "A and C", "both A and B", or "all of the above"\nDo not generate meta-questions, topic-identification questions, or questions asking what skill or category is being tested\nEach item must be a real exam-style question with a clear answer based on reasoning, interpretation, calculation, or pattern recognition\nTimed mode items must be medium difficulty, concise, and realistically answerable under time pressure\nPrefer shorter stems, faster recognition, shorter computation, and clean wording\nNo direct recall or pure definition items\nEnglish items should favor concise context clues, grammar, sentence logic, or short reading tasks\nMathematics items should favor shorter arithmetic, algebra, geometry, or data tasks that still require genuine solving\nLogical Reasoning items should favor direct but nontrivial deductions, analogy recognition, ordering, or condition-based elimination\nMental Ability / Abstract items should favor concise sequence, matrix, transformation, or symbolic pattern recognition\nChoices must be short phrases or short clauses with balanced length and tone\nAt least one wrong choice must be as long as or longer than the correct choice\nUse plausible distractors based on common student misconceptions\nAvoid giveaway wording patterns\nDo not make the correct answer obviously longest or shortest\nRandomize answer letters across A/B/C/D without obvious streaks\nUse Unicode math symbols only; no LaTeX or backslashes\nNo markdown, no asterisks, no extra text\nReturn JSON only',
    );
  }
}

class _ReadinessLinePainter extends CustomPainter {
  final List<double> points;

  _ReadinessLinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFBFD0AE).withValues(alpha: 0.34)
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final stepX = points.length > 1 ? size.width / (points.length - 1) : 0.0;

    final linePath = Path();
    final dotOffsets = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final x = stepX * i;
      final y =
          size.height - (points[i].clamp(0.0, 100.0) / 100.0) * size.height;
      final point = Offset(x, y);
      dotOffsets.add(point);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final areaPath = Path.from(linePath)
      ..lineTo(dotOffsets.last.dx, size.height)
      ..lineTo(dotOffsets.first.dx, size.height)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          PnleTheme.success.withValues(alpha: 0.32),
          PnleTheme.success.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [PnleTheme.success, PnleTheme.info],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(areaPath, areaPaint);
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = PnleTheme.success;
    final dotStroke = Paint()
      ..color = _MenuScreenState._menuPastelCream
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final offset in dotOffsets) {
      canvas.drawCircle(offset, 3.2, dotPaint);
      canvas.drawCircle(offset, 3.2, dotStroke);
    }

    for (int i = 0; i < dotOffsets.length; i++) {
      final pctText = '${points[i].toStringAsFixed(1)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: pctText,
          style: const TextStyle(
            color: _MenuScreenState._menuPastelText,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final dx = (dotOffsets[i].dx - (textPainter.width / 2))
          .clamp(0.0, size.width - textPainter.width);
      final preferredY = dotOffsets[i].dy - 16;
      final fallbackY = dotOffsets[i].dy + 6;
      final dy = preferredY >= 0
          ? preferredY
          : fallbackY.clamp(0.0, size.height - textPainter.height);
      textPainter.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _ReadinessLinePainter oldDelegate) {
    if (oldDelegate.points.length != points.length) {
      return true;
    }
    for (int i = 0; i < points.length; i++) {
      if (oldDelegate.points[i] != points[i]) {
        return true;
      }
    }
    return false;
  }
}

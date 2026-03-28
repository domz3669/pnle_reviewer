import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'services/sound_service.dart';
import 'dart:convert';

import 'config/secrets.dart';
import 'config/admob_ids.dart';
import 'config/pnle_theme.dart';
import 'models/acet_assessment.dart';
import 'models/question.dart';
import 'utils/responsive.dart';
import 'animated_results_dialog.dart';
import 'explanation_dialog.dart';
import 'better_explanation_dialog.dart';
import 'services/acet_assessment_service.dart';
import 'services/review_service.dart';
import 'services/gemini_service.dart';
import 'services/gpt_service.dart';

const String _reportingAppName = 'ACET Reviewer 2027';
const _quizDialogCream = Color(0xFFFCF6EB);
const _quizDialogPanel = Color(0xFFF9F3E7);
const _quizDialogText = Color(0xFF5A7652);
const _quizDialogTextSoft = Color(0xFF8AA081);
const _quizDialogBorder = Color(0xA4C5D6AE);
const _quizDialogLeaf = Color(0xFF7EA468);
const _quizDialogLeafSoft = Color(0xFFDDEBCE);
const _quizDialogSkySoft = Color(0xFFE6EFF7);
const _quizDialogWarm = Color(0xFFC28D74);
const _quizDialogWarmSoft = Color(0xFFF4E3D9);
const _quizDialogButter = Color(0xFFB28D4B);
const _quizDialogButterSoft = Color(0xFFF7EFCF);
const _quizScreenBackground = Color(0xFFFCF6EB);
const _quizScreenPanel = Color(0xFFF9F3E7);
const _quizAnswerCorrect = Color(0xFF7EA468);
const _quizAnswerCorrectDeep = Color(0xFF698C59);
const _quizAnswerWrong = Color(0xFFC28D74);
const _quizAnswerWrongDeep = Color(0xFFAE765F);

class QuestionScreen extends StatefulWidget {
  final List<Question> questions;
  final bool hasUnlimitedAccess;
  final bool strictTimingEnabled;
  final bool recordResults;
  final String testMode; // 'randomQuiz' or 'focusMode' or 'previous'
  final int zeroAdSessionsRemaining;
  final int initialIndex;
  final Map<String, int>? initialCorrectCount;
  final int initialElapsedSeconds;
  final List<AcetQuestionAttempt>? initialAttempts;

  const QuestionScreen({
    super.key,
    required this.questions,
    this.hasUnlimitedAccess = false,
    this.strictTimingEnabled = false,
    this.recordResults = true,
    this.testMode = 'randomQuiz',
    this.zeroAdSessionsRemaining = 0,
    this.initialIndex = 0,
    this.initialCorrectCount,
    this.initialElapsedSeconds = 0,
    this.initialAttempts,
  });

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _ReportSubmissionDialogState {
  final bool isLoading;
  final bool sentSuccessfully;
  final String title;
  final String detail;

  const _ReportSubmissionDialogState({
    required this.isLoading,
    required this.sentSuccessfully,
    required this.title,
    required this.detail,
  });

  const _ReportSubmissionDialogState.loading()
      : isLoading = true,
        sentSuccessfully = false,
        title = 'Sending your report...',
        detail =
            'Please wait while we submit this question to the review queue and save a local backup.';
}

class _QuestionScreenState extends State<QuestionScreen>
    with TickerProviderStateMixin {
  int currentIndex = 0;
  int? selectedChoiceIndex;
  bool _answerSelected = false;
  bool _explanationRequested = false;
  int explanationCount = 0; // Track explanation requests per session
  bool _explainAdUnlockedForCurrentQuestion = false;
  int _explainAdUnlockCount = 0;
  static const int _freeExplainLimit = 4;
  static const int _maxExplainAdUnlocks = 2;

  // Pre-loaded sound service for zero-latency playback
  final SoundService _soundService = SoundService();
  final AcetAssessmentService _acetAssessmentService =
      const AcetAssessmentService();

  // Track total time spent on the quiz
  final Stopwatch _quizStopwatch = Stopwatch();

  // Animation controllers for choice feedback
  late AnimationController _choiceAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shakeAnimation;

  // Banner Ad
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  int _bannerLoadRetryCount = 0;
  static const int _maxBannerLoadRetries = 3;

  // Interstitial Ad
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  bool _isSubmittingReport = false;

  // Interstitial Ad for explain-limit unlock
  InterstitialAd? _explainInterstitialAd;
  bool _isExplainInterstitialAdLoaded = false;

  // =========================
  // ANSWER & SCORE HELPERS
  // =========================
  int get _correctIndex {
    return currentQuestion.answer.codeUnitAt(0) - 65;
  }

  final Map<String, int> _correctCount = {};

  final Map<String, int> _totalCount = {};
  final List<Map<String, dynamic>> _mistakes = [];
  final Set<int> _recordedMistakeQuestionIndexes = <int>{};
  final List<AcetQuestionAttempt> _questionAttempts = <AcetQuestionAttempt>[];
  final Set<int> _recordedAttemptQuestionNumbers = <int>{};
  int _elapsedOffsetSeconds = 0;

  // =========================
  // TIMER (Dynamic based on category)
  // =========================
  late AnimationController _timeController;

  int get _currentMaxTime => _getTimerForCategory(currentQuestion.category);

  /// Get timer duration based on question category
  int _getTimerForCategory(String category) {
    if (_usesStrictTiming) {
      switch (category) {
        case 'Mathematics':
          return 40;
        case 'English':
        case 'Logical Reasoning':
        case 'Mental Ability / Abstract':
        default:
          return 35;
      }
    }

    final isChallenge = widget.testMode == 'challenge';
    switch (category) {
      case 'English':
        return isChallenge ? 65 : 45;
      case 'Mathematics':
        return isChallenge ? 85 : 60;
      case 'Logical Reasoning':
      case 'Mental Ability / Abstract':
        return isChallenge ? 75 : 55;
      default:
        return isChallenge ? 75 : 55;
    }
  }

  bool _timeUp = false;
  bool _isLocked = false;
  bool _autoAdvanceQueued = false;

  bool get _isTimedExamMode => widget.testMode == 'timedExam';
  bool get _usesStrictTiming => _isTimedExamMode || widget.strictTimingEnabled;
  bool get _isVisualQuestion =>
      (currentQuestion.imageAssetPath?.isNotEmpty ?? false);

  bool get _hasVisualPromptText => currentQuestion.question.trim().isNotEmpty;

  Question get currentQuestion => widget.questions[currentIndex];

  String _sourceSuffixForCurrentQuestion() {
    final source = (currentQuestion.source ?? '').toLowerCase();
    if (source == 'deepseek') return '-D';
    if (source == 'gemini') return '-G';
    return '';
  }

  // =========================
  // LIFECYCLE
  // =========================
  @override
  void initState() {
    super.initState();

    currentIndex = widget.initialIndex.clamp(0, widget.questions.length - 1);
    _elapsedOffsetSeconds =
        widget.initialElapsedSeconds < 0 ? 0 : widget.initialElapsedSeconds;

    // Play quiz start sound effect (pre-loaded, instant)
    _soundService.playStartQuiz();

    // Start tracking total quiz time
    _quizStopwatch.start();

    // Count total questions per category
    for (final q in widget.questions) {
      _totalCount[q.category] = (_totalCount[q.category] ?? 0) + 1;
    }

    // Initialize correct count for all categories (including zeros)
    for (final category in _totalCount.keys) {
      _correctCount.putIfAbsent(category, () => 0);
    }

    final initialCorrect = widget.initialCorrectCount;
    if (initialCorrect != null) {
      for (final entry in initialCorrect.entries) {
        if (_correctCount.containsKey(entry.key)) {
          _correctCount[entry.key] = entry.value < 0 ? 0 : entry.value;
        }
      }
    }

    final initialAttempts = widget.initialAttempts;
    if (initialAttempts != null) {
      _questionAttempts
        ..clear()
        ..addAll(initialAttempts);
      _recordedAttemptQuestionNumbers
        ..clear()
        ..addAll(initialAttempts.map((attempt) => attempt.questionNumber));
    }

    _timeController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _currentMaxTime),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _onTimeUp();
        }
      });

    _choiceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Scale animation: ultra-smooth pop effect for correct answers
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _choiceAnimationController,
        curve: Curves.easeOut,
      ),
    );

    // Shake animation: horizontal oscillation for wrong answers
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _choiceAnimationController,
        curve: Curves.linear,
      ),
    );

    _startTimer();
    if (!widget.hasUnlimitedAccess) {
      _loadBannerAd();
    }
    // Don't load interstitial ads for Quick Practice mode
    if (!widget.hasUnlimitedAccess && widget.testMode != 'quickPractice') {
      _loadInterstitialAd();
    }
    if (!widget.hasUnlimitedAccess) {
      _loadExplainInterstitialAd();
    }
  }

  String _bannerAdUnitId() {
    return AdMobIds.banner;
  }

  String _interstitialAdUnitId() {
    return AdMobIds.interstitial;
  }

  String _explainInterstitialAdUnitId() {
    return AdMobIds.interstitial;
  }

  void _loadBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId(),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdLoaded = true;
            _bannerLoadRetryCount = 0;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _isBannerAdLoaded = false;
          debugPrint(
              'Banner ad failed to load (${error.code}: ${error.message})');
          if (!mounted || widget.hasUnlimitedAccess) return;
          if (_bannerLoadRetryCount >= _maxBannerLoadRetries) return;
          _bannerLoadRetryCount++;
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted || widget.hasUnlimitedAccess) return;
            _loadBannerAd();
          });
        },
      ),
    )..load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId(),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoaded = false;
          debugPrint(
            'Interstitial ad failed to load (${error.code}: ${error.message})',
          );
        },
      ),
    );
  }

  void _loadExplainInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _explainInterstitialAdUnitId(),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _explainInterstitialAd = ad;
          _isExplainInterstitialAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isExplainInterstitialAdLoaded = false;
          debugPrint(
            'Explain interstitial ad failed to load (${error.code}: ${error.message})',
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _timeController.dispose();
    _choiceAnimationController.dispose();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _explainInterstitialAd?.dispose();
    super.dispose();
  }

  // =========================
  // TIMER CONTROL
  // =========================
  void _startTimer() {
    _timeController.reset();
    _timeController.forward();
  }

  void _onTimeUp() {
    setState(() {
      _timeUp = true;
      _isLocked = true;
      _answerSelected = true;
    });
    // Play wrong answer sound if user didn't answer
    if (selectedChoiceIndex == null) {
      _recordQuestionAttempt(
        answered: false,
        isCorrect: false,
        timedOut: true,
        timeSeconds: _currentMaxTime,
      );
      _recordMistake(
        questionIndex: currentIndex,
        selectedAnswer: null,
        timedOut: true,
      );
      _soundService.playWrongAnswer();
    }

    if (_usesStrictTiming && !_autoAdvanceQueued) {
      _autoAdvanceQueued = true;
      Future.delayed(const Duration(milliseconds: 650), () {
        _autoAdvanceQueued = false;
        if (!mounted) return;
        if (_timeUp && _isLocked && _answerSelected) {
          _nextQuestion();
        }
      });
    }
  }

  String _answerLetterForIndex(int index) {
    if (index < 0 || index >= 26) return '';
    return String.fromCharCode(65 + index);
  }

  int _timeSpentForCurrentQuestion({bool timedOut = false}) {
    if (timedOut) return _currentMaxTime;
    final spent = (_currentMaxTime * _timeController.value).round();
    return spent.clamp(0, _currentMaxTime);
  }

  void _recordQuestionAttempt({
    required bool answered,
    required bool isCorrect,
    required bool timedOut,
    int? timeSeconds,
  }) {
    final questionNumber = currentQuestion.number;
    if (_recordedAttemptQuestionNumbers.contains(questionNumber)) {
      return;
    }

    _recordedAttemptQuestionNumbers.add(questionNumber);
    _questionAttempts.add(
      AcetQuestionAttempt(
        questionNumber: questionNumber,
        category: currentQuestion.category,
        timeSeconds:
            (timeSeconds ?? _timeSpentForCurrentQuestion(timedOut: timedOut))
                .clamp(0, _currentMaxTime),
        isCorrect: isCorrect,
        answered: answered,
        timedOut: timedOut,
      ),
    );
  }

  AcetAssessment _buildAssessment() {
    return _acetAssessmentService.buildAssessment(
      attempts: _questionAttempts,
      categoryTotals: Map<String, int>.from(_totalCount),
    );
  }

  void _recordMistake({
    required int questionIndex,
    required String? selectedAnswer,
    required bool timedOut,
  }) {
    if (questionIndex < 0 || questionIndex >= widget.questions.length) return;
    if (_recordedMistakeQuestionIndexes.contains(questionIndex)) return;

    final question = widget.questions[questionIndex];
    _recordedMistakeQuestionIndexes.add(questionIndex);
    _mistakes.add({
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
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Map<String, dynamic> _buildResumeStatePayload({required int elapsedSeconds}) {
    final resumeIndex =
        (_answerSelected && currentIndex < widget.questions.length - 1)
            ? currentIndex + 1
            : currentIndex;

    return {
      'questions': widget.questions
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
      'currentIndex': resumeIndex,
      'correctCount': Map<String, int>.from(_correctCount),
      'elapsedSeconds': elapsedSeconds,
      'testMode': widget.testMode,
      'recordResults': widget.recordResults,
      'assessmentAttempts':
          _questionAttempts.map((attempt) => attempt.toJson()).toList(),
    };
  }

  Map<String, dynamic> _buildResultPayload({
    required String nextAction,
    required int elapsedSeconds,
    required AcetAssessment assessment,
  }) {
    return {
      'correctCount': Map<String, int>.from(_correctCount),
      'totalCount': Map<String, int>.from(_totalCount),
      'nextAction': nextAction,
      'testMode': widget.testMode,
      'recordResults': widget.recordResults,
      'mistakes': List<Map<String, dynamic>>.from(_mistakes),
      'elapsedSeconds': elapsedSeconds,
      'assessment': assessment.toJson(),
      'assessmentAttempts':
          _questionAttempts.map((attempt) => attempt.toJson()).toList(),
    };
  }

  Color _timeColorFromRatio(double ratio) {
    if (ratio > 0.6) return _quizDialogLeaf;
    if (ratio > 0.3) return _quizDialogButter;
    return PnleTheme.danger;
  }

  void _showQuizSnackBar(
    String message, {
    Color accent = _quizDialogLeaf,
    int seconds = 2,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: Duration(seconds: seconds),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_quizDialogPanel, _quizDialogCream, 0.3)!,
                _quizDialogPanel,
                Color.lerp(_quizDialogPanel, _quizDialogSkySoft, 0.18)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Icons.info_outline_rounded, color: accent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.outfit(
                    color: _quizDialogText,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _showPauseExitDialog() async {
    final shouldPause = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_quizDialogPanel, _quizDialogLeafSoft, 0.18)!,
                _quizDialogPanel,
                Color.lerp(_quizDialogPanel, _quizDialogWarmSoft, 0.16)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _quizDialogBorder, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _quizDialogLeaf.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _quizDialogLeafSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.pause_circle_outline_rounded,
                      color: _quizDialogLeaf,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pause And Exit?',
                      style: GoogleFonts.outfit(
                        color: _quizDialogText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Your current progress will be saved so you can continue this quiz later.',
                style: GoogleFonts.outfit(
                  color: _quizDialogTextSoft,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _quizDialogBorder),
                        backgroundColor: _quizDialogCream,
                        foregroundColor: _quizDialogText,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Continue Quiz',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _quizDialogLeaf,
                        foregroundColor: _quizDialogCream,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Pause Exit',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
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

    return shouldPause ?? false;
  }

  Widget _animatedTimeBar() {
    return AnimatedBuilder(
      animation: _timeController,
      builder: (context, _) {
        final ratio = (1.0 - _timeController.value).clamp(0.03, 1.0);
        final isCritical = ratio <= 0.3;
        final barColor = _timeColorFromRatio(ratio);
        final secondsLeft = (_currentMaxTime * (1.0 - _timeController.value))
            .clamp(0.0, _currentMaxTime.toDouble());

        return Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, barConstraints) {
                  final barWidth = barConstraints.maxWidth * ratio;
                  return Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: _quizDialogLeafSoft.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      children: [
                        // Main progress bar
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: barWidth,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  barColor.withValues(alpha: 0.95),
                                  barColor.withValues(alpha: 0.72),
                                  _quizDialogCream.withValues(alpha: 0.38),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: isCritical
                                  ? [
                                      BoxShadow(
                                        color: barColor.withValues(alpha: 0.7),
                                        blurRadius: 10,
                                        spreadRadius: 1.5,
                                      ),
                                    ]
                                  : [],
                            ),
                          ),
                        ),
                        // Sparkle tip effect
                        if (barWidth > 8)
                          Positioned(
                            left: barWidth - 6,
                            top: 0,
                            bottom: 0,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(_timeController.value),
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeInOut,
                              builder: (context, value, child) {
                                final sparkleOpacity = (1.0 - value) * 0.8;
                                final sparkleSize = 3.0 + (value * 2);
                                return Center(
                                  child: Container(
                                    width: sparkleSize,
                                    height: sparkleSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white
                                          .withValues(alpha: sparkleOpacity),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white.withValues(
                                              alpha: sparkleOpacity * 0.6),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: Text(
                '${secondsLeft.toStringAsFixed(1)}s',
                textAlign: TextAlign.right,
                style: GoogleFonts.outfit(
                  color: barColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================
  // ANSWER COLOR LOGIC
  // =========================
  Color _choiceColor(int index) {
    // When time is up, highlight all choices red
    if (_timeUp) {
      return _quizAnswerWrong;
    }

    // When answer is selected, only highlight the user's choice
    if (_answerSelected && selectedChoiceIndex == index) {
      return index == _correctIndex ? _quizAnswerCorrect : _quizAnswerWrong;
    }

    return _quizDialogCream;
  }

  LinearGradient? _choiceGradient(int index) {
    return null;
  }

  Color _choiceBorderColor(int index) {
    if (_timeUp) return _quizAnswerWrongDeep;
    if (_answerSelected && selectedChoiceIndex == index) {
      return index == _correctIndex
          ? _quizAnswerCorrectDeep
          : _quizAnswerWrongDeep;
    }
    return _quizDialogBorder;
  }

  Color _choiceTextColor(int index) {
    if (_timeUp) return _quizDialogCream;
    if (_answerSelected && selectedChoiceIndex == index) {
      return _quizDialogCream;
    }
    return _quizDialogText;
  }

  // =========================
  // HELPER METHODS
  // =========================
  bool _canUseExplainWhy() {
    if (widget.hasUnlimitedAccess) return true;
    if (_explainAdUnlockedForCurrentQuestion) return true;
    return explanationCount < _freeExplainLimitForCurrentMode;
  }

  bool _canOfferExplainAdUnlock() {
    if (widget.hasUnlimitedAccess) return false;
    if (_canUseExplainWhy()) return false;
    return _explainAdUnlockCount < _maxExplainAdUnlocksForCurrentMode;
  }

  int get _freeExplainLimitForCurrentMode {
    return widget.testMode == 'quickPractice' ? 1 : _freeExplainLimit;
  }

  int get _maxExplainAdUnlocksForCurrentMode {
    return widget.testMode == 'quickPractice' ? 1 : _maxExplainAdUnlocks;
  }

  // =========================
  // REPORT CONTENT
  // =========================
  void _reportContent() async {
    if (_isSubmittingReport || !mounted) return;

    _isSubmittingReport = true;
    final question = currentQuestion.question;
    final reportWebhookUrl = REPORT_CONTENT_WEBHOOK_URL.trim();
    final dialogState = ValueNotifier<_ReportSubmissionDialogState>(
      const _ReportSubmissionDialogState.loading(),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => ValueListenableBuilder<_ReportSubmissionDialogState>(
        valueListenable: dialogState,
        builder: (dialogContext, state, _) {
          final statusColor = state.isLoading
              ? PnleTheme.accent
              : (state.sentSuccessfully
                  ? PnleTheme.success
                  : PnleTheme.warning);
          final statusIcon = state.isLoading
              ? null
              : (state.sentSuccessfully
                  ? Icons.task_alt_rounded
                  : Icons.save_outlined);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(_quizDialogPanel, _quizDialogLeafSoft, 0.2)!,
                    _quizDialogPanel,
                    Color.lerp(_quizDialogPanel, _quizDialogSkySoft, 0.24)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: state.isLoading
                      ? _quizDialogBorder
                      : statusColor.withValues(alpha: 0.32),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _quizDialogLeaf.withValues(alpha: 0.12),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: state.isLoading
                              ? _quizDialogCream
                              : statusColor.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: state.isLoading
                                ? _quizDialogBorder
                                : statusColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: state.isLoading
                            ? SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    statusColor,
                                  ),
                                ),
                              )
                            : Icon(
                                statusIcon,
                                color: statusColor,
                                size: 28,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.isLoading
                                  ? 'Submitting Report'
                                  : 'Report Submitted',
                              style: GoogleFonts.outfit(
                                color: _quizDialogText,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              state.title,
                              style: GoogleFonts.outfit(
                                color: _quizDialogTextSoft,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Question reported',
                    style: GoogleFonts.outfit(
                      color: _quizDialogLeaf,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _quizDialogCream,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _quizDialogBorder,
                      ),
                    ),
                    child: Text(
                      question,
                      style: GoogleFonts.outfit(
                        color: _quizDialogText,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.detail,
                    style: GoogleFonts.outfit(
                      color: _quizDialogTextSoft,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: state.isLoading
                        ? Text(
                            'Sending...',
                            style: GoogleFonts.outfit(
                              color: _quizDialogTextSoft,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          )
                        : FilledButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: state.sentSuccessfully
                                  ? _quizDialogLeaf
                                  : statusColor,
                              foregroundColor: _quizDialogCream,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'OK',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      dialogState.dispose();
      _isSubmittingReport = false;
    });

    // Try to send report via backend webhook
    bool sentSuccessfully = false;
    if (reportWebhookUrl.isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse(reportWebhookUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'appName': _reportingAppName,
                'question': question,
                'category': currentQuestion.category,
                'questionNumber': currentQuestion.number,
                'timestamp': DateTime.now().toIso8601String(),
                'testMode': widget.testMode,
              }),
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 201) {
          sentSuccessfully = true;
        }
      } catch (e) {
        debugPrint('Failed to send report via webhook: $e');
      }
    }

    // Always store locally as backup
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = prefs.getStringList('pendingReports') ?? [];

      final reportEntry = {
        'appName': _reportingAppName,
        'question': question,
        'category': currentQuestion.category,
        'timestamp': DateTime.now().toIso8601String(),
        'questionNumber': currentQuestion.number,
        'testMode': widget.testMode,
        'synced': sentSuccessfully,
      };

      reports.add(jsonEncode(reportEntry));
      await prefs.setStringList('pendingReports', reports);
    } catch (e) {
      debugPrint('Error storing local report: $e');
    }

    if (!mounted) {
      _isSubmittingReport = false;
      return;
    }

    final statusTitle = sentSuccessfully
        ? 'Your report was added to the review queue.'
        : 'Your report was saved on this device.';
    final statusDetail = sentSuccessfully
        ? 'Thank you for flagging the issue. We will review it from the moderator queue.'
        : (reportWebhookUrl.isEmpty
            ? 'This build does not have the report service configured yet, so the report was stored locally only.'
            : 'The report service is temporarily unavailable, so the report was stored locally as a backup.');
    dialogState.value = _ReportSubmissionDialogState(
      isLoading: false,
      sentSuccessfully: sentSuccessfully,
      title: statusTitle,
      detail: statusDetail,
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(color: _quizScreenBackground),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // HEADER
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _quizDialogCream,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _quizDialogBorder,
                            ),
                          ),
                          child: Text(
                            currentQuestion.category,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: _quizDialogText,
                              fontSize: r.fontSize(11),
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _quizDialogLeafSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _quizDialogLeaf.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Q${currentIndex + 1}/${widget.questions.length}${_sourceSuffixForCurrentQuestion()}',
                          style: GoogleFonts.outfit(
                            color: _quizDialogLeaf,
                            fontSize: r.fontSize(11),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _reportContent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _quizDialogWarmSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _quizDialogWarm.withValues(alpha: 0.38),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.flag_outlined,
                                color: PnleTheme.danger,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Report',
                                style: GoogleFonts.outfit(
                                  color: _quizDialogWarm,
                                  fontWeight: FontWeight.w600,
                                  fontSize: r.fontSize(12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _usesStrictTiming
                            ? 'Strict timing session must be submitted before exiting.'
                            : 'Return to menu',
                        child: GestureDetector(
                          onTap: _menuPressed,
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: _usesStrictTiming
                                  ? _quizDialogLeafSoft.withValues(alpha: 0.75)
                                  : _quizDialogCream,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _usesStrictTiming
                                    ? _quizDialogBorder.withValues(alpha: 0.9)
                                    : _quizDialogBorder,
                              ),
                            ),
                            child: Icon(
                              Icons.home_rounded,
                              color: _usesStrictTiming
                                  ? _quizDialogTextSoft
                                  : _quizDialogText,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // QUESTION BOX (content-driven with capped height)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.40,
                    ),
                    child: Container(
                      padding: _isVisualQuestion
                          ? const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 24,
                            ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(
                                _quizScreenPanel, _quizDialogLeafSoft, 0.16)!,
                            _quizScreenPanel,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _quizDialogBorder,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _quizDialogLeaf.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _isVisualQuestion
                          ? SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_hasVisualPromptText)
                                    Text(
                                      currentQuestion.question,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: currentQuestion
                                                    .question.length >
                                                300
                                            ? r.fontSize(15)
                                            : currentQuestion.question.length >
                                                    200
                                                ? r.fontSize(16)
                                                : r.fontSize(18),
                                        fontWeight: FontWeight.w400,
                                        color: _quizDialogText,
                                        height: 1.4,
                                      ),
                                    ),
                                  if (_hasVisualPromptText)
                                    const SizedBox(height: 10),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.of(context).size.height *
                                              0.26,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        showDialog<void>(
                                          context: context,
                                          builder: (_) => Dialog(
                                            backgroundColor: Colors.black
                                                .withValues(alpha: 0.82),
                                            insetPadding:
                                                const EdgeInsets.all(12),
                                            child: InteractiveViewer(
                                              minScale: 1.0,
                                              maxScale: 4.0,
                                              child: AspectRatio(
                                                aspectRatio: 4 / 3,
                                                child: Image.asset(
                                                  currentQuestion
                                                      .imageAssetPath!,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.asset(
                                          currentQuestion.imageAssetPath!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) {
                                            return Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: _quizDialogCream,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: _quizDialogBorder,
                                                ),
                                              ),
                                              child: Text(
                                                'Image could not be loaded.',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.outfit(
                                                  color: _quizDialogTextSoft,
                                                  fontSize: r.fontSize(12),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentQuestion.question,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      fontSize:
                                          currentQuestion.question.length > 300
                                              ? r.fontSize(15)
                                              : currentQuestion
                                                          .question.length >
                                                      200
                                                  ? r.fontSize(16)
                                                  : r.fontSize(18),
                                      fontWeight: FontWeight.w400,
                                      color: _quizDialogText,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // PROGRESS BAR
                  _animatedTimeBar(),
                  const SizedBox(height: 16),

                  // CHOICES BOX (Dynamic height, scrollable, vertically centered)
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            currentQuestion.choices.length,
                            (index) => GestureDetector(
                              onTap: (_isLocked || _timeUp)
                                  ? null
                                  : () {
                                      final isCorrect = index == _correctIndex;
                                      final timeSpent =
                                          _timeSpentForCurrentQuestion();

                                      _recordQuestionAttempt(
                                        answered: true,
                                        isCorrect: isCorrect,
                                        timedOut: false,
                                        timeSeconds: timeSpent,
                                      );

                                      setState(() {
                                        selectedChoiceIndex = index;
                                        _isLocked = true;
                                        _answerSelected = true;

                                        if (isCorrect) {
                                          _correctCount[
                                                  currentQuestion.category] =
                                              (_correctCount[currentQuestion
                                                          .category] ??
                                                      0) +
                                                  1;
                                        }
                                      });

                                      if (isCorrect) {
                                        _soundService.playCorrectAnswer();
                                      } else {
                                        _recordMistake(
                                          questionIndex: currentIndex,
                                          selectedAnswer:
                                              _answerLetterForIndex(index),
                                          timedOut: false,
                                        );
                                        _soundService.playWrongAnswer();
                                      }

                                      _timeController.stop();
                                      // Trigger animation
                                      _choiceAnimationController.forward(
                                          from: 0);
                                    },
                              child: AnimatedBuilder(
                                animation: _choiceAnimationController,
                                builder: (context, child) {
                                  if (child == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final isAnimating = _answerSelected &&
                                      selectedChoiceIndex == index &&
                                      _choiceAnimationController.isAnimating;
                                  final isCorrect = index == _correctIndex;

                                  if (isAnimating && isCorrect) {
                                    return Transform.scale(
                                      scale: _scaleAnimation.value,
                                      alignment: Alignment.center,
                                      child: child,
                                    );
                                  }

                                  if (isAnimating && !isCorrect) {
                                    // Oscillate left-right: -10px, 10px, -10px, etc
                                    final shakeAmount = _shakeAnimation.value;
                                    final oscillation =
                                        (sin(shakeAmount * pi * 4) * 10);
                                    return Transform.translate(
                                      offset: Offset(oscillation, 0),
                                      child: child,
                                    );
                                  }

                                  return child;
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  constraints:
                                      const BoxConstraints(minHeight: 60),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: _choiceGradient(index) == null
                                        ? _choiceColor(index)
                                        : null,
                                    gradient: _choiceGradient(index),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _choiceBorderColor(index),
                                      width: 1.2,
                                    ),
                                    boxShadow: _answerSelected &&
                                            selectedChoiceIndex == index
                                        ? [
                                            BoxShadow(
                                              color: _choiceBorderColor(index)
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 12,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color: _quizDialogLeaf.withValues(
                                                  alpha: 0.05),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${String.fromCharCode(65 + index)}.',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: r.fontSize(16),
                                          color: _choiceTextColor(index),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          currentQuestion.choices[index],
                                          style: GoogleFonts.outfit(
                                            fontSize: r.fontSize(15),
                                            color: _choiceTextColor(index),
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // BANNER AD (placed above bottom actions)
                  if (!widget.hasUnlimitedAccess &&
                      _isBannerAdLoaded &&
                      _bannerAd != null) ...[
                    SizedBox(
                      height: 50,
                      child: Center(
                        child: SizedBox(
                          width: _bannerAd!.size.width.toDouble(),
                          height: _bannerAd!.size.height.toDouble(),
                          child: AdWidget(ad: _bannerAd!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // BOTTOM ACTIONS: EXPLAIN + NEXT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Explain Why Button
                      Builder(
                        builder: (context) {
                          final hasExplainAccess = _canUseExplainWhy();
                          final canOfferExplainAd = _canOfferExplainAdUnlock();
                          final canTapExplain = _answerSelected &&
                              !_explanationRequested &&
                              (hasExplainAccess || canOfferExplainAd);

                          return Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: (canTapExplain && hasExplainAccess)
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFFA8C795),
                                          Color(0xFF7EA468),
                                        ],
                                      )
                                    : (canTapExplain && !hasExplainAccess)
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFFF0D9A6),
                                              Color(0xFFBE8E75),
                                            ],
                                          )
                                        : LinearGradient(
                                            colors: [
                                              _quizDialogCream,
                                              _quizScreenPanel,
                                            ],
                                          ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: (canTapExplain && hasExplainAccess)
                                      ? _quizDialogLeaf.withValues(alpha: 0.5)
                                      : (canTapExplain && !hasExplainAccess)
                                          ? _quizDialogWarm.withValues(
                                              alpha: 0.75)
                                          : _quizDialogBorder,
                                  width: 1.5,
                                ),
                                boxShadow: (canTapExplain && hasExplainAccess)
                                    ? [
                                        BoxShadow(
                                          color: _quizDialogLeaf.withValues(
                                              alpha: 0.2),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : (canTapExplain && !hasExplainAccess)
                                        ? [
                                            BoxShadow(
                                              color: _quizDialogWarm.withValues(
                                                  alpha: 0.18),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap:
                                      canTapExplain ? _showExplanation : null,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      (_answerSelected &&
                                              !hasExplainAccess &&
                                              canOfferExplainAd)
                                          ? Image.asset(
                                              'assets/images/ads.png',
                                              width: 20,
                                              height: 20,
                                            )
                                          : Icon(
                                              Icons.lightbulb_outline_rounded,
                                              color: canTapExplain
                                                  ? _quizDialogCream
                                                  : _quizDialogTextSoft,
                                              size: 20,
                                            ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Coach Note',
                                        style: GoogleFonts.outfit(
                                          color: canTapExplain
                                              ? _quizDialogCream
                                              : _quizDialogTextSoft,
                                          fontWeight: FontWeight.bold,
                                          fontSize: r.fontSize(11),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _answerSelected ? () => _nextQuestion() : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _answerSelected
                                ? _quizDialogLeaf
                                : _quizDialogLeafSoft.withValues(alpha: 0.7),
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            disabledBackgroundColor:
                                _quizDialogLeafSoft.withValues(alpha: 0.7),
                          ),
                          icon: Icon(
                            currentIndex == widget.questions.length - 1
                                ? Icons.emoji_events_rounded
                                : Icons.arrow_forward_rounded,
                            color: _answerSelected
                                ? _quizDialogCream
                                : _quizDialogTextSoft,
                            size: r.size(18),
                          ),
                          label: Text(
                            currentIndex == widget.questions.length - 1
                                ? 'SHOW SCORE'
                                : 'NEXT',
                            style: GoogleFonts.outfit(
                              color: _answerSelected
                                  ? _quizDialogCream
                                  : _quizDialogTextSoft,
                              fontWeight: FontWeight.bold,
                              fontSize: r.fontSize(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Coach Note uses AI after you answer. Internet may be required.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: _quizDialogTextSoft,
                        fontSize: r.fontSize(10),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================
  // NAVIGATION & RESULTS
  // =========================
  Future<void> _menuPressed() async {
    if (_usesStrictTiming) {
      _showQuizSnackBar(
        'Strict timing session cannot be paused. Finish before exiting.',
        accent: _quizDialogWarm,
      );
      return;
    }

    final shouldPause = await _showPauseExitDialog();
    if (!shouldPause || !mounted) return;

    _timeController.stop();
    _quizStopwatch.stop();
    final elapsedSeconds =
        _elapsedOffsetSeconds + _quizStopwatch.elapsed.inSeconds;

    Navigator.pop(context, {
      'nextAction': 'pause',
      'resumeState': _buildResumeStatePayload(elapsedSeconds: elapsedSeconds),
      'mistakes': List<Map<String, dynamic>>.from(_mistakes),
    });
  }

  Future<void> _showEndQuizInterstitialIfNeeded() async {
    if (widget.hasUnlimitedAccess || widget.testMode == 'quickPractice') {
      return;
    }
    if (!_isInterstitialAdLoaded || _interstitialAd == null) {
      return;
    }

    final completer = Completer<void>();
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialAdLoaded = false;
        _loadInterstitialAd();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialAdLoaded = false;
        _loadInterstitialAd();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    _interstitialAd!.show();
    await completer.future;
  }

  Future<void> _nextQuestion() async {
    if (currentIndex < widget.questions.length - 1) {
      _timeController.stop();
      _timeController.value = 0.0;

      setState(() {
        currentIndex++;
        selectedChoiceIndex = null;
        _timeUp = false;
        _isLocked = false;
        _answerSelected = false;
        _explanationRequested = false;
        _explainAdUnlockedForCurrentQuestion = false;
      });

      // Update timer duration for the new question's category
      _timeController.duration = Duration(seconds: _currentMaxTime);

      // Reset animation state
      _choiceAnimationController.reset();
      _startTimer();
    } else {
      _timeController.stop();

      // Show interstitial first for free users; only show animated results after ad closes.
      await _showEndQuizInterstitialIfNeeded();
      if (!mounted) return;
      // Let route lifecycle settle after full-screen ad before mounting results dialog.
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      await _showResultsDialog();
    }
  }

  Future<void> _showResultsDialog() async {
    // Stop the stopwatch and capture elapsed time
    _quizStopwatch.stop();
    final elapsedSeconds =
        _elapsedOffsetSeconds + _quizStopwatch.elapsed.inSeconds;
    final assessment = _buildAssessment();
    final percentageValue = assessment.accuracyPercent;

    // Update leaderboard with today's score (removed â€” no more auth/leaderboard)

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return AnimatedResultsDialog(
          assessment: assessment,
          hasUnlimitedAccess: widget.hasUnlimitedAccess,
          testMode: widget.testMode,
          elapsedSeconds: elapsedSeconds,
          zeroAdSessionsRemaining: widget.zeroAdSessionsRemaining,
          onResultAction: (action) {
            Navigator.of(dialogContext).pop(action);
          },
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'playAgain') {
      Navigator.pop(
        context,
        _buildResultPayload(
          nextAction: 'playAgain',
          elapsedSeconds: elapsedSeconds,
          assessment: assessment,
        ),
      );
      return;
    }

    if (action == 'menu') {
      Navigator.pop(
        context,
        _buildResultPayload(
          nextAction: 'menu',
          elapsedSeconds: elapsedSeconds,
          assessment: assessment,
        ),
      );
      return;
    }

    // Check if we should show review prompt
    if (mounted && !widget.hasUnlimitedAccess) {
      final reviewService = ReviewService();
      final shouldShow = await reviewService.shouldShowReview(
        quizScore: percentageValue,
        hasUnlimitedAccess: false,
        hasGraceAccess: false,
      );

      if (shouldShow && mounted) {
        // Small delay to not interrupt results dialog transition
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await reviewService.requestReview();
        }
      }
    }
  }

  // OLD RESULTS DIALOG - Removed. Using AnimatedResultsDialog instead.
  // _showResultsDialog_REMOVED method removed - using AnimatedResultsDialog  // _resultItem removed - not used

  Future<void> _showExplainAdOfferDialog() async {
    if (!_canOfferExplainAdUnlock()) {
      _showQuizSnackBar(
        'Ad unlock limit reached for this quiz. Try again next quiz session.',
        accent: _quizDialogWarm,
      );
      return;
    }

    final remainingAdUnlocks =
        _maxExplainAdUnlocksForCurrentMode - _explainAdUnlockCount;
    final shouldWatch = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(_quizDialogPanel, _quizDialogWarmSoft, 0.18)!,
                _quizDialogPanel,
                Color.lerp(_quizDialogPanel, _quizDialogSkySoft, 0.22)!,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _quizDialogBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _quizDialogLeaf.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _quizDialogButterSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _quizDialogButter.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: _quizDialogButter,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Coach Note Limit Reached',
                      style: GoogleFonts.outfit(
                        color: _quizDialogText,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Watch an ad to unlock Coach Note for this question.',
                style: GoogleFonts.outfit(
                  color: _quizDialogText,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Coach Note gives optional AI-generated review guidance after you answer.',
                style: GoogleFonts.outfit(
                  color: _quizDialogTextSoft,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Coach Note ad unlocks left this quiz: $remainingAdUnlocks/$_maxExplainAdUnlocksForCurrentMode',
                style: GoogleFonts.outfit(
                  color: _quizDialogWarm,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _quizDialogBorder,
                        ),
                        foregroundColor: _quizDialogText,
                        backgroundColor: _quizDialogCream,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Not now',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _quizDialogLeaf,
                        foregroundColor: _quizDialogCream,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/ads.png',
                            width: 18,
                            height: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Coach Note',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

    if (shouldWatch != true || !mounted) return;

    final unlocked = await _showExplainInterstitialAd();
    if (!mounted) return;

    if (!unlocked) {
      _showQuizSnackBar(
        'Ad not available yet. Please try again in a moment.',
        accent: _quizDialogButter,
      );
      return;
    }

    setState(() {
      _explainAdUnlockedForCurrentQuestion = true;
      _explainAdUnlockCount++;
    });

    _openExplanationDialog(countAsFreeUsage: false);
  }

  Future<bool> _showExplainInterstitialAd() async {
    if (!_isExplainInterstitialAdLoaded || _explainInterstitialAd == null) {
      _loadExplainInterstitialAd();
      return false;
    }

    final completer = Completer<bool>();

    _explainInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _explainInterstitialAd = null;
        _isExplainInterstitialAdLoaded = false;
        _loadExplainInterstitialAd();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _explainInterstitialAd = null;
        _isExplainInterstitialAdLoaded = false;
        _loadExplainInterstitialAd();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _explainInterstitialAd!.show();

    return completer.future;
  }

  Future<void> _openExplanationDialog({required bool countAsFreeUsage}) async {
    final localExplanation = currentQuestion.explanation?.trim();
    final hasLocalExplanation =
        localExplanation != null && localExplanation.isNotEmpty;
    bool hasInternet = true;

    if (!hasLocalExplanation) {
      hasInternet = await _hasInternetConnection();
      if (!mounted) return;

      if (!hasInternet) {
        _showQuizSnackBar(
          'No internet connection. Coach Note is available offline only when the question already has a saved explanation.',
          accent: _quizDialogWarm,
          seconds: 3,
        );
        return;
      }
    } else {
      hasInternet = await _hasInternetConnection();
      if (!mounted) return;
    }

    setState(() {
      _explanationRequested = true;
      if (countAsFreeUsage && !widget.hasUnlimitedAccess) {
        explanationCount++;
      }
    });

    // Get user's selected answer text
    final userAnswerText = selectedChoiceIndex != null
        ? currentQuestion.choices[selectedChoiceIndex!]
        : 'No answer selected';

    // Get correct answer text
    final correctAnswerText = currentQuestion.choices[_correctIndex];

    // Check if user is correct
    final isCorrect = selectedChoiceIndex == _correctIndex;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => ExplanationDialog(
        initialExplanation: localExplanation,
        isStoredExplanation: hasLocalExplanation,
        onGenerate: () async {
          if (hasLocalExplanation) {
            return localExplanation;
          }

          final service = GeminiService(apiKey: GEMINI_API_KEY);
          return await service.getExplanation(
            question: currentQuestion.question,
            choices: currentQuestion.choices,
            userAnswer: userAnswerText,
            correctAnswer: correctAnswerText,
          );
        },
        userAnswer: userAnswerText,
        correctAnswer: correctAnswerText,
        isCorrect: isCorrect,
        hasUnlimitedAccess: widget.hasUnlimitedAccess,
        onReportContent: _reportContent,
        onUseBetterAI: (hasInternet && !_isVisualQuestion)
            ? () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context, rootNavigator: true);
                final hasInternet = await _hasInternetConnection();
                if (!mounted) return;

                if (!hasInternet) {
                  messenger.hideCurrentSnackBar();
                  _showQuizSnackBar(
                    'No internet connection. Coach Note requires internet access.',
                    accent: _quizDialogWarm,
                    seconds: 3,
                  );
                  return;
                }

                navigator.pop();

                // Get user's selected answer text
                final userAnswerText = selectedChoiceIndex != null
                    ? currentQuestion.choices[selectedChoiceIndex!]
                    : 'No answer selected';

                // Get correct answer text
                final correctAnswerText =
                    currentQuestion.choices[_correctIndex];

                // Check if user is correct
                final isCorrect = selectedChoiceIndex == _correctIndex;

                if (!mounted) return;

                await navigator.push(
                  DialogRoute<void>(
                    context: navigator.context,
                    barrierDismissible: false,
                    barrierColor: Colors.black87,
                    builder: (_) => BetterExplanationDialog(
                      onGenerate: () async {
                        final service = GptService(apiKey: GPT_API_KEY);
                        return await service.getBetterExplanation(
                          question: currentQuestion.question,
                          choices: currentQuestion.choices,
                          userAnswer: userAnswerText,
                          correctAnswer: correctAnswerText,
                        );
                      },
                      userAnswer: userAnswerText,
                      correctAnswer: correctAnswerText,
                      isCorrect: isCorrect,
                      onReportContent: _reportContent,
                    ),
                  ),
                );
              }
            : null,
      ),
    );
  }

  void _showExplanation() {
    _showExplanationWithConnectivityCheck();
  }

  Future<void> _showExplanationWithConnectivityCheck() async {
    final localExplanation = currentQuestion.explanation?.trim();
    final hasLocalExplanation =
        localExplanation != null && localExplanation.isNotEmpty;

    if (!widget.hasUnlimitedAccess && !_canUseExplainWhy()) {
      if (!_canOfferExplainAdUnlock()) {
        _showQuizSnackBar(
          'Ad unlock limit reached for this quiz. Try again next quiz session.',
          accent: _quizDialogWarm,
        );
        return;
      }

      if (hasLocalExplanation) {
        final hasInternet = await _hasInternetConnection();
        if (!mounted) return;

        if (!hasInternet) {
          _showQuizSnackBar(
            'Saved Coach Notes work offline, but ad unlocks for extra uses need internet access.',
            accent: _quizDialogWarm,
            seconds: 3,
          );
          return;
        }
      }

      _showExplainAdOfferDialog();
      return;
    }

    await _openExplanationDialog(
      countAsFreeUsage:
          !widget.hasUnlimitedAccess && !_explainAdUnlockedForCurrentQuestion,
    );
  }

  Future<bool> _hasInternetConnection() async {
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
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 && response.statusCode < 500) {
        return true;
      }
    } catch (_) {}

    return false;
  }
}

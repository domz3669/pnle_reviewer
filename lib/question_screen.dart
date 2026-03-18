import 'dart:math';
import 'dart:async';
import 'dart:io';
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
import 'models/question.dart';
import 'utils/responsive.dart';
import 'animated_results_dialog.dart';
import 'explanation_dialog.dart';
import 'better_explanation_dialog.dart';
import 'services/review_service.dart';
import 'services/gemini_service.dart';
import 'services/gpt_service.dart';

class QuestionScreen extends StatefulWidget {
  final List<Question> questions;
  final bool isPremium;
  final bool recordResults;
  final String testMode; // 'randomQuiz' or 'focusMode' or 'previous'
  final int zeroAdSessionsRemaining;

  const QuestionScreen({
    super.key,
    required this.questions,
    this.isPremium = false,
    this.recordResults = true,
    this.testMode = 'randomQuiz',
    this.zeroAdSessionsRemaining = 0,
  });

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
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

  // Track total time spent on the quiz
  final Stopwatch _quizStopwatch = Stopwatch();

  // Animation controllers for choice feedback
  late AnimationController _choiceAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shakeAnimation;

  // Banner Ad
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  // Interstitial Ad
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;

  // Rewarded Ad for explain-limit unlock
  RewardedAd? _explainRewardedAd;
  bool _isExplainRewardedAdLoaded = false;

  // =========================
  // ANSWER & SCORE HELPERS
  // =========================
  int get _correctIndex {
    return currentQuestion.answer.codeUnitAt(0) - 65;
  }

  final Map<String, int> _correctCount = {};

  final Map<String, int> _totalCount = {};

  // =========================
  // TIMER (Dynamic based on category)
  // =========================
  late AnimationController _timeController;

  int get _currentMaxTime => _getTimerForCategory(currentQuestion.category);

  /// Get timer duration based on question category
  int _getTimerForCategory(String category) {
    final isChallenge = widget.testMode == 'challenge';
    switch (category) {
      case 'Language Proficiency':
        return isChallenge ? 65 : 45;
      case 'Mathematics':
      case 'Science':
        return isChallenge ? 85 : 60;
      case 'Reading Comprehension':
        return isChallenge ? 95 : 70;
      default:
        return isChallenge ? 80 : 55;
    }
  }

  bool _timeUp = false;
  bool _isLocked = false;

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
    if (!widget.isPremium) {
      _loadBannerAd();
    }
    // Don't load interstitial ads for Quick Practice mode
    if (!widget.isPremium && widget.testMode != 'quickPractice') {
      _loadInterstitialAd();
    }
    if (!widget.isPremium) {
      _loadExplainRewardedAd();
    }
  }

  String _bannerAdUnitId({bool forceTestFallback = false}) {
    if (forceTestFallback && Platform.isIOS) return AdMobIds.iosBannerTest;
    return AdMobIds.banner;
  }

  String _interstitialAdUnitId({bool forceTestFallback = false}) {
    if (forceTestFallback && Platform.isIOS) {
      return AdMobIds.iosInterstitialTest;
    }
    return AdMobIds.interstitial;
  }

  String _explainRewardedAdUnitId({bool forceTestFallback = false}) {
    if (forceTestFallback && Platform.isIOS) return AdMobIds.iosRewardedTest;
    return AdMobIds.rewarded;
  }

  void _loadBannerAd({bool useTestFallback = false}) {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId(forceTestFallback: useTestFallback),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _isBannerAdLoaded = false;
          if (Platform.isIOS &&
              !AdMobIds.useTestAds &&
              !useTestFallback &&
              mounted) {
            debugPrint(
              'iOS banner ad failed (${error.code}: ${error.message}). Retrying with test banner ID fallback.',
            );
            _loadBannerAd(useTestFallback: true);
          }
        },
      ),
    )..load();
  }

  void _loadInterstitialAd({bool useTestFallback = false}) {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId(forceTestFallback: useTestFallback),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoaded = false;
          if (Platform.isIOS && !AdMobIds.useTestAds && !useTestFallback) {
            debugPrint(
              'iOS interstitial failed (${error.code}: ${error.message}). Retrying with test interstitial ID fallback.',
            );
            _loadInterstitialAd(useTestFallback: true);
          }
        },
      ),
    );
  }

  void _loadExplainRewardedAd({bool useTestFallback = false}) {
    RewardedAd.load(
      adUnitId: _explainRewardedAdUnitId(forceTestFallback: useTestFallback),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _explainRewardedAd = ad;
          _isExplainRewardedAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isExplainRewardedAdLoaded = false;
          if (Platform.isIOS && !AdMobIds.useTestAds && !useTestFallback) {
            debugPrint(
              'iOS rewarded failed (${error.code}: ${error.message}). Retrying with test rewarded ID fallback.',
            );
            _loadExplainRewardedAd(useTestFallback: true);
          }
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
    _explainRewardedAd?.dispose();
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
      _soundService.playWrongAnswer();
    }
  }

  Color _timeColorFromRatio(double ratio) {
    if (ratio > 0.6) return PnleTheme.success;
    if (ratio > 0.3) return PnleTheme.warning;
    return PnleTheme.danger;
  }

  Widget _animatedTimeBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _timeController,
          builder: (context, _) {
            final ratio = (1.0 - _timeController.value).clamp(0.03, 1.0);
            final isCritical = ratio <= 0.3;
            final barColor = _timeColorFromRatio(ratio);
            final barWidth = constraints.maxWidth * ratio;

            return Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
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
                            Colors.white.withValues(alpha: 0.18),
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
      return PnleTheme.danger.withValues(alpha: 0.25);
    }

    // When answer is selected, only highlight the user's choice
    if (_answerSelected && selectedChoiceIndex == index) {
      // Green if correct, red if wrong
      return index == _correctIndex
          ? PnleTheme.success.withValues(alpha: 0.25)
          : PnleTheme.danger.withValues(alpha: 0.25);
    }

    return Colors.white.withValues(alpha: 0.08);
  }

  LinearGradient? _choiceGradient(int index) {
    if (_timeUp) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PnleTheme.danger.withValues(alpha: 0.30),
          PnleTheme.danger.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.08),
        ],
      );
    }

    if (_answerSelected && selectedChoiceIndex == index) {
      final base =
          index == _correctIndex ? PnleTheme.success : PnleTheme.danger;
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          base.withValues(alpha: 0.30),
          base.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.08),
        ],
      );
    }

    return null;
  }

  Color _choiceBorderColor(int index) {
    if (_timeUp) return PnleTheme.danger;
    if (_answerSelected && selectedChoiceIndex == index) {
      return index == _correctIndex ? PnleTheme.success : PnleTheme.danger;
    }
    return Colors.white.withValues(alpha: 0.2);
  }

  Color _choiceTextColor(int index) {
    if (_timeUp) return Colors.white;
    if (_answerSelected && selectedChoiceIndex == index) return Colors.white;
    return Colors.white.withValues(alpha: 0.9);
  }

  // =========================
  // HELPER METHODS
  // =========================
  bool _canUseExplainWhy() {
    if (widget.isPremium) return true;
    if (_explainAdUnlockedForCurrentQuestion) return true;
    return explanationCount < _freeExplainLimit;
  }

  bool _canOfferExplainAdUnlock() {
    if (widget.isPremium) return false;
    if (_canUseExplainWhy()) return false;
    return _explainAdUnlockCount < _maxExplainAdUnlocks;
  }

  // =========================
  // REPORT CONTENT
  // =========================
  void _reportContent() async {
    final question = currentQuestion.question;

    // Try to send report via backend webhook
    bool sentSuccessfully = false;
    try {
      // Send to backend webhook to process and email
      final response = await http
          .post(
            Uri.parse('https://your-backend.com/api/report-question'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'question': question,
              'category': currentQuestion.category,
              'questionNumber': currentQuestion.number,
              'timestamp': DateTime.now().toIso8601String(),
              'userEmail':
                  'domingotambasacan@gmail.com', // TODO: Get from user auth
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        sentSuccessfully = true;
      }
    } catch (e) {
      debugPrint('Failed to send report via webhook: $e');
    }

    // Always store locally as backup
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = prefs.getStringList('pendingReports') ?? [];

      final reportEntry = {
        'question': question,
        'category': currentQuestion.category,
        'timestamp': DateTime.now().toIso8601String(),
        'questionNumber': currentQuestion.number,
        'synced': sentSuccessfully,
      };

      reports.add(jsonEncode(reportEntry));
      await prefs.setStringList('pendingReports', reports);
    } catch (e) {
      debugPrint('Error storing local report: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => AlertDialog(
        title: const Text('Report Submitted'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sentSuccessfully
                  ? '✓ Your report has been sent via email.'
                  : '✓ Your report has been recorded.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('Question reported:'),
            const SizedBox(height: 8),
            Text(
              question,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            Text(
              sentSuccessfully
                  ? 'Check your email at domingotambasacan@gmail.com for confirmation. Thank you!'
                  : 'Reports will be synced when you reconnect. Thank you for your feedback!',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
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
          decoration: const BoxDecoration(
            gradient: PnleTheme.appBackground,
          ),
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
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            currentQuestion.category,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
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
                          color: PnleTheme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: PnleTheme.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'Q${currentIndex + 1}/${widget.questions.length}${_sourceSuffixForCurrentQuestion()}',
                          style: GoogleFonts.outfit(
                            color: PnleTheme.accent,
                            fontSize: r.fontSize(12),
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
                            color: PnleTheme.danger.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: PnleTheme.danger.withValues(alpha: 0.45),
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
                                  color: PnleTheme.danger,
                                  fontWeight: FontWeight.w600,
                                  fontSize: r.fontSize(12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _menuPressed,
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.home_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // QUESTION BOX (Scrollable with max height)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.35,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          currentQuestion.question,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: currentQuestion.question.length > 300
                                ? r.fontSize(15)
                                : currentQuestion.question.length > 200
                                    ? r.fontSize(16)
                                    : r.fontSize(18),
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.4,
                          ),
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
                                        : null,
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

                  const SizedBox(height: 16),

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
                            flex: 2,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: (canTapExplain && hasExplainAccess)
                                    ? const LinearGradient(
                                        colors: [
                                          PnleTheme.success,
                                          Color(0xFF4CAF6F),
                                        ],
                                      )
                                    : (canTapExplain && !hasExplainAccess)
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFFF6AD55),
                                              Color(0xFFED8936),
                                            ],
                                          )
                                        : LinearGradient(
                                            colors: [
                                              Colors.white
                                                  .withValues(alpha: 0.12),
                                              Colors.white
                                                  .withValues(alpha: 0.06),
                                            ],
                                          ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: (canTapExplain && hasExplainAccess)
                                      ? PnleTheme.success.withValues(alpha: 0.6)
                                      : (canTapExplain && !hasExplainAccess)
                                          ? const Color(0xFFED8936)
                                              .withValues(alpha: 0.75)
                                          : Colors.white.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                                boxShadow: (canTapExplain && hasExplainAccess)
                                    ? [
                                        BoxShadow(
                                          color: PnleTheme.success
                                              .withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : (canTapExplain && !hasExplainAccess)
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFFED8936)
                                                  .withValues(alpha: 0.25),
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
                                                  ? PnleTheme.bgBottom
                                                  : Colors.white
                                                      .withValues(alpha: 0.4),
                                              size: 20,
                                            ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Explain',
                                        style: GoogleFonts.outfit(
                                          color: canTapExplain
                                              ? PnleTheme.bgBottom
                                              : Colors.white
                                                  .withValues(alpha: 0.4),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
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
                                ? PnleTheme.accent
                                : Colors.white.withValues(alpha: 0.15),
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.15),
                          ),
                          icon: Icon(
                            currentIndex == widget.questions.length - 1
                                ? Icons.emoji_events_rounded
                                : Icons.arrow_forward_rounded,
                            color: _answerSelected
                                ? PnleTheme.bgBottom
                                : Colors.white.withValues(alpha: 0.5),
                            size: r.size(18),
                          ),
                          label: Text(
                            'NEXT',
                            style: GoogleFonts.outfit(
                              color: _answerSelected
                                  ? PnleTheme.bgBottom
                                  : Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.bold,
                              fontSize: r.fontSize(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // BANNER AD
                  if (!widget.isPremium &&
                      _isBannerAdLoaded &&
                      _bannerAd != null)
                    Container(
                      alignment: Alignment.center,
                      width: _bannerAd!.size.width.toDouble(),
                      height: _bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: _bannerAd!),
                    ),

                  if (!widget.isPremium && _isBannerAdLoaded)
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
  void _menuPressed() {
    // Test cancelled, no recording - return to menu
    Navigator.pop(context);
  }

  Future<void> _showEndQuizInterstitialIfNeeded() async {
    if (widget.isPremium || widget.testMode == 'quickPractice') {
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
    final totalCorrect = _correctCount.values.fold(0, (sum, val) => sum + val);
    final totalQuestions = widget.questions.length;
    final percentageValue = (totalCorrect / totalQuestions) * 100;
    final isPerfect = percentageValue == 100.0;

    // Stop the stopwatch and capture elapsed time
    _quizStopwatch.stop();
    final elapsedSeconds = _quizStopwatch.elapsed.inSeconds;

    // Update leaderboard with today's score (removed — no more auth/leaderboard)

    final action = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return AnimatedResultsDialog(
          totalCorrect: totalCorrect,
          totalQuestions: totalQuestions,
          percentageValue: percentageValue,
          isPerfect: isPerfect,
          correctCount: _correctCount,
          totalCount: _totalCount,
          isPremium: widget.isPremium,
          testMode: widget.testMode,
          elapsedSeconds: elapsedSeconds,
          zeroAdSessionsRemaining: widget.zeroAdSessionsRemaining,
          onResultAction: (action) {
            Navigator.of(dialogContext, rootNavigator: true).pop(action);
          },
        );
      },
    );

    // Check if we should show review prompt
    if (mounted && !widget.isPremium) {
      final reviewService = ReviewService();
      final shouldShow = await reviewService.shouldShowReview(
        quizScore: percentageValue,
        isPremiumUser: false,
        isTrialActive: false,
      );

      if (shouldShow && mounted) {
        // Small delay to not interrupt results dialog transition
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await reviewService.requestReview();
        }
      }
    }

    // Handle the returned action:
    if (action == null) return;

    if (action == 'playAgain') {
      if (!mounted) return;
      if (widget.recordResults) {
        final results = {
          'correctCount': Map<String, int>.from(_correctCount),
          'totalCount': Map<String, int>.from(_totalCount),
          'nextAction': 'playAgain',
          'testMode': widget.testMode,
        };
        Navigator.pop(context, results);
      } else {
        Navigator.pop(context, 'playAgain');
      }
    } else if (action == 'menu') {
      if (!mounted) return;
      final results = {
        'correctCount': Map<String, int>.from(_correctCount),
        'totalCount': Map<String, int>.from(_totalCount),
        'nextAction': 'menu',
        'testMode': widget.testMode,
      };
      Navigator.pop(context, widget.recordResults ? results : 'menu');
    }
  }

  // OLD RESULTS DIALOG - Removed. Using AnimatedResultsDialog instead.
  // _showResultsDialog_REMOVED method removed - using AnimatedResultsDialog  // _resultItem removed - not used

  Future<void> _showExplainAdOfferDialog() async {
    if (!_canOfferExplainAdUnlock()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ad unlock limit reached for this quiz. Try again next quiz session.',
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final remainingAdUnlocks = _maxExplainAdUnlocks - _explainAdUnlockCount;
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
                PnleTheme.bgTop.withValues(alpha: 0.96),
                PnleTheme.bgBottom.withValues(alpha: 0.96),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
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
                      color: Colors.orange.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFFFC86A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Free Explain Limit Reached',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Watch an ad to unlock Explain Why for this question.',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ad unlocks left this quiz: $remainingAdUnlocks/$_maxExplainAdUnlocks',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
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
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                        backgroundColor: PnleTheme.accent,
                        foregroundColor: PnleTheme.bgBottom,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                            'Explain Why',
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

    final unlocked = await _showExplainRewardedAd();
    if (!mounted) return;

    if (!unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad not available yet. Please try again in a moment.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _explainAdUnlockedForCurrentQuestion = true;
      _explainAdUnlockCount++;
    });

    _openExplanationDialog(countAsFreeUsage: false);
  }

  Future<bool> _showExplainRewardedAd() async {
    if (!_isExplainRewardedAdLoaded || _explainRewardedAd == null) {
      _loadExplainRewardedAd();
      return false;
    }

    final completer = Completer<bool>();
    var rewardEarned = false;

    _explainRewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _explainRewardedAd = null;
        _isExplainRewardedAdLoaded = false;
        _loadExplainRewardedAd();
        if (!completer.isCompleted) completer.complete(rewardEarned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _explainRewardedAd = null;
        _isExplainRewardedAdLoaded = false;
        _loadExplainRewardedAd();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _explainRewardedAd!.show(
      onUserEarnedReward: (_, __) {
        rewardEarned = true;
      },
    );

    return completer.future;
  }

  void _openExplanationDialog({required bool countAsFreeUsage}) {
    setState(() {
      _explanationRequested = true;
      if (countAsFreeUsage && !widget.isPremium) {
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
        onGenerate: () async {
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
        isPremium: widget.isPremium,
        onReportContent: _reportContent,
        onUseBetterAI: () async {
          Navigator.pop(context);

          // Get user's selected answer text
          final userAnswerText = selectedChoiceIndex != null
              ? currentQuestion.choices[selectedChoiceIndex!]
              : 'No answer selected';

          // Get correct answer text
          final correctAnswerText = currentQuestion.choices[_correctIndex];

          // Check if user is correct
          final isCorrect = selectedChoiceIndex == _correctIndex;

          if (mounted) {
            showDialog(
              context: context,
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
            );
          }
        },
      ),
    );
  }

  void _showExplanation() {
    if (!widget.isPremium && !_canUseExplainWhy()) {
      if (!_canOfferExplainAdUnlock()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ad unlock limit reached for this quiz. Try again next quiz session.',
              style: GoogleFonts.outfit(),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      _showExplainAdOfferDialog();
      return;
    }

    _openExplanationDialog(
      countAsFreeUsage:
          !widget.isPremium && !_explainAdUnlockedForCurrentQuestion,
    );
  }
}

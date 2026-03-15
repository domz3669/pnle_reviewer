import 'dart:math';
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
import 'subscription_dialog.dart';
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
  bool _hasUsedExplainWhyInQuickPractice = false; // Track explain-why usage in quick practice
  int explanationCount = 0; // Track explanation requests per session

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
      _totalCount[q.category] =
          (_totalCount[q.category] ?? 0) + 1;
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
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdMobIds.banner,
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
        },
      ),
    )..load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdMobIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoaded = false;
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
            final ratio =
                (1.0 - _timeController.value).clamp(0.03, 1.0);
            final isCritical = ratio <= 0.3;
            final barColor = _timeColorFromRatio(ratio);
            final barWidth = constraints.maxWidth * ratio;

            return Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
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
                            barColor.withOpacity(0.95),
                            barColor.withOpacity(0.72),
                            Colors.white.withOpacity(0.18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isCritical
                            ? [
                                BoxShadow(
                                  color: barColor.withOpacity(0.7),
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
                                color: Colors.white.withOpacity(sparkleOpacity),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(sparkleOpacity * 0.6),
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
      return PnleTheme.danger.withOpacity(0.2);
    }
    
    // When answer is selected, only highlight the user's choice
    if (_answerSelected && selectedChoiceIndex == index) {
      // Green if correct, red if wrong
      return index == _correctIndex
          ? PnleTheme.success.withOpacity(0.25)
          : PnleTheme.danger.withOpacity(0.25);
    }
    
    return Colors.white.withOpacity(0.08);
  }

  LinearGradient? _choiceGradient(int index) {
    if (_timeUp) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PnleTheme.danger.withOpacity(0.22),
          PnleTheme.danger.withOpacity(0.14),
          Colors.white.withOpacity(0.08),
        ],
      );
    }

    if (_answerSelected && selectedChoiceIndex == index) {
      final base = index == _correctIndex ? PnleTheme.success : PnleTheme.danger;
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          base.withOpacity(0.30),
          base.withOpacity(0.20),
          Colors.white.withOpacity(0.08),
        ],
      );
    }

    return null;
  }

  Color _choiceBorderColor(int index) {
    if (_timeUp) return PnleTheme.danger.withOpacity(0.6);
    if (_answerSelected && selectedChoiceIndex == index) {
      return index == _correctIndex
          ? PnleTheme.success
          : PnleTheme.danger;
    }
    return Colors.white.withOpacity(0.2);
  }

  Color _choiceTextColor(int index) {
    if (_timeUp) return Colors.white;
    if (_answerSelected && selectedChoiceIndex == index) return Colors.white;
    return Colors.white.withOpacity(0.9);
  }

  // =========================
  // HELPER METHODS
  // =========================
  bool _canUseExplainWhy() {
    // In Quick Practice, free users can only use Explain Why once
    if (widget.testMode == 'quickPractice' && !widget.isPremium) {
      return !_hasUsedExplainWhyInQuickPractice;
    }
    // All other modes have unlimited explain why
    return true;
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
      final response = await http.post(
        Uri.parse('https://your-backend.com/api/report-question'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          'category': currentQuestion.category,
          'questionNumber': currentQuestion.number,
          'timestamp': DateTime.now().toIso8601String(),
          'userEmail': 'domingotambasacan@gmail.com', // TODO: Get from user auth
        }),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        sentSuccessfully = true;
      }
    } catch (e) {
      print('Failed to send report via webhook: $e');
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
      print('Error storing local report: $e');
    }
    
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

    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
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
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
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
                          color: PnleTheme.accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: PnleTheme.accent.withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          'Q${currentIndex + 1} / ${widget.questions.length}',
                          style: GoogleFonts.outfit(
                            color: PnleTheme.accent,
                            fontSize: r.fontSize(12),
                            fontWeight: FontWeight.bold,
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
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
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
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.95),
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
                                            (_correctCount[
                                                    currentQuestion
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
                                    _choiceAnimationController.forward(from: 0);
                                  },
                            child: AnimatedBuilder(
                              animation: _choiceAnimationController,
                              builder: (context, child) {
                                final isAnimating = _answerSelected && 
                                    selectedChoiceIndex == index && 
                                    _choiceAnimationController.isAnimating;
                                final isCorrect = index == _correctIndex;
                                
                                // Apply scale for correct, shake for wrong
                                Matrix4 transform;
                                if (isAnimating && isCorrect) {
                                  transform = Matrix4.identity()..scale(_scaleAnimation.value);
                                } else if (isAnimating && !isCorrect) {
                                  // Oscillate left-right: -10px, 10px, -10px, etc
                                  final shakeAmount = _shakeAnimation.value;
                                  final oscillation = (sin(shakeAmount * pi * 4) * 10);
                                  transform = Matrix4.identity()..translate(oscillation, 0.0, 0.0);
                                } else {
                                  transform = Matrix4.identity();
                                }

                                return Transform(
                                  transform: transform,
                                  alignment: Alignment.center,
                                  child: child,
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                constraints: const BoxConstraints(minHeight: 60),
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
                                boxShadow: _answerSelected && selectedChoiceIndex == index
                                    ? [
                                        BoxShadow(
                                          color: _choiceBorderColor(index).withOpacity(0.4),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.center,
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

                  // REPORT CONTENT & EXPLAIN WHY (Redesigned with icons)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Report Content Button
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                PnleTheme.danger.withOpacity(0.15),
                                PnleTheme.danger.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: PnleTheme.danger.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _reportContent,
                              borderRadius: BorderRadius.circular(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flag_outlined,
                                    color: PnleTheme.danger,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Report',
                                    style: GoogleFonts.outfit(
                                      color: PnleTheme.danger,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Explain Why Button
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: (_answerSelected && !_explanationRequested && _canUseExplainWhy())
                                ? const LinearGradient(
                                    colors: [
                                      PnleTheme.success,
                                      Color(0xFF4CAF6F),
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.12),
                                      Colors.white.withOpacity(0.06),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (_answerSelected && !_explanationRequested && _canUseExplainWhy())
                                  ? PnleTheme.success.withOpacity(0.6)
                                  : Colors.white.withOpacity(0.2),
                              width: 1.5,
                            ),
                            boxShadow: (_answerSelected && !_explanationRequested && _canUseExplainWhy())
                                ? [
                                    BoxShadow(
                                      color: PnleTheme.success.withOpacity(0.3),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: (_answerSelected && !_explanationRequested && _canUseExplainWhy())
                                  ? _showExplanation
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline_rounded,
                                    color: (_answerSelected && !_explanationRequested && _canUseExplainWhy())
                                        ? PnleTheme.bgBottom
                                        : Colors.white.withOpacity(0.4),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    (_answerSelected && !_canUseExplainWhy())
                                        ? 'Limit Reached'
                                        : 'Explain Why?',
                                    style: GoogleFonts.outfit(
                                      color: (_answerSelected && !_explanationRequested && _canUseExplainWhy())
                                          ? PnleTheme.bgBottom
                                          : Colors.white.withOpacity(0.4),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // BANNER AD
                  if (!widget.isPremium && _isBannerAdLoaded && _bannerAd != null)
                    Container(
                      alignment: Alignment.center,
                      width: _bannerAd!.size.width.toDouble(),
                      height: _bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: _bannerAd!),
                    ),

                  if (!widget.isPremium && _isBannerAdLoaded)
                    const SizedBox(height: 12),

                  // MENU & NEXT QUESTION / SHOW SCORE
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: ElevatedButton.icon(
                            onPressed: _menuPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.exit_to_app_rounded,
                              color: Colors.white.withOpacity(0.9),
                              size: 18,
                            ),
                            label: Text(
                              'MENU',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.bold,
                                fontSize: r.fontSize(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _answerSelected ? () => _nextQuestion() : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _answerSelected
                                  ? PnleTheme.accent
                                  : Colors.white.withOpacity(0.15),
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size.fromHeight(56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              disabledBackgroundColor:
                                  Colors.white.withOpacity(0.15),
                            ),
                            icon: Icon(
                              currentIndex == widget.questions.length - 1
                                  ? Icons.emoji_events_rounded
                                  : Icons.arrow_forward_rounded,
                              color: _answerSelected
                                  ? PnleTheme.bgBottom
                                  : Colors.white.withOpacity(0.5),
                              size: r.size(20),
                            ),
                            label: Text(
                              currentIndex == widget.questions.length - 1
                                  ? 'SHOW SCORE'
                                  : 'NEXT QUESTION',
                              style: GoogleFonts.outfit(
                                color: _answerSelected
                                    ? PnleTheme.bgBottom
                                    : Colors.white.withOpacity(0.5),
                                fontWeight: FontWeight.bold,
                                fontSize: r.fontSize(15),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  // =========================
  // NAVIGATION & RESULTS
  // =========================
  void _menuPressed() {
    // Test cancelled, no recording - return to menu
    Navigator.pop(context);
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
      });

      // Update timer duration for the new question's category
      _timeController.duration = Duration(seconds: _currentMaxTime);

      // Reset animation state
      _choiceAnimationController.reset();
      _startTimer();
    } else {
      _timeController.stop();
      await _showResultsDialog();
    }
  }

  Future<void> _showResultsDialog() async {
    final totalCorrect =
        _correctCount.values.fold(0, (sum, val) => sum + val);
    final totalQuestions = widget.questions.length;
    final percentageValue = (totalCorrect / totalQuestions) * 100;
    final isPerfect = percentageValue == 100.0;

    // Stop the stopwatch and capture elapsed time
    _quizStopwatch.stop();
    final elapsedSeconds = _quizStopwatch.elapsed.inSeconds;

    // Update leaderboard with today's score (removed — no more auth/leaderboard)

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) {
        return AnimatedResultsDialog(
          totalCorrect: totalCorrect,
          totalQuestions: totalQuestions,
          percentageValue: percentageValue,
          isPerfect: isPerfect,
          correctCount: _correctCount,
          totalCount: _totalCount,
          isPremium: widget.isPremium,
          isInterstitialAdLoaded: _isInterstitialAdLoaded,
          interstitialAd: _interstitialAd,
          testMode: widget.testMode,
          elapsedSeconds: elapsedSeconds,
          zeroAdSessionsRemaining: widget.zeroAdSessionsRemaining,
          onResultAction: (action) {
            Navigator.pop(context, action);
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
      };
      Navigator.pop(context, widget.recordResults ? results : 'menu');
    }
  }

  // OLD RESULTS DIALOG - Removed. Using AnimatedResultsDialog instead.
  // _showResultsDialog_REMOVED method removed - using AnimatedResultsDialog  // _resultItem removed - not used

  void _showExplanation() {
    // Check if free user has reached limit (5th explanation)
    if (!widget.isPremium && explanationCount >= 4) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => SubscriptionDialog(
          triggerSource: 'explain_limit',
          onStartTrial: () {
            Navigator.pop(context);
            // In a real app, this would activate trial in MenuScreen
            // For now, we'll just show a message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✓ 3-Day Free Trial Activated!'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          onClose: () => Navigator.pop(context),
        ),
      );
      return;
    }

    // Mark as requested and increment count
    setState(() {
      _explanationRequested = true;
      explanationCount++;
      // In Quick Practice, mark that free user has used explain why
      if (widget.testMode == 'quickPractice' && !widget.isPremium) {
        _hasUsedExplainWhyInQuickPractice = true;
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
          
          // Show interstitial ad for free users
          if (!widget.isPremium && _isInterstitialAdLoaded && _interstitialAd != null) {
            await _interstitialAd!.show();
            // Reload ad after showing
            _loadInterstitialAd();
          }
          
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
}


import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';
import 'services/sound_service.dart';

class AnimatedResultsDialog extends StatefulWidget {
  final int totalCorrect;
  final int totalQuestions;
  final double percentageValue;
  final bool isPerfect;
  final Map<String, int> correctCount;
  final Map<String, int> totalCount;
  final bool hasAdFreeAccess;
  final String? testMode;
  final int elapsedSeconds;
  final Function(String) onResultAction;
  final int zeroAdSessionsRemaining;

  const AnimatedResultsDialog({
    required this.totalCorrect,
    required this.totalQuestions,
    required this.percentageValue,
    required this.isPerfect,
    required this.correctCount,
    required this.totalCount,
    required this.hasAdFreeAccess,
    required this.testMode,
    this.elapsedSeconds = 0,
    required this.onResultAction,
    this.zeroAdSessionsRemaining = 0,
  });

  @override
  State<AnimatedResultsDialog> createState() => _AnimatedResultsDialogState();
}

class _AnimatedResultsDialogState extends State<AnimatedResultsDialog>
    with TickerProviderStateMixin {
  late AnimationController _percentageController;
  late AnimationController _progressController;
  late AnimationController _buttonGlowController;
  late Animation<double> _percentageAnimation;
  late Animation<double> _buttonGlowAnimation;
  final SoundService _soundService = SoundService();

  @override
  void initState() {
    super.initState();

    // Play ending sound on loop (pre-loaded, instant)
    _soundService.playEndingSoundLoop();

    _percentageController = AnimationController(
      duration: const Duration(milliseconds: 3500),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 3500),
      vsync: this,
    );

    _buttonGlowController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _percentageAnimation = Tween<double>(begin: 0, end: widget.percentageValue)
        .animate(CurvedAnimation(
            parent: _percentageController, curve: Curves.easeOutCubic));

    _buttonGlowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _buttonGlowController, curve: Curves.easeInOut));

    _percentageController.forward();
    _progressController.forward();
  }

  @override
  void dispose() {
    _soundService.stopEndingSound();
    _percentageController.dispose();
    _progressController.dispose();
    _buttonGlowController.dispose();
    super.dispose();
  }

  String _getPerformanceMessage(double score) {
    if (score >= 90) return "Outstanding! 🎉";
    if (score >= 70) return "Great job! 👍";
    if (score >= 50) return "Good effort! 📚";
    return "Keep practicing! 💪";
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Color _getPercentageColor(double score) {
    if (score >= 80) return PnleTheme.success;
    if (score >= 50) return PnleTheme.warning;
    return PnleTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [PnleTheme.bgTop, PnleTheme.bgBottom],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isPerfect) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text('✨', style: GoogleFonts.outfit(fontSize: 24)),
                    Text('🏆', style: GoogleFonts.outfit(fontSize: 24)),
                    Text('✨', style: GoogleFonts.outfit(fontSize: 24)),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              AnimatedBuilder(
                animation: _percentageAnimation,
                builder: (context, child) {
                  final displayPercentage =
                      _percentageAnimation.value.toStringAsFixed(1);
                  final color = _getPercentageColor(_percentageAnimation.value);
                  final scale = 0.95 + (_percentageAnimation.value / 100) * 0.1;

                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: color.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$displayPercentage%',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: color,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${widget.totalCorrect} / ${widget.totalQuestions} Correct',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getPerformanceMessage(_percentageAnimation.value),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.elapsedSeconds > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.timer_outlined,
                                    color: Colors.white54, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Time: ${_formatTime(widget.elapsedSeconds)}',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Category Breakdown',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...widget.correctCount.keys.map((category) {
                final correct = widget.correctCount[category] ?? 0;
                final total = widget.totalCount[category] ?? 1;
                if (total == 0) return const SizedBox.shrink();

                return AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, _) {
                    final animatedValue =
                        (correct / total) * _progressController.value;
                    final percentage =
                        ((correct / total) * 100).toStringAsFixed(0);

                    return _ResultCategoryItem(
                      category: category,
                      correct: correct,
                      total: total,
                      percentage: percentage,
                      animatedProgress: animatedValue,
                    );
                  },
                );
              }),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _soundService.stopEndingSound();
                        widget.onResultAction('menu');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.5),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.testMode == 'reviewMistakes'
                            ? 'HOME'
                            : 'QUIZ MENU',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _buttonGlowAnimation,
                      builder: (context, child) => Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: PnleTheme.accent.withOpacity(
                                  0.4 + (_buttonGlowAnimation.value * 0.3)),
                              blurRadius: 8 + (_buttonGlowAnimation.value * 8),
                              spreadRadius:
                                  1 + (_buttonGlowAnimation.value * 2),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          _soundService.stopEndingSound();
                          widget.onResultAction('playAgain');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PnleTheme.accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'PLAY AGAIN',
                          style: GoogleFonts.outfit(
                            color: PnleTheme.bgBottom,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
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
  }
}

class _ResultCategoryItem extends StatelessWidget {
  final String category;
  final int correct;
  final int total;
  final String percentage;
  final double animatedProgress;

  const _ResultCategoryItem({
    required this.category,
    required this.correct,
    required this.total,
    required this.percentage,
    required this.animatedProgress,
  });

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'Language Proficiency':
        return Icons.record_voice_over_rounded;
      case 'Reading Comprehension':
        return Icons.menu_book_rounded;
      case 'Mathematics':
        return Icons.calculate_rounded;
      case 'Science':
        return Icons.science_rounded;
      default:
        return Icons.edit_note_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      _getCategoryIcon(category),
                      size: 19,
                      color: Colors.white.withOpacity(0.95),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          height: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 68, maxWidth: 96),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$correct/$total ($percentage%)',
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
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: animatedProgress,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                correct == total
                    ? PnleTheme.success
                    : correct > total / 2
                        ? PnleTheme.warning
                        : PnleTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/acet_assessment.dart';
import 'services/sound_service.dart';

const _resultsCream = Color(0xFFEBF2FA);
const _resultsPanel = Color(0xFFE0ECF5);
const _resultsText = Color(0xFF2D5070);
const _resultsTextSoft = Color(0xFF6B8FA8);
const _resultsBorder = Color(0xA4A8C5D8);
const _resultsLeaf = Color(0xFF5B8DB8);
const _resultsLeafSoft = Color(0xFFC8DCE8);
const _resultsSkySoft = Color(0xFFE0EBF5);
const _resultsWarm = Color(0xFF8A7AA0);
const _resultsWarmSoft = Color(0xFFE4E0EE);
const _resultsButter = Color(0xFF5A7FA0);
const _resultsButterSoft = Color(0xFFDDEAF5);

class AnimatedResultsDialog extends StatefulWidget {
  final AcetAssessment assessment;
  final bool hasUnlimitedAccess;
  final String? testMode;
  final int elapsedSeconds;
  final Function(String) onResultAction;
  final int zeroAdSessionsRemaining;

  const AnimatedResultsDialog({
    super.key,
    required this.assessment,
    required this.hasUnlimitedAccess,
    required this.testMode,
    required this.elapsedSeconds,
    required this.onResultAction,
    this.zeroAdSessionsRemaining = 0,
  });

  @override
  State<AnimatedResultsDialog> createState() => _AnimatedResultsDialogState();
}

class _AnimatedResultsDialogState extends State<AnimatedResultsDialog>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _countController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _accuracyAnimation;
  final SoundService _soundService = SoundService();

  @override
  void initState() {
    super.initState();
    _soundService.playEndingSoundLoop();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _countController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _accuracyAnimation = Tween<double>(
      begin: 0,
      end: widget.assessment.accuracyPercent,
    ).animate(
      CurvedAnimation(parent: _countController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _countController.forward();
  }

  @override
  void dispose() {
    _soundService.stopEndingSound();
    _fadeController.dispose();
    _countController.dispose();
    super.dispose();
  }

  String _modeTitle() {
    switch (widget.testMode) {
      case 'focusMode':
        return 'PNLE Focus Results';
      case 'challenge':
        return 'PNLE Challenge Results';
      case 'timedExam':
        return 'PNLE Timed Results';
      case 'reviewMistakes':
        return 'PNLE Mistake Review';
      default:
        return 'PNLE Practice Results';
    }
  }

  String _modeTag() {
    switch (widget.testMode) {
      case 'focusMode':
        return 'FOCUS';
      case 'challenge':
        return 'CHALLENGE';
      case 'timedExam':
        return 'TIMED';
      case 'reviewMistakes':
        return 'REVIEW';
      default:
        return 'QUIZ';
    }
  }

  Color _readinessColor() {
    switch (widget.assessment.readinessLabel) {
      case 'PNLE Ready':
        return _resultsLeaf;
      case 'Competitive':
        return const Color(0xFF7293AE);
      case 'Developing':
        return _resultsButter;
      default:
        return _resultsWarm;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Strong':
        return _resultsLeaf;
      case 'Good':
        return const Color(0xFF7293AE);
      case 'Needs Speed':
      case 'Needs Accuracy':
        return _resultsButter;
      default:
        return _resultsWarm;
    }
  }

  Color _softAccent(Color accent) {
    if (accent == _resultsLeaf) return _resultsLeafSoft;
    if (accent == _resultsWarm) return _resultsWarmSoft;
    if (accent == _resultsButter) return _resultsButterSoft;
    return _resultsSkySoft;
  }

  String _formatTime(double seconds) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      final remainder = (seconds % 60).round();
      return '${minutes}m ${remainder}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
  }

  String _focusRecommendation() {
    final focus = widget.assessment.recommendedFocusCategory;
    if (focus.isEmpty) {
      return 'Build consistent timed repetition across all categories.';
    }
    return 'Recommended focus: $focus';
  }

  String _benchmarkBand() {
    final accuracy = widget.assessment.accuracyPercent;
    final avgTime = widget.assessment.averageTimePerQuestionSeconds;
    if (accuracy >= 84 && avgTime <= 40) {
      return 'Band A';
    }
    if (accuracy >= 74 && avgTime <= 50) {
      return 'Band B';
    }
    if (accuracy >= 64 && avgTime <= 60) {
      return 'Band C';
    }
    return 'Band D';
  }

  Color _benchmarkColor(String band) {
    switch (band) {
      case 'Band A':
        return _resultsLeaf;
      case 'Band B':
        return const Color(0xFF7293AE);
      case 'Band C':
        return _resultsButter;
      default:
        return _resultsWarm;
    }
  }

  String _nextDrillPlan() {
    final stats = _sortedCategoryStats();
    if (stats.isEmpty) {
      return 'Do one 10-question mixed drill, then review all mistakes before starting a new set.';
    }

    final weakest = stats.first;
    final secondWeakest = stats.length > 1 ? stats[1] : stats.first;
    return 'Next drill: run 8 questions in ${weakest.category} and 4 in ${secondWeakest.category}. Spend 2 minutes reviewing each miss before retrying the same category.';
  }

  List<AcetCategoryAssessment> _sortedCategoryStats() {
    final stats = widget.assessment.perCategoryStats.values.toList();
    stats.sort((a, b) {
      final accuracyCompare = a.accuracyPercent.compareTo(b.accuracyPercent);
      if (accuracyCompare != 0) return accuracyCompare;
      return b.averageTimePerQuestionSeconds
          .compareTo(a.averageTimePerQuestionSeconds);
    });
    return stats;
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: _resultsCream,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: accent, size: compact ? 17 : 18),
          SizedBox(height: compact ? 8 : 10),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _resultsTextSoft,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: _resultsText,
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _resultsCream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _softAccent(accent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: _resultsTextSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: _resultsText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedBucketChip({
    required String label,
    required int count,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 9 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: GoogleFonts.outfit(
              color: _resultsText,
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _resultsTextSoft,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile(
    AcetCategoryAssessment stat, {
    bool condensed = false,
  }) {
    final accent = _statusColor(stat.statusLabel);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _resultsCream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat.category,
                  style: GoogleFonts.outfit(
                    color: _resultsText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _softAccent(accent),
                      _softAccent(accent).withValues(alpha: 0.84),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  stat.statusLabel,
                  style: GoogleFonts.outfit(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                '${stat.correctAnswers}/${stat.totalQuestions} correct',
                style: GoogleFonts.outfit(
                  color: _resultsTextSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${stat.accuracyPercent.toStringAsFixed(1)}% accuracy',
                style: GoogleFonts.outfit(
                  color: _resultsTextSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!condensed)
                Text(
                  '${stat.averageTimePerQuestionSeconds.toStringAsFixed(1)}s avg',
                  style: GoogleFonts.outfit(
                    color: _resultsTextSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readinessColor = _readinessColor();
    final stats = _sortedCategoryStats();
    final compact = MediaQuery.of(context).size.width <= 380;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 880),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_resultsPanel, _resultsLeafSoft, 0.2)!,
                _resultsPanel,
                Color.lerp(_resultsPanel, _resultsSkySoft, 0.24)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: readinessColor.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: _resultsLeaf.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _softAccent(readinessColor),
                              _softAccent(readinessColor)
                                  .withValues(alpha: 0.86),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: readinessColor.withValues(alpha: 0.18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: readinessColor.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          _modeTag(),
                          style: GoogleFonts.outfit(
                            color: readinessColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _softAccent(readinessColor),
                              _softAccent(readinessColor)
                                  .withValues(alpha: 0.84),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: readinessColor.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          widget.assessment.readinessLabel,
                          style: GoogleFonts.outfit(
                            color: readinessColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _modeTitle(),
                    style: GoogleFonts.outfit(
                      color: _resultsText,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Session summary based on your latest PNLE practice.',
                    style: GoogleFonts.outfit(
                      color: _resultsTextSoft,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: readinessColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: readinessColor.withValues(alpha: 0.28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall Performance',
                          style: GoogleFonts.outfit(
                            color: _resultsText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: _accuracyAnimation,
                          builder: (context, _) {
                            return Text(
                              '${_accuracyAnimation.value.toStringAsFixed(1)}%',
                              style: GoogleFonts.outfit(
                                color: _resultsText,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.assessment.correctAnswers}/${widget.assessment.totalQuestions} correct',
                          style: GoogleFonts.outfit(
                            color: _resultsTextSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Column(
                          children: [
                            _compactSummaryTile(
                              icon: Icons.check_circle_outline_rounded,
                              label: 'Accuracy',
                              value:
                                  '${widget.assessment.accuracyPercent.toStringAsFixed(1)}%',
                              accent: _resultsLeaf,
                            ),
                            const SizedBox(height: 10),
                            _compactSummaryTile(
                              icon: Icons.timer_outlined,
                              label: 'Avg Time',
                              value: _formatTime(widget
                                  .assessment.averageTimePerQuestionSeconds),
                              accent: const Color(0xFF7293AE),
                            ),
                            const SizedBox(height: 10),
                            _compactSummaryTile(
                              icon: Icons.bolt_rounded,
                              label: 'Efficiency',
                              value: widget.assessment.efficiencyScore
                                  .toStringAsFixed(1),
                              accent: _resultsWarm,
                            ),
                            const SizedBox(height: 10),
                            _compactSummaryTile(
                              icon: Icons.flag_rounded,
                              label: 'Readiness',
                              value: widget.assessment.readinessLabel,
                              accent: readinessColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Benchmark Band + Session Time
                  Builder(builder: (_) {
                    final band = _benchmarkBand();
                    final bandColor = _benchmarkColor(band);
                    final totalMinutes = widget.elapsedSeconds ~/ 60;
                    final totalSecs = widget.elapsedSeconds % 60;
                    final timeStr = totalMinutes > 0
                        ? '${totalMinutes}m ${totalSecs}s'
                        : '${totalSecs}s';
                    return Row(
                      children: [
                        Expanded(
                          child: _compactSummaryTile(
                            icon: Icons.workspace_premium_rounded,
                            label: 'Benchmark',
                            value: band,
                            accent: bandColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _compactSummaryTile(
                            icon: Icons.schedule_rounded,
                            label: 'Session Time',
                            value: timeStr,
                            accent: const Color(0xFF7293AE),
                          ),
                        ),
                      ],
                    );
                  }),
                  // Speed Distribution
                  if (widget.assessment.totalQuestions > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _resultsCream,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _resultsBorder.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Answer Speed',
                            style: GoogleFonts.outfit(
                              color: _resultsText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _speedBucketChip(
                                  label: 'Fast',
                                  count: widget.assessment.fastAnswerCount,
                                  color: _resultsLeaf,
                                  compact: compact,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _speedBucketChip(
                                  label: 'Moderate',
                                  count: widget.assessment.moderateAnswerCount,
                                  color: _resultsButter,
                                  compact: compact,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _speedBucketChip(
                                  label: 'Slow',
                                  count: widget.assessment.slowAnswerCount,
                                  color: _resultsWarm,
                                  compact: compact,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Timed-out warning
                  if (widget.assessment.timedOutCount > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8B0B0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_off_rounded, color: Color(0xFFAA3344), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${widget.assessment.timedOutCount} question${widget.assessment.timedOutCount > 1 ? 's' : ''} timed out',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFAA3344),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Category Breakdown',
                    style: GoogleFonts.outfit(
                      color: _resultsText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...stats.map(
                    (stat) => _categoryTile(
                      stat,
                      condensed: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _resultsCream,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _resultsBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coach Feedback',
                          style: GoogleFonts.outfit(
                            color: _resultsText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.assessment.insightMessage,
                          style: GoogleFonts.outfit(
                            color: _resultsTextSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _focusRecommendation(),
                          style: GoogleFonts.outfit(
                            color: _resultsLeaf,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _nextDrillPlan(),
                          style: GoogleFonts.outfit(
                            color: _resultsText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  compact
                      ? Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => widget.onResultAction('menu'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: _resultsBorder),
                                  backgroundColor: _resultsCream,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  'Back To Menu',
                                  style: GoogleFonts.outfit(
                                    color: _resultsText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () =>
                                    widget.onResultAction('playAgain'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFF5E0),
                                  foregroundColor: const Color(0xFF3A2E00),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  side: const BorderSide(color: Color(0xFFE6C97A)),
                                ),
                                child: Text(
                                  'Play Again',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => widget.onResultAction('menu'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: _resultsBorder),
                                  backgroundColor: _resultsCream,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  'Back To Menu',
                                  style: GoogleFonts.outfit(
                                    color: _resultsText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    widget.onResultAction('playAgain'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFF5E0),
                                  foregroundColor: const Color(0xFF3A2E00),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  side: const BorderSide(color: Color(0xFFE6C97A)),
                                ),
                                child: Text(
                                  'Play Again',
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
        ),
      ),
    );
  }
}

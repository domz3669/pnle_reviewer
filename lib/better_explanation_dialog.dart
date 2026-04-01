import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';
import 'utils/responsive.dart';

const _deepCoachCream = Color(0xFFEBF2FA);
const _deepCoachPanel = Color(0xFFE0ECF5);
const _deepCoachText = Color(0xFF2D5070);
const _deepCoachTextSoft = Color(0xFF6B8FA8);
const _deepCoachBorder = Color(0xA4A8C5D8);
const _deepCoachLeaf = Color(0xFF5B8DB8);
const _deepCoachLeafSoft = Color(0xFFC8DCE8);
const _deepCoachSkySoft = Color(0xFFE0EBF5);
const _deepCoachWarm = Color(0xFF8A7AA0);
const _deepCoachWarmSoft = Color(0xFFE4E0EE);

class BetterExplanationDialog extends StatefulWidget {
  final Future<String> Function() onGenerate;
  final String userAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final VoidCallback onReportContent;

  const BetterExplanationDialog({
    super.key,
    required this.onGenerate,
    required this.userAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.onReportContent,
  });

  @override
  State<BetterExplanationDialog> createState() =>
      _BetterExplanationDialogState();
}

class _BetterExplanationDialogState extends State<BetterExplanationDialog>
    with TickerProviderStateMixin {
  int counter = 0;
  bool isGenerating = true;
  bool hasError = false;
  String? explanation;
  Timer? _timer;
  late AnimationController _correctAnswerAnimationController;
  late Animation<double> _correctAnswerScaleAnimation;

  @override
  void initState() {
    super.initState();
    _correctAnswerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _correctAnswerScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(
            parent: _correctAnswerAnimationController,
            curve: Curves.elasticOut));
    _correctAnswerAnimationController.forward();
    _startGeneration();
  }

  void _startGeneration() async {
    setState(() {
      counter = 0;
      isGenerating = true;
      hasError = false;
      explanation = null;
    });

    // Start counter (same speed as generation: 1 increment per second)
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && counter < 100 && isGenerating) {
        setState(() {
          counter++;
        });
      }
    });

    try {
      final result = await widget.onGenerate();

      if (!mounted) return;

      _timer?.cancel();

      setState(() {
        isGenerating = false;
        explanation = result;
        counter = 100;
      });
    } catch (e) {
      if (!mounted) return;

      _timer?.cancel();
      setState(() {
        isGenerating = false;
        hasError = true;
        counter = 100;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _correctAnswerAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: r.padding(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.lerp(_deepCoachPanel, _deepCoachLeafSoft, 0.22)!,
              _deepCoachPanel,
              Color.lerp(_deepCoachPanel, _deepCoachSkySoft, 0.24)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: _deepCoachBorder,
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: _deepCoachLeaf.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with title and close button
            if (!isGenerating && explanation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'AI Deep Coaching',
                          style: GoogleFonts.outfit(
                            fontSize: r.fontSize(22),
                            fontWeight: FontWeight.bold,
                            color: _deepCoachText,
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                            },
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _deepCoachCream,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _deepCoachBorder,
                                ),
                              ),
                              child: Icon(
                                Icons.close,
                                color: _deepCoachTextSoft,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      color: _deepCoachBorder,
                      height: 1,
                      thickness: 1,
                    ),
                  ],
                ),
              ),
            // Loading state
            if (isGenerating)
              Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _deepCoachLeaf,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Preparing deeper AI coaching notes...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: r.fontSize(16),
                        fontWeight: FontWeight.w600,
                        color: _deepCoachText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'These coaching notes are generated online and may vary by question.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: r.fontSize(13),
                        color: _deepCoachTextSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (explanation != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // User's wrong answer (only if incorrect)
                      if (!widget.isCorrect)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _deepCoachWarmSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _deepCoachWarm.withOpacity(0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.close,
                                    color: PnleTheme.danger,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Your Answer',
                                    style: GoogleFonts.outfit(
                                      fontSize: r.fontSize(13),
                                      fontWeight: FontWeight.w600,
                                      color: _deepCoachTextSoft,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.userAnswer,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  fontSize: r.fontSize(15),
                                  fontWeight: FontWeight.w600,
                                  color: _deepCoachWarm,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Correct answer
                      ScaleTransition(
                        scale: _correctAnswerScaleAnimation,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _deepCoachLeafSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _deepCoachLeaf.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: PnleTheme.success.withOpacity(0.9),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Correct Answer',
                                    style: GoogleFonts.outfit(
                                      fontSize: r.fontSize(13),
                                      fontWeight: FontWeight.w600,
                                      color: _deepCoachTextSoft,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.correctAnswer,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  fontSize: r.fontSize(15),
                                  fontWeight: FontWeight.w600,
                                  color: _deepCoachLeaf,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Explanation box (scrollable)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _deepCoachCream,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _deepCoachBorder,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Why is this correct?',
                              style: GoogleFonts.outfit(
                                fontSize: r.fontSize(13),
                                fontWeight: FontWeight.w600,
                                color: _deepCoachTextSoft,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              explanation!,
                              style: GoogleFonts.outfit(
                                fontSize: r.fontSize(14),
                                color: _deepCoachText,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Disclaimer
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7EFCF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFD9C59C),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info,
                                  color: const Color(0xFFB28D4B),
                                  size: 16,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Coaching notes are for review guidance. Please verify with trusted references.',
                                    style: GoogleFonts.outfit(
                                      fontSize: r.fontSize(12),
                                      color: _deepCoachTextSoft,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                widget.onReportContent();
                              },
                              child: Text(
                                'Report Inaccuracy',
                                style: GoogleFonts.outfit(
                                  fontSize: r.fontSize(12),
                                  fontWeight: FontWeight.w600,
                                  color: _deepCoachWarm,
                                  decoration: TextDecoration.underline,
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

            const SizedBox(height: 20),

            // Button (counter or CLOSE)
            if (isGenerating)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: _deepCoachCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _deepCoachBorder,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$counter%',
                  style: GoogleFonts.outfit(
                    color: _deepCoachText,
                    fontSize: r.fontSize(16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 14),
                    decoration: BoxDecoration(
                      color: _deepCoachCream,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _deepCoachBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'CLOSE',
                        style: GoogleFonts.outfit(
                          color: _deepCoachText,
                          fontSize: r.fontSize(16),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

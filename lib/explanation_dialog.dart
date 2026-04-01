import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';
import 'utils/responsive.dart';

const _coachCream = Color(0xFFEBF2FA);
const _coachPanel = Color(0xFFE0ECF5);
const _coachText = Color(0xFF2D5070);
const _coachTextSoft = Color(0xFF6B8FA8);
const _coachBorder = Color(0xA4A8C5D8);
const _coachLeaf = Color(0xFF5B8DB8);
const _coachLeafSoft = Color(0xFFC8DCE8);
const _coachSkySoft = Color(0xFFE0EBF5);
const _coachWarm = Color(0xFF8A7AA0);
const _coachWarmSoft = Color(0xFFE4E0EE);

class ExplanationDialog extends StatefulWidget {
  final Future<String> Function() onGenerate;
  final String? initialExplanation;
  final bool isStoredExplanation;
  final String userAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final bool hasUnlimitedAccess;
  final VoidCallback onReportContent;
  final VoidCallback? onUseBetterAI;

  const ExplanationDialog({
    super.key,
    required this.onGenerate,
    this.initialExplanation,
    this.isStoredExplanation = false,
    required this.userAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    this.hasUnlimitedAccess = false,
    required this.onReportContent,
    this.onUseBetterAI,
  });

  @override
  State<ExplanationDialog> createState() => _ExplanationDialogState();
}

class _ExplanationDialogState extends State<ExplanationDialog> {
  int counter = 0;
  bool isGenerating = true;
  bool hasError = false;
  String? explanation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final initialExplanation = widget.initialExplanation?.trim();
    if (initialExplanation != null && initialExplanation.isNotEmpty) {
      explanation = initialExplanation;
      isGenerating = false;
      counter = 100;
      return;
    }
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
              Color.lerp(_coachPanel, _coachLeafSoft, 0.24)!,
              _coachPanel,
              Color.lerp(_coachPanel, _coachSkySoft, 0.24)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: _coachBorder,
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: _coachLeaf.withOpacity(0.12),
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
                          'Explanation',
                          style: GoogleFonts.outfit(
                            fontSize: r.fontSize(22),
                            fontWeight: FontWeight.bold,
                            color: _coachText,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _coachCream,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _coachBorder,
                              ),
                            ),
                            child: Icon(
                              Icons.close,
                              color: _coachTextSoft,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      color: _coachBorder,
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
                        _coachLeaf,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Preparing your Coach Note...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: r.fontSize(16),
                        fontWeight: FontWeight.w600,
                        color: _coachText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This note is generated online when the question does not already include a saved explanation.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: r.fontSize(13),
                        color: _coachTextSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            // Content state
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
                            color: _coachWarmSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _coachWarm.withOpacity(0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.close,
                                    color: PnleTheme.warning.withOpacity(0.85),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Your Answer',
                                    style: GoogleFonts.outfit(
                                      fontSize: r.fontSize(13),
                                      fontWeight: FontWeight.w600,
                                      color: _coachTextSoft,
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
                                  color: _coachWarm,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Correct answer
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _coachLeafSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _coachLeaf.withOpacity(0.3),
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
                                    color: _coachTextSoft,
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
                                color: _coachLeaf,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Explanation box (scrollable)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _coachCream,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _coachBorder,
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
                                color: _coachTextSoft,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              explanation!,
                              style: GoogleFonts.outfit(
                                fontSize: r.fontSize(14),
                                color: _coachText,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

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
                                    widget.isStoredExplanation
                                        ? 'This Coach Note comes from the question\'s saved explanation. Please verify with trusted references.'
                                        : 'This Coach Note is generated online for review guidance. Please verify with trusted references.',
                                    style: GoogleFonts.outfit(
                                      fontSize: r.fontSize(12),
                                      color: _coachTextSoft,
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
                                  color: _coachWarm,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Not satisfied section
                      if (widget.onUseBetterAI != null) ...[
                        Text(
                          'Need a deeper breakdown?',
                          style: GoogleFonts.outfit(
                            color: _coachText,
                            fontSize: r.fontSize(14),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: widget.onUseBetterAI,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _coachLeaf,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: _coachCream,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'DEEPER COACHING',
                                style: GoogleFonts.outfit(
                                  color: _coachCream,
                                  fontWeight: FontWeight.bold,
                                  fontSize: r.fontSize(14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                  color: _coachCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _coachBorder,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$counter%',
                  style: GoogleFonts.outfit(
                    color: _coachText,
                    fontSize: r.fontSize(16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 14),
                    decoration: BoxDecoration(
                      color: _coachCream,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _coachBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'CLOSE',
                        style: GoogleFonts.outfit(
                          color: _coachText,
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';
import 'utils/responsive.dart';

class ExplanationDialog extends StatefulWidget {
  final Future<String> Function() onGenerate;
  final String userAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final bool hasAdFreeAccess;
  final VoidCallback onReportContent;
  final VoidCallback? onUseBetterAI;

  const ExplanationDialog({
    super.key,
    required this.onGenerate,
    required this.userAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    this.hasAdFreeAccess = false,
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
              PnleTheme.bgTop.withOpacity(0.95),
              PnleTheme.bgBottom.withOpacity(0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
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
                            color: Colors.white,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
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
                    const SizedBox(height: 16),
                    Divider(
                      color: Colors.white.withOpacity(0.2),
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
                        Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Preparing your AI coaching notes...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: r.fontSize(16),
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'These coaching notes are generated online and may vary by question.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: r.fontSize(13),
                        color: Colors.white.withOpacity(0.6),
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
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
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
                                      color: Colors.white.withOpacity(0.7),
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
                                  color: PnleTheme.warning.withOpacity(0.9),
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
                          color: PnleTheme.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: PnleTheme.success.withOpacity(0.3),
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
                                    color: Colors.white.withOpacity(0.7),
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
                                color: PnleTheme.success.withOpacity(0.9),
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
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
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
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              explanation!,
                              style: GoogleFonts.outfit(
                                fontSize: r.fontSize(14),
                                color: Colors.white.withOpacity(0.85),
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
                          color: PnleTheme.warning.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: PnleTheme.warning.withOpacity(0.2),
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
                                  color: PnleTheme.warning.withOpacity(0.7),
                                  size: 16,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Coaching notes are for review guidance. Please verify with trusted references.',
                                    style: GoogleFonts.outfit(
                                      fontSize: r.fontSize(12),
                                      color: Colors.white.withOpacity(0.6),
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
                                  color: PnleTheme.warning.withOpacity(0.75),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Not satisfied section
                      Text(
                        'Need a deeper breakdown?',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: r.fontSize(14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Enhanced explanation button
                      ElevatedButton(
                        onPressed: widget.onUseBetterAI,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PnleTheme.bgTop,
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
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'DEEPER COACHING',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: r.fontSize(14),
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
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$counter%',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.9),
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
                      color: PnleTheme.bgTop.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: PnleTheme.glowA.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'CLOSE',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
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

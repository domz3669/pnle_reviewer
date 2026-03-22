import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/sound_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';

class GeneratingTestDialog extends StatefulWidget {
  final Future<bool> Function() onGenerate;
  final Future<bool> Function()? onShowAd;
  final VoidCallback onStart;
  final VoidCallback? onSkip;
  final VoidCallback? onSuccess;
  final bool hasAdFreeAccess;
  final bool isFocusMode;
  final String? focusCategory;
  final String modeLabel;

  const GeneratingTestDialog({
    super.key,
    required this.onGenerate,
    this.onShowAd,
    required this.onStart,
    this.onSkip,
    this.onSuccess,
    this.hasAdFreeAccess = false,
    this.isFocusMode = false,
    this.focusCategory,
    this.modeLabel = 'RANDOM QUIZ',
  });

  @override
  State<GeneratingTestDialog> createState() => _GeneratingTestDialogState();
}

class _GeneratingTestDialogState extends State<GeneratingTestDialog>
    with TickerProviderStateMixin {
  static const Duration _cancelEnableDelay = Duration(seconds: 90);

  bool isGenerating = true;
  bool hasError = false;
  String? _errorMessage;
  bool _adAlreadyShown = false;
  bool _allowCancelDuringGeneration = false;
  Timer? _cancelEnableTimer;
  final SoundService _soundService = SoundService();
  late AnimationController _successAnimationController;

  Color get _accentColor =>
      widget.isFocusMode ? PnleTheme.glowA : PnleTheme.accent;

  @override
  void initState() {
    super.initState();

    _successAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _startGeneration();
  }

  void _startGeneration() async {
    _cancelEnableTimer?.cancel();
    setState(() {
      isGenerating = true;
      hasError = false;
      _errorMessage = null;
      _allowCancelDuringGeneration = false;
    });

    _cancelEnableTimer = Timer(_cancelEnableDelay, () {
      if (!mounted || !isGenerating || hasError) return;
      setState(() {
        _allowCancelDuringGeneration = true;
      });
    });

    try {
      // Run ad and generation simultaneously
      final results = await Future.wait([
        widget.onGenerate(),
        if (widget.onShowAd != null && !_adAlreadyShown)
          widget.onShowAd!().then((result) {
            _adAlreadyShown = true;
            return result;
          })
        else
          Future.value(true),
      ]);

      final success = results[0];
      final adSuccess = results[1];

      if (!mounted) return;

      if (success && adSuccess) {
        // Play success notification - multiple times for audibility
        _playSuccessNotification();

        setState(() {
          isGenerating = false;
          hasError = false;
        });

        // Animate success icon
        _successAnimationController.forward();

        if (widget.onSuccess != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onSuccess?.call();
          });
        }
      } else {
        setState(() {
          isGenerating = false;
          hasError = true;
          _errorMessage = !adSuccess
              ? 'Please finish watching the ad before starting the quiz.'
              : null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isGenerating = false;
        hasError = true;
        _errorMessage =
            'Unable to prepare your session right now. Please check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    _cancelEnableTimer?.cancel();
    _successAnimationController.dispose();

    super.dispose();
  }

  void _playSuccessNotification() {
    _soundService.playQuizReady();
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final canClose = hasError || !isGenerating || _allowCancelDuringGeneration;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(28),
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
                color: _accentColor.withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close Button (top right)
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: canClose
                        ? () {
                            // Show warning for free users if test is ready
                            if (!widget.hasAdFreeAccess &&
                                !hasError &&
                                !isGenerating) {
                              _showCloseWarning(context);
                            } else {
                              Navigator.pop(context);
                            }
                          }
                        : null,
                    icon: Icon(
                      Icons.close_rounded,
                      color: canClose
                          ? Colors.white.withOpacity(0.7)
                          : Colors.white.withOpacity(0.3),
                    ),
                    iconSize: 24,
                  ),
                ),

                // Mode Badge
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _accentColor.withOpacity(0.3),
                          _accentColor.withOpacity(0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _accentColor.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isFocusMode
                              ? Icons.gps_fixed
                              : Icons.shuffle_rounded,
                          color: _accentColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.modeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Animation with Progress Ring
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Single Progress Indicator
                    if (isGenerating)
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_accentColor),
                        ),
                      ),

                    // Themed Icon
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _accentColor.withOpacity(0.25),
                            _accentColor.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: _accentColor,
                        size: 56,
                      ),
                    ),

                    // Success/Error Icon Overlay
                    if (!isGenerating)
                      AnimatedBuilder(
                        animation: _successAnimationController,
                        builder: (context, child) {
                          final scaleValue = hasError
                              ? 1.0
                              : 1.0 +
                                  (Curves.elasticOut.transform(
                                          _successAnimationController.value) *
                                      0.3);
                          final pulseValue = hasError
                              ? 1.0
                              : 1.0 +
                                  (0.1 *
                                      (1 - _successAnimationController.value));

                          return Transform.scale(
                            scale: scaleValue,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: hasError
                                    ? Colors.red.withOpacity(0.9)
                                    : _accentColor.withOpacity(0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: hasError
                                        ? Colors.red.withOpacity(0.5)
                                        : _accentColor
                                            .withOpacity(0.5 * pulseValue),
                                    blurRadius: 25 * pulseValue,
                                    spreadRadius: 8 * pulseValue,
                                  ),
                                ],
                              ),
                              child: Icon(
                                hasError
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Status Text Container
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isGenerating) ...[
                        // Generating State
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: _accentColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Preparing your quiz...',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'This usually takes under a minute. Please keep the app open.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _allowCancelDuringGeneration
                              ? 'Still waiting? You can tap X to close this dialog.'
                              : 'If it gets stuck, the X button unlocks after 90 seconds.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ] else if (!hasError) ...[
                        // Success State
                        Icon(
                          Icons.celebration_rounded,
                          color: _accentColor,
                          size: 32,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Test Ready!',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your personalized test is ready',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _accentColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _accentColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tips_and_updates_rounded,
                                color: _accentColor,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.9),
                                      height: 1.4,
                                    ),
                                    children: const [
                                      TextSpan(
                                          text:
                                              'If the answer seems wrong, tap '),
                                      TextSpan(
                                        text: '"COACH NOTE"',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      TextSpan(text: ' after answering'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Error State
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade300,
                          size: 32,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Preparation Failed',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please check your connection and try again',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (hasError &&
                          _errorMessage != null &&
                          _errorMessage!.isNotEmpty)
                        Text(
                          _errorMessage!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.78),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action Button
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: hasError
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : isGenerating
                              ? [
                                  Colors.grey.shade600,
                                  Colors.grey.shade700,
                                ]
                              : [_accentColor, _accentColor.withOpacity(0.8)],
                    ),
                    boxShadow: !isGenerating
                        ? [
                            BoxShadow(
                              color: hasError
                                  ? Colors.red.withOpacity(0.4)
                                  : _accentColor.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: ElevatedButton(
                    onPressed: (hasError || !isGenerating)
                        ? () {
                            if (hasError) {
                              _startGeneration();
                            } else {
                              widget.onStart();
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      disabledBackgroundColor: Colors.transparent,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!isGenerating)
                          Icon(
                            hasError
                                ? Icons.refresh_rounded
                                : Icons.play_arrow_rounded,
                            color: hasError ? Colors.white : PnleTheme.bgBottom,
                            size: 24,
                          ),
                        if (!isGenerating) const SizedBox(width: 8),
                        Text(
                          hasError
                              ? 'RETRY'
                              : isGenerating
                                  ? 'PREPARING...'
                                  : 'START TEST',
                          style: GoogleFonts.outfit(
                            color: hasError
                                ? Colors.white
                                : isGenerating
                                    ? Colors.white.withOpacity(0.5)
                                    : PnleTheme.bgBottom,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
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

  void _showCloseWarning(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PnleTheme.bgTop.withOpacity(0.95),
                      PnleTheme.bgBottom.withOpacity(0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: PnleTheme.warning.withOpacity(0.6),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PnleTheme.warning.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: PnleTheme.warning,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Test Chance Used',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your test is ready! Closing now will waste 1 of your 4 daily chances. Are you sure you want to skip this test?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              widget.onSkip?.call();
                              Navigator.of(dialogContext, rootNavigator: true)
                                  .pop(); // Close warning
                              Navigator.of(context, rootNavigator: true)
                                  .pop(); // Close generation dialog
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                            ),
                            child: Text(
                              'Skip Test',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [
                                  PnleTheme.accent,
                                  PnleTheme.accentDeep
                                ],
                              ),
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(dialogContext, rootNavigator: true)
                                    .pop(); // Close warning
                                Navigator.of(context, rootNavigator: true)
                                    .pop(); // Close generation dialog
                                widget.onStart(); // Start the test immediately
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Take Test',
                                style: GoogleFonts.outfit(
                                  color: PnleTheme.bgBottom,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
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
          ),
        );
      },
    );
  }
}

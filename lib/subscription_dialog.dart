import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';

class SubscriptionDialog extends StatelessWidget {
  final VoidCallback onStartTrial;
  final VoidCallback onClose;
  final VoidCallback? onRestorePurchases;
  final String? triggerSource; // 'trial_offer', 'daily_limit', or 'explain_limit'

  const SubscriptionDialog({
    super.key,
    required this.onStartTrial,
    required this.onClose,
    this.onRestorePurchases,
    this.triggerSource,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  PnleTheme.bgTop.withOpacity(0.95),
                  PnleTheme.bgBottom.withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: PnleTheme.accent.withOpacity(0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: PnleTheme.accent.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Premium Crown Badge
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            PnleTheme.accent.withOpacity(0.3),
                            PnleTheme.accent.withOpacity(0.1),
                          ],
                        ),
                        border: Border.all(
                          color: PnleTheme.accent.withOpacity(0.6),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        size: 48,
                        color: PnleTheme.accent,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      'Unlock Premium',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Limited Time Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            PnleTheme.accent.withOpacity(0.3),
                            PnleTheme.accent.withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: PnleTheme.accent.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: PnleTheme.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '3-DAY FREE TRIAL',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: PnleTheme.accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Description
                    Text(
                      'Join thousands of students mastering UPCAT preparation',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Benefits List with Icons
                    ..._buildEnhancedBenefitsList(),

                    const SizedBox(height: 28),

                    // Pricing Box
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '₱',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '199',
                                style: GoogleFonts.outfit(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '/month',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'First 3 days FREE • Cancel anytime',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Start Trial Button
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            PnleTheme.accent,
                            PnleTheme.accentDeep,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: PnleTheme.accent.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: onStartTrial,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'START FREE TRIAL',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: PnleTheme.bgBottom,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: PnleTheme.bgBottom,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Trust Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: Colors.white.withOpacity(0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Secure payment • No card required for trial',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (onRestorePurchases != null)
                      TextButton(
                        onPressed: onRestorePurchases,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 20,
                          ),
                        ),
                        child: Text(
                          'Restore Purchases',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PnleTheme.accent,
                          ),
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Close Button
                    TextButton(
                      onPressed: onClose,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      ),
                      child: Text(
                        'Maybe Later',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.6),
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
    );
  }

  List<Widget> _buildEnhancedBenefitsList() {
    final benefits = [
      {
        'icon': Icons.block_rounded,
        'title': 'No More Ads',
        'subtitle': 'Uninterrupted study sessions',
      },
      {
        'icon': Icons.all_inclusive_rounded,
        'title': 'Up to 300 Questions Daily',
        'subtitle': '9,000 AI-generated questions/month',
      },
      {
        'icon': Icons.emoji_events_rounded,
        'title': 'Challenge Mode',
        'subtitle': 'Master harder, advanced questions',
      },
      {
        'icon': Icons.psychology_alt_rounded,
        'title': 'Unlimited AI Explanations',
        'subtitle': 'Understand every answer deeply',
      },
      {
        'icon': Icons.bar_chart_rounded,
        'title': '10-Day Performance Tracker',
        'subtitle': 'Track progress & identify weak areas',
      },
      {
        'icon': Icons.bookmark_rounded,
        'title': 'Save Up to 20 Exams',
        'subtitle': 'Review your best practice tests',
      },
    ];

    return benefits
        .map(
          (benefit) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        PnleTheme.accent.withOpacity(0.3),
                        PnleTheme.accent.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    benefit['icon'] as IconData,
                    color: PnleTheme.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        benefit['title'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        benefit['subtitle'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.check_circle,
                  color: const Color(0xFF4CAF50),
                  size: 20,
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}

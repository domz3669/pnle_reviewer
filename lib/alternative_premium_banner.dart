import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';

/// Alternative Premium Banner Widget
/// Displays a "PREMIUM" badge in the top-right corner
/// This is an optional design - currently using diagonal banner in menu_screen
class AlternativePremiumBanner extends StatelessWidget {
  final bool showPremiumBanner;

  const AlternativePremiumBanner({
    Key? key,
    required this.showPremiumBanner,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!showPremiumBanner) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFFD700),
              Color(0xFFFFC700),
            ],
          ),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              color: PnleTheme.bgBottom,
              size: 12,
            ),
            const SizedBox(width: 3),
            Text(
              'PREMIUM',
              style: GoogleFonts.outfit(
                color: PnleTheme.bgBottom,
                fontWeight: FontWeight.bold,
                fontSize: 9,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal badge variant (uncomment if preferred)
class MinimalPremiumBadge extends StatelessWidget {
  final bool showPremiumBanner;

  const MinimalPremiumBadge({
    Key? key,
    required this.showPremiumBanner,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!showPremiumBanner) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: PnleTheme.bgBottom.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          'PRO',
          style: GoogleFonts.outfit(
            color: PnleTheme.bgBottom,
            fontWeight: FontWeight.bold,
            fontSize: 9,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

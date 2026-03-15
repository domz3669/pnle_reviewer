import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  static final ReviewService _instance = ReviewService._internal();

  factory ReviewService() {
    return _instance;
  }

  ReviewService._internal();

  final InAppReview _inAppReview = InAppReview.instance;

  /// Check if app review should be shown based on conditions
  /// Returns true if should show, false otherwise
  Future<bool> shouldShowReview({
    required double quizScore,
    required bool isPremiumUser,
    required bool isTrialActive,
  }) async {
    // Don't show for premium or trial users
    if (isPremiumUser || isTrialActive) {
      return false;
    }

    // Only show if score is above 70%
    if (quizScore < 70) {
      return false;
    }

    // Check if already asked too recently
    final prefs = await SharedPreferences.getInstance();
    final lastReviewRequestTime = prefs.getString('lastReviewRequestTime');

    if (lastReviewRequestTime != null) {
      final lastRequest = DateTime.parse(lastReviewRequestTime);
      final now = DateTime.now();
      final daysSinceLastRequest = now.difference(lastRequest).inDays;

      // Don't ask again for at least 7 days
      if (daysSinceLastRequest < 7) {
        return false;
      }
    }

    return true;
  }

  /// Request app review and track the request
  Future<void> requestReview() async {
    try {
      // Check if review is available on this device
      if (await _inAppReview.isAvailable()) {
        // Show the native review dialog
        await _inAppReview.requestReview();

        // Track when review was requested
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'lastReviewRequestTime',
          DateTime.now().toIso8601String(),
        );
      }
    } catch (e) {
      print('Error requesting review: $e');
      // Silently fail - don't disrupt user experience
    }
  }

  /// Get days remaining until user can be asked again
  Future<int> daysUntilNextReviewAsk() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReviewRequestTime = prefs.getString('lastReviewRequestTime');

    if (lastReviewRequestTime == null) {
      return 0; // Can ask now
    }

    final lastRequest = DateTime.parse(lastReviewRequestTime);
    final now = DateTime.now();
    final daysSinceLastRequest = now.difference(lastRequest).inDays;
    final daysRemaining = 7 - daysSinceLastRequest;

    return daysRemaining > 0 ? daysRemaining : 0;
  }
}

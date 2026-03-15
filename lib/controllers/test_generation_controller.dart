import 'dart:async';

enum TestGenerationResult {
  success,
  failed,
}

class TestGenerationController {
  final bool isPremiumUser;

  TestGenerationController({
    required this.isPremiumUser,
  });

  /// Entry point called by UI
  Future<TestGenerationResult> startGeneration({
    required Future<bool> Function() showRewardedAd,
    required Future<bool> Function() generateTest,
  }) async {
    // PREMIUM: no ads, no limits
    if (isPremiumUser) {
      return await _attemptGeneration(generateTest);
    }

    // FREE: must pass ad gate first
    final adCompleted = await showRewardedAd();

    if (!adCompleted) {
      return TestGenerationResult.failed;
    }

    return await _attemptGeneration(generateTest);
  }

  /// Only place where generation is attempted
  Future<TestGenerationResult> _attemptGeneration(
    Future<bool> Function() generateTest,
  ) async {
    final success = await generateTest();

    if (success) {
      return TestGenerationResult.success;
    } else {
      return TestGenerationResult.failed;
    }
  }
}
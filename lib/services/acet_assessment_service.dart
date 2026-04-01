import '../models/acet_assessment.dart';

class AcetAssessmentService {
  const AcetAssessmentService();

  AcetAssessment mergeAssessments(List<AcetAssessment> assessments) {
    if (assessments.isEmpty) {
      return const AcetAssessment(
        totalQuestions: 0,
        correctAnswers: 0,
        wrongAnswers: 0,
        unansweredAnswers: 0,
        timedOutCount: 0,
        accuracyPercent: 0,
        averageTimePerQuestionSeconds: 0,
        efficiencyScore: 0,
        readinessLabel: 'Not Ready',
        fastAnswerCount: 0,
        moderateAnswerCount: 0,
        slowAnswerCount: 0,
        questionsPerMinute: 0,
        insightMessage: '',
        recommendedFocusCategory: '',
        perCategoryStats: <String, AcetCategoryAssessment>{},
      );
    }

    final totalQuestions =
        assessments.fold<int>(0, (sum, item) => sum + item.totalQuestions);
    final correctAnswers =
        assessments.fold<int>(0, (sum, item) => sum + item.correctAnswers);
    final wrongAnswers =
        assessments.fold<int>(0, (sum, item) => sum + item.wrongAnswers);
    final unansweredAnswers =
        assessments.fold<int>(0, (sum, item) => sum + item.unansweredAnswers);
    final timedOutCount =
        assessments.fold<int>(0, (sum, item) => sum + item.timedOutCount);
    final totalTimeSeconds = assessments.fold<double>(
      0,
      (sum, item) =>
          sum + (item.averageTimePerQuestionSeconds * item.totalQuestions),
    );

    final accuracyPercent =
        totalQuestions > 0 ? (correctAnswers / totalQuestions) * 100 : 0.0;
    final averageTimePerQuestionSeconds = totalQuestions > 0
        ? totalTimeSeconds / totalQuestions
        : 0.0;
    final speedFactor = (1.15 - ((averageTimePerQuestionSeconds - 10) * 0.02))
        .clamp(0.70, 1.05);
    final efficiencyScore = (accuracyPercent * speedFactor).clamp(0.0, 100.0);
    final questionsPerMinute = totalTimeSeconds > 0
        ? (totalQuestions * 60) / totalTimeSeconds
        : 0.0;

    final categoryKeys = <String>{};
    for (final assessment in assessments) {
      categoryKeys.addAll(assessment.perCategoryStats.keys);
    }

    final mergedCategoryStats = <String, AcetCategoryAssessment>{};
    for (final category in categoryKeys) {
      int categoryCorrect = 0;
      int categoryTotal = 0;
      double categoryTime = 0;

      for (final assessment in assessments) {
        final stat = assessment.perCategoryStats[category];
        if (stat == null) continue;
        categoryCorrect += stat.correctAnswers;
        categoryTotal += stat.totalQuestions;
        categoryTime +=
            stat.averageTimePerQuestionSeconds * stat.totalQuestions;
      }

      final categoryAccuracy =
          categoryTotal > 0 ? (categoryCorrect / categoryTotal) * 100 : 0.0;
      final categoryAverageTime =
          categoryTotal > 0 ? categoryTime / categoryTotal : 0.0;

      mergedCategoryStats[category] = AcetCategoryAssessment(
        category: category,
        correctAnswers: categoryCorrect,
        totalQuestions: categoryTotal,
        accuracyPercent: categoryAccuracy,
        averageTimePerQuestionSeconds: categoryAverageTime,
        statusLabel: categoryStatusLabel(
          accuracyPercent: categoryAccuracy,
          averageTimeSeconds: categoryAverageTime,
        ),
      );
    }

    final recommendedFocusCategory =
        _recommendedFocusCategory(mergedCategoryStats.values.toList());
    final readinessLabel = _readinessLabel(
      accuracyPercent: accuracyPercent,
      averageTimePerQuestionSeconds: averageTimePerQuestionSeconds,
      perCategoryStats: mergedCategoryStats,
    );
    final insightMessage = _insightMessage(
      accuracyPercent: accuracyPercent,
      averageTimePerQuestionSeconds: averageTimePerQuestionSeconds,
      efficiencyScore: efficiencyScore,
      timedOutCount: timedOutCount,
      fastAnswerCount:
          assessments.fold<int>(0, (sum, item) => sum + item.fastAnswerCount),
      slowAnswerCount:
          assessments.fold<int>(0, (sum, item) => sum + item.slowAnswerCount),
      recommendedFocusCategory: recommendedFocusCategory,
      perCategoryStats: mergedCategoryStats,
    );

    return AcetAssessment(
      totalQuestions: totalQuestions,
      correctAnswers: correctAnswers,
      wrongAnswers: wrongAnswers,
      unansweredAnswers: unansweredAnswers,
      timedOutCount: timedOutCount,
      accuracyPercent: accuracyPercent,
      averageTimePerQuestionSeconds: averageTimePerQuestionSeconds,
      efficiencyScore: efficiencyScore,
      readinessLabel: readinessLabel,
      fastAnswerCount:
          assessments.fold<int>(0, (sum, item) => sum + item.fastAnswerCount),
      moderateAnswerCount: assessments.fold<int>(
        0,
        (sum, item) => sum + item.moderateAnswerCount,
      ),
      slowAnswerCount:
          assessments.fold<int>(0, (sum, item) => sum + item.slowAnswerCount),
      questionsPerMinute: questionsPerMinute,
      insightMessage: insightMessage,
      recommendedFocusCategory: recommendedFocusCategory,
      perCategoryStats: mergedCategoryStats,
    );
  }

  AcetAssessment buildAssessment({
    required List<AcetQuestionAttempt> attempts,
    required Map<String, int> categoryTotals,
  }) {
    final totalQuestions = categoryTotals.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final correctAnswers = attempts.where((attempt) => attempt.isCorrect).length;
    final answeredQuestions = attempts.where((attempt) => attempt.answered).length;
    final wrongAnswers = attempts
        .where((attempt) => attempt.answered && !attempt.isCorrect)
        .length;
    final unansweredAnswers = (totalQuestions - answeredQuestions).clamp(0, totalQuestions);
    final timedOutCount = attempts.where((attempt) => attempt.timedOut).length;
    final totalTimeSeconds = attempts.fold<int>(
      0,
      (sum, attempt) => sum + attempt.timeSeconds,
    );

    final accuracyPercent =
        totalQuestions > 0 ? (correctAnswers / totalQuestions) * 100 : 0.0;
    final averageTimePerQuestionSeconds = totalQuestions > 0
        ? totalTimeSeconds / totalQuestions
        : 0.0;
    final questionsPerMinute = totalTimeSeconds > 0
        ? (totalQuestions * 60) / totalTimeSeconds
        : 0.0;

    final fastAnswerCount = attempts
        .where((attempt) => attempt.answered && attempt.timeSeconds <= 15)
        .length;
    final moderateAnswerCount = attempts
        .where(
          (attempt) =>
              attempt.answered &&
              attempt.timeSeconds >= 16 &&
              attempt.timeSeconds <= 25,
        )
        .length;
    final slowAnswerCount = attempts
        .where(
          (attempt) =>
              attempt.answered &&
              attempt.timeSeconds >= 26 &&
              attempt.timeSeconds <= 30,
        )
        .length;

    final speedFactor = (1.15 - ((averageTimePerQuestionSeconds - 10) * 0.02))
        .clamp(0.70, 1.05);
    final efficiencyScore = (accuracyPercent * speedFactor).clamp(0.0, 100.0);

    final perCategoryStats = _buildCategoryStats(
      attempts: attempts,
      categoryTotals: categoryTotals,
    );
    final recommendedFocusCategory =
        _recommendedFocusCategory(perCategoryStats.values.toList());
    final readinessLabel = _readinessLabel(
      accuracyPercent: accuracyPercent,
      averageTimePerQuestionSeconds: averageTimePerQuestionSeconds,
      perCategoryStats: perCategoryStats,
    );
    final insightMessage = _insightMessage(
      accuracyPercent: accuracyPercent,
      averageTimePerQuestionSeconds: averageTimePerQuestionSeconds,
      efficiencyScore: efficiencyScore,
      timedOutCount: timedOutCount,
      fastAnswerCount: fastAnswerCount,
      slowAnswerCount: slowAnswerCount,
      recommendedFocusCategory: recommendedFocusCategory,
      perCategoryStats: perCategoryStats,
    );

    return AcetAssessment(
      totalQuestions: totalQuestions,
      correctAnswers: correctAnswers,
      wrongAnswers: wrongAnswers,
      unansweredAnswers: unansweredAnswers,
      timedOutCount: timedOutCount,
      accuracyPercent: accuracyPercent,
      averageTimePerQuestionSeconds: averageTimePerQuestionSeconds,
      efficiencyScore: efficiencyScore,
      readinessLabel: readinessLabel,
      fastAnswerCount: fastAnswerCount,
      moderateAnswerCount: moderateAnswerCount,
      slowAnswerCount: slowAnswerCount,
      questionsPerMinute: questionsPerMinute,
      insightMessage: insightMessage,
      recommendedFocusCategory: recommendedFocusCategory,
      perCategoryStats: perCategoryStats,
    );
  }

  String categoryStatusLabel({
    required double accuracyPercent,
    required double averageTimeSeconds,
  }) {
    if (accuracyPercent >= 80 && averageTimeSeconds <= 20) {
      return 'Strong';
    }
    if (accuracyPercent >= 70 && averageTimeSeconds <= 25) {
      return 'Good';
    }
    if (accuracyPercent >= 70 && averageTimeSeconds > 25) {
      return 'Needs Speed';
    }
    if (accuracyPercent < 70 && averageTimeSeconds <= 25) {
      return 'Needs Accuracy';
    }
    return 'Weak';
  }

  Map<String, AcetCategoryAssessment> _buildCategoryStats({
    required List<AcetQuestionAttempt> attempts,
    required Map<String, int> categoryTotals,
  }) {
    final stats = <String, AcetCategoryAssessment>{};

    for (final entry in categoryTotals.entries) {
      final category = entry.key;
      final totalQuestions = entry.value;
      final categoryAttempts =
          attempts.where((attempt) => attempt.category == category).toList();
      final correctAnswers =
          categoryAttempts.where((attempt) => attempt.isCorrect).length;
      final totalTimeSeconds = categoryAttempts.fold<int>(
        0,
        (sum, attempt) => sum + attempt.timeSeconds,
      );
      final accuracyPercent = totalQuestions > 0
          ? (correctAnswers / totalQuestions) * 100
          : 0.0;
      final averageTimeSeconds = totalQuestions > 0
          ? totalTimeSeconds / totalQuestions
          : 0.0;

      stats[category] = AcetCategoryAssessment(
        category: category,
        correctAnswers: correctAnswers,
        totalQuestions: totalQuestions,
        accuracyPercent: accuracyPercent,
        averageTimePerQuestionSeconds: averageTimeSeconds,
        statusLabel: categoryStatusLabel(
          accuracyPercent: accuracyPercent,
          averageTimeSeconds: averageTimeSeconds,
        ),
      );
    }

    return stats;
  }

  String _readinessLabel({
    required double accuracyPercent,
    required double averageTimePerQuestionSeconds,
    Map<String, AcetCategoryAssessment>? perCategoryStats,
  }) {
    // PNLE dual-threshold: 75% general average AND no subject below 60%
    final hasSubjectBelow60 = perCategoryStats != null &&
        perCategoryStats.values.any(
          (stat) => stat.totalQuestions > 0 && stat.accuracyPercent < 60,
        );

    if (accuracyPercent >= 75 && !hasSubjectBelow60) {
      return 'PNLE Ready';
    }
    if (accuracyPercent >= 70 && !hasSubjectBelow60) {
      return 'Competitive';
    }
    if (accuracyPercent >= 60) {
      return 'Developing';
    }
    return 'Not Ready';
  }

  String _recommendedFocusCategory(
    List<AcetCategoryAssessment> categories,
  ) {
    if (categories.isEmpty) return '';

    final sorted = List<AcetCategoryAssessment>.from(categories)
      ..sort((a, b) {
        final accuracyCompare =
            a.accuracyPercent.compareTo(b.accuracyPercent);
        if (accuracyCompare != 0) return accuracyCompare;
        return b.averageTimePerQuestionSeconds
            .compareTo(a.averageTimePerQuestionSeconds);
      });

    return sorted.first.category;
  }

  String _insightMessage({
    required double accuracyPercent,
    required double averageTimePerQuestionSeconds,
    required double efficiencyScore,
    required int timedOutCount,
    required int fastAnswerCount,
    required int slowAnswerCount,
    required String recommendedFocusCategory,
    required Map<String, AcetCategoryAssessment> perCategoryStats,
  }) {
    if (accuracyPercent >= 75 && averageTimePerQuestionSeconds > 25) {
      return 'You are accurate, but building speed will boost your efficiency score.';
    }
    if (accuracyPercent < 70 && fastAnswerCount > slowAnswerCount) {
      return 'You are fast, but careless mistakes are lowering your score.';
    }
    if (accuracyPercent >= 70 && averageTimePerQuestionSeconds <= 25) {
      return 'Your performance is balanced and competitive.';
    }

    final focusStat = perCategoryStats[recommendedFocusCategory];
    if (focusStat != null) {
      if (focusStat.averageTimePerQuestionSeconds > 25 &&
          focusStat.accuracyPercent >= 70) {
        return '${focusStat.category} is slowing you down. Practice under tighter time pressure.';
      }
      return 'Focus on both speed and accuracy, especially in ${focusStat.category}.';
    }

    if (timedOutCount >= 2 || efficiencyScore < 55) {
      return 'Focus on both speed and accuracy under time pressure.';
    }

    return 'Keep building speed and control together to stay competitive.';
  }
}

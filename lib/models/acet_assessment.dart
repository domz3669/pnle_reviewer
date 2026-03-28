class AcetQuestionAttempt {
  final int questionNumber;
  final String category;
  final int timeSeconds;
  final bool isCorrect;
  final bool answered;
  final bool timedOut;

  const AcetQuestionAttempt({
    required this.questionNumber,
    required this.category,
    required this.timeSeconds,
    required this.isCorrect,
    required this.answered,
    required this.timedOut,
  });

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'category': category,
        'timeSeconds': timeSeconds,
        'isCorrect': isCorrect,
        'answered': answered,
        'timedOut': timedOut,
      };

  factory AcetQuestionAttempt.fromJson(Map<String, dynamic> json) {
    return AcetQuestionAttempt(
      questionNumber: (json['questionNumber'] as num?)?.toInt() ?? 0,
      category: (json['category'] as String?) ?? '',
      timeSeconds: (json['timeSeconds'] as num?)?.toInt() ?? 0,
      isCorrect: json['isCorrect'] == true,
      answered: json['answered'] == true,
      timedOut: json['timedOut'] == true,
    );
  }
}

class AcetCategoryAssessment {
  final String category;
  final int correctAnswers;
  final int totalQuestions;
  final double accuracyPercent;
  final double averageTimePerQuestionSeconds;
  final String statusLabel;

  const AcetCategoryAssessment({
    required this.category,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.accuracyPercent,
    required this.averageTimePerQuestionSeconds,
    required this.statusLabel,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
        'accuracyPercent': accuracyPercent,
        'averageTimePerQuestionSeconds': averageTimePerQuestionSeconds,
        'statusLabel': statusLabel,
      };

  factory AcetCategoryAssessment.fromJson(Map<String, dynamic> json) {
    return AcetCategoryAssessment(
      category: (json['category'] as String?) ?? '',
      correctAnswers: (json['correctAnswers'] as num?)?.toInt() ?? 0,
      totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 0,
      accuracyPercent: (json['accuracyPercent'] as num?)?.toDouble() ?? 0,
      averageTimePerQuestionSeconds:
          (json['averageTimePerQuestionSeconds'] as num?)?.toDouble() ?? 0,
      statusLabel: (json['statusLabel'] as String?) ?? 'Weak',
    );
  }
}

class AcetAssessment {
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;
  final int unansweredAnswers;
  final int timedOutCount;
  final double accuracyPercent;
  final double averageTimePerQuestionSeconds;
  final double efficiencyScore;
  final String readinessLabel;
  final int fastAnswerCount;
  final int moderateAnswerCount;
  final int slowAnswerCount;
  final double questionsPerMinute;
  final String insightMessage;
  final String recommendedFocusCategory;
  final Map<String, AcetCategoryAssessment> perCategoryStats;

  const AcetAssessment({
    required this.totalQuestions,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.unansweredAnswers,
    required this.timedOutCount,
    required this.accuracyPercent,
    required this.averageTimePerQuestionSeconds,
    required this.efficiencyScore,
    required this.readinessLabel,
    required this.fastAnswerCount,
    required this.moderateAnswerCount,
    required this.slowAnswerCount,
    required this.questionsPerMinute,
    required this.insightMessage,
    required this.recommendedFocusCategory,
    required this.perCategoryStats,
  });

  Map<String, dynamic> toJson() => {
        'totalQuestions': totalQuestions,
        'correctAnswers': correctAnswers,
        'wrongAnswers': wrongAnswers,
        'unansweredAnswers': unansweredAnswers,
        'timedOutCount': timedOutCount,
        'accuracyPercent': accuracyPercent,
        'averageTimePerQuestionSeconds': averageTimePerQuestionSeconds,
        'efficiencyScore': efficiencyScore,
        'readinessLabel': readinessLabel,
        'fastAnswerCount': fastAnswerCount,
        'moderateAnswerCount': moderateAnswerCount,
        'slowAnswerCount': slowAnswerCount,
        'questionsPerMinute': questionsPerMinute,
        'insightMessage': insightMessage,
        'recommendedFocusCategory': recommendedFocusCategory,
        'perCategoryStats': perCategoryStats.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };

  factory AcetAssessment.fromJson(Map<String, dynamic> json) {
    final rawCategoryStats = json['perCategoryStats'];
    final categoryStats = <String, AcetCategoryAssessment>{};
    if (rawCategoryStats is Map) {
      for (final entry in rawCategoryStats.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is Map<String, dynamic>) {
          categoryStats[key] = AcetCategoryAssessment.fromJson(value);
        } else if (key is String && value is Map) {
          categoryStats[key] =
              AcetCategoryAssessment.fromJson(Map<String, dynamic>.from(value));
        }
      }
    }

    return AcetAssessment(
      totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 0,
      correctAnswers: (json['correctAnswers'] as num?)?.toInt() ?? 0,
      wrongAnswers: (json['wrongAnswers'] as num?)?.toInt() ?? 0,
      unansweredAnswers: (json['unansweredAnswers'] as num?)?.toInt() ?? 0,
      timedOutCount: (json['timedOutCount'] as num?)?.toInt() ?? 0,
      accuracyPercent: (json['accuracyPercent'] as num?)?.toDouble() ?? 0,
      averageTimePerQuestionSeconds:
          (json['averageTimePerQuestionSeconds'] as num?)?.toDouble() ?? 0,
      efficiencyScore: (json['efficiencyScore'] as num?)?.toDouble() ?? 0,
      readinessLabel: (json['readinessLabel'] as String?) ?? 'Not Ready',
      fastAnswerCount: (json['fastAnswerCount'] as num?)?.toInt() ?? 0,
      moderateAnswerCount: (json['moderateAnswerCount'] as num?)?.toInt() ?? 0,
      slowAnswerCount: (json['slowAnswerCount'] as num?)?.toInt() ?? 0,
      questionsPerMinute: (json['questionsPerMinute'] as num?)?.toDouble() ?? 0,
      insightMessage: (json['insightMessage'] as String?) ?? '',
      recommendedFocusCategory:
          (json['recommendedFocusCategory'] as String?) ?? '',
      perCategoryStats: categoryStats,
    );
  }
}

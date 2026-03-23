class QuizModeConfig {
  final String modeId;
  final int questionCount;
  final int? timePerQuestionSeconds;
  final bool? autoNextOnTimeout;
  final bool usesMixedCategories;
  final bool usesSingleCategory;

  const QuizModeConfig({
    required this.modeId,
    required this.questionCount,
    this.timePerQuestionSeconds,
    this.autoNextOnTimeout,
    this.usesMixedCategories = false,
    this.usesSingleCategory = false,
  });

  factory QuizModeConfig.fromJson(String modeId, Map<String, dynamic> json) {
    return QuizModeConfig(
      modeId: modeId,
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 15,
      timePerQuestionSeconds:
          (json['timePerQuestionSeconds'] as num?)?.toInt(),
      autoNextOnTimeout: json['autoNextOnTimeout'] as bool?,
      usesMixedCategories: json['usesMixedCategories'] as bool? ?? false,
      usesSingleCategory: json['usesSingleCategory'] as bool? ?? false,
    );
  }
}

class ExamConfig {
  final String examId;
  final String appTitle;
  final String language;
  final List<String> categories;
  final Map<String, QuizModeConfig> modes;
  final int dailySessionTarget;
  final int savedTestsLimit;

  const ExamConfig({
    required this.examId,
    required this.appTitle,
    required this.language,
    required this.categories,
    required this.modes,
    required this.dailySessionTarget,
    required this.savedTestsLimit,
  });

  factory ExamConfig.fromJson(String examId, Map<String, dynamic> json) {
    final rawModes =
        (json['modes'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

    final parsedModes = <String, QuizModeConfig>{};
    for (final entry in rawModes.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        parsedModes[entry.key] = QuizModeConfig.fromJson(entry.key, value);
      } else if (value is Map) {
        parsedModes[entry.key] = QuizModeConfig.fromJson(
          entry.key,
          value.cast<String, dynamic>(),
        );
      }
    }

    final categories = <String>[];
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is String && item.trim().isNotEmpty) {
          categories.add(item.trim());
        }
      }
    }

    return ExamConfig(
      examId: examId,
      appTitle: (json['appTitle'] as String?)?.trim() ?? examId,
      language: (json['language'] as String?)?.trim() ?? 'English',
      categories: categories,
      modes: parsedModes,
      dailySessionTarget: (json['dailySessionTarget'] as num?)?.toInt() ?? 4,
      savedTestsLimit: (json['savedTestsLimit'] as num?)?.toInt() ?? 30,
    );
  }

  QuizModeConfig? mode(String modeId) => modes[modeId];
}

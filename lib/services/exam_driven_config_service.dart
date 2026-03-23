import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/exam_config.dart';
import '../models/prompt_config.dart';

class ExamDrivenConfigService {
  ExamDrivenConfigService._();

  static final ExamDrivenConfigService instance = ExamDrivenConfigService._();

  static const String _promptsAssetPath = 'assets/config/prompts.json';
  static const String _examConfigAssetPath = 'assets/config/exam_config.json';

  bool _loaded = false;
  String _defaultExamId = 'ustet';
  final Map<String, PromptConfig> _promptByExam = {};
  final Map<String, ExamConfig> _examById = {};

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    try {
      final promptsRaw = await rootBundle.loadString(_promptsAssetPath);
      final decodedPrompts = jsonDecode(promptsRaw);
      if (decodedPrompts is Map<String, dynamic>) {
        final defaultExam = decodedPrompts['defaultExamId'];
        if (defaultExam is String && defaultExam.trim().isNotEmpty) {
          _defaultExamId = defaultExam.trim();
        }

        final exams =
            (decodedPrompts['exams'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        for (final entry in exams.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _promptByExam[entry.key] = PromptConfig.fromJson(entry.key, value);
          } else if (value is Map) {
            _promptByExam[entry.key] =
                PromptConfig.fromJson(entry.key, value.cast<String, dynamic>());
          }
        }
      }
    } catch (e) {
      debugPrint('Config load warning ($_promptsAssetPath): $e');
    }

    try {
      final examRaw = await rootBundle.loadString(_examConfigAssetPath);
      final decodedExam = jsonDecode(examRaw);
      if (decodedExam is Map<String, dynamic>) {
        final defaultExam = decodedExam['defaultExamId'];
        if (defaultExam is String && defaultExam.trim().isNotEmpty) {
          _defaultExamId = defaultExam.trim();
        }

        final exams =
            (decodedExam['exams'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        for (final entry in exams.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _examById[entry.key] = ExamConfig.fromJson(entry.key, value);
          } else if (value is Map) {
            _examById[entry.key] =
                ExamConfig.fromJson(entry.key, value.cast<String, dynamic>());
          }
        }
      }
    } catch (e) {
      debugPrint('Config load warning ($_examConfigAssetPath): $e');
    }

    _loaded = true;
  }

  String get defaultExamId => _defaultExamId;

  ExamConfig? getExamConfig(String examId) {
    return _examById[examId] ?? _examById[_defaultExamId];
  }

  QuizModeConfig? getModeConfig(String examId, String mode) {
    return getExamConfig(examId)?.mode(mode);
  }

  PromptConfig? getPromptConfig(String examId) {
    return _promptByExam[examId] ?? _promptByExam[_defaultExamId];
  }

  String systemPromptForExam({
    required String examId,
    required String fallback,
  }) {
    final configured = getPromptConfig(examId)?.systemPrompt;
    if (configured == null || configured.isEmpty) return fallback;
    return configured;
  }

  String renderPrompt({
    required String examId,
    required String mode,
    required Map<String, String> values,
    required String fallbackTemplate,
  }) {
    final configured = getPromptConfig(examId)?.modeTemplates[mode];
    if (configured == null || configured.isEmpty) {
      debugPrint('Prompt template missing for exam=$examId mode=$mode. Using fallback.');
      return _renderTemplate(fallbackTemplate, values);
    }
    return _renderTemplate(configured, values);
  }

  String buildSeedRefillPrompt({
    required String examId,
    required String mode,
    required String category,
    required int count,
    required String fallbackTemplate,
    required String fallbackModeInstruction,
  }) {
    final config = getPromptConfig(examId);
    final template = config?.seedRefillTemplate;
    final modeInstruction =
        config?.seedRefillModeInstructions[mode] ?? fallbackModeInstruction;

    if (template == null || template.isEmpty) {
      return _renderTemplate(fallbackTemplate, {
        'mode': mode,
        'category': category,
        'count': '$count',
        'modeInstruction': modeInstruction,
      });
    }

    return _renderTemplate(template, {
      'mode': mode,
      'category': category,
      'count': '$count',
      'modeInstruction': modeInstruction,
    });
  }

  String _renderTemplate(String template, Map<String, String> values) {
    return template.replaceAllMapped(
      RegExp(r'\{\{([a-zA-Z0-9_]+)\}\}'),
      (match) {
        final key = match.group(1) ?? '';
        return values[key] ?? '';
      },
    );
  }
}

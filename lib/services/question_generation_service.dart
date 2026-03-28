import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/question.dart';
import 'exam_driven_config_service.dart';

class QuestionGenerationService {
  static const int _maxRetries = 2;

  final String apiKey;
  final String examId;
  final ExamDrivenConfigService _examConfigService =
      ExamDrivenConfigService.instance;
  late final GenerativeModel model;

  QuestionGenerationService({required this.apiKey, this.examId = 'acet'}) {
    model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.3,
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<List<Question>> generateQuestions(
    String prompt,
    String programInterest, {
    Map<int, String>? categoryMap,
  }) async {
    Exception? lastError;

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        debugPrint('Gemini Flash attempt $attempt/$_maxRetries...');
        return await _doGenerateQuestions(
          prompt,
          programInterest,
          categoryMap: categoryMap,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('Attempt $attempt failed: $e');
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    throw lastError ??
        Exception('Question generation failed after $_maxRetries attempts');
  }

  Future<List<Question>> _doGenerateQuestions(
    String prompt,
    String programInterest, {
    Map<int, String>? categoryMap,
  }) async {
    await _examConfigService.ensureLoaded();

    final systemPrompt = _examConfigService.systemPromptForExam(
      examId: examId,
      fallback: 'You are an ACET item writer. '
          'Return VALID JSON ONLY. No markdown. No comments. '
          'Write real exam-style multiple-choice questions, not meta-questions and not topic-label questions. '
          'Never ask the student to identify the skill, category, competency, or lesson being tested. '
          'Every item must have a solvable stem and one clearly correct answer. '
          'Keep all options similar in length. '
          'Never use combined-option wording like "A and B", "A and C", "both A and B", or "all of the above" in any choice text. '
          'Never make the correct option obviously the longest or shortest by wording. '
          'Use plausible distractors based on common student mistakes. '
          'Distribute correct answers across A/B/C/D without obvious repeating patterns. '
          'Use Unicode math symbols only when needed; avoid LaTeX and backslashes.',
    );

    final content = [
      Content.text(
        '$systemPrompt\n\n$prompt',
      ),
    ];

    final response = await model.generateContent(content);

    if (response.text == null || response.text!.isEmpty) {
      throw Exception('Empty response from Gemini');
    }

    String rawContent = response.text!.trim();

    // CLEANUP (LLM safety)
    rawContent = rawContent.replaceAll('```json', '');
    rawContent = rawContent.replaceAll('```', '');
    rawContent = rawContent.trim();

    dynamic decodedContent;

    try {
      decodedContent = jsonDecode(rawContent);
    } catch (e) {
      debugPrint('Error: JSON decode failed');
      debugPrint(rawContent);
      throw Exception('Invalid AI JSON response');
    }

    List questionsJson;

    // Case 1: Raw array returned
    if (decodedContent is List) {
      questionsJson = decodedContent;
    }
    // Case 2: Wrapped in { "questions": [...] }
    else if (decodedContent is Map && decodedContent['questions'] is List) {
      questionsJson = decodedContent['questions'];
    } else {
      debugPrint('Error: Unexpected JSON structure');
      debugPrint(decodedContent.toString());
      throw Exception('Unexpected AI response format');
    }

    // Default random distribution (15 questions):
    // Q1-4 English, Q5-8 Mathematics, Q9-12 Logical Reasoning,
    // Q13-15 Mental Ability / Abstract.

    final parsed = questionsJson
        .map((q) {
          final num = q['number'] as int;
          String category;

          // If custom categoryMap is provided (e.g., for Challenge Mode), use it
          if (categoryMap != null && categoryMap.containsKey(num)) {
            category = categoryMap[num]!;
          } else {
            if (num >= 1 && num <= 4) {
              category = 'English';
            } else if (num >= 5 && num <= 8) {
              category = 'Mathematics';
            } else if (num >= 9 && num <= 12) {
              category = 'Logical Reasoning';
            } else {
              category = 'Mental Ability / Abstract';
            }
          }

          return Question(
            number: num,
            category: category,
            question: q['question'],
            choices: List<String>.from(q['choices']),
            answer: q['answer'],
            explanation: q['explanation'],
            source: 'gemini',
          );
        })
        .where((q) => !_hasCombinedChoice(q.choices))
        .toList();

    if (parsed.isEmpty) {
      throw Exception(
          'Generated choices contained invalid combined-option wording.');
    }

    return parsed;
  }

  bool _hasCombinedChoice(List<String> choices) {
    final combinedPattern = RegExp(
      r'\b(?:both\s+[A-D]\s+and\s+[A-D]|[A-D]\s*(?:and|&)\s*[A-D]|all\s+of\s+the\s+above|both\s+of\s+the\s+above)\b',
      caseSensitive: false,
    );

    return choices.any((c) => combinedPattern.hasMatch(c));
  }
}

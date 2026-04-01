import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_app_check/firebase_app_check.dart';
import '../models/question.dart';
import '../config/secrets.dart';
import 'exam_driven_config_service.dart';

class GatewayService {
  static const Duration _questionTimeout = Duration(seconds: 115);
  static const Duration _explanationTimeout = Duration(seconds: 55);
  static const int _maxQuestionRetries = 3;
  static final http.Client _httpClient = http.Client();

  final ExamDrivenConfigService _examConfigService =
      ExamDrivenConfigService.instance;

  final String examId;
  final double temperature;
  final int? maxTokens;
  final int maxRetries;

  GatewayService({
    this.examId = 'pnle',
    this.temperature = 0.3,
    this.maxTokens,
    this.maxRetries = _maxQuestionRetries,
  });

  /// Get a fresh App Check token for gateway authentication.
  Future<Map<String, String>> _authHeaders() async {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      debugPrint('App Check token obtained: ${token != null ? "${token.substring(0, 20)}..." : "NULL"}');
      if (token == null) {
        debugPrint('WARNING: App Check token is null — server will reject request');
      }
      return {
        'Content-Type': 'application/json',
        if (token != null) 'X-Firebase-AppCheck': token,
      };
    } catch (e) {
      debugPrint('App Check getToken() FAILED: $e — server will reject request');
      return {'Content-Type': 'application/json'};
    }
  }

  // =========================================================================
  // Question generation via gateway
  // =========================================================================

  Future<List<Question>> generateQuestions(
    String prompt,
    String programInterest, {
    Map<int, String>? categoryMap,
    String provider = 'deepseek',
    bool allowPartialResults = false,
  }) async {
    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('Gateway ($provider) attempt $attempt/$maxRetries...');
        return await _doGenerateQuestions(
          prompt,
          programInterest,
          provider: provider,
          categoryMap: categoryMap,
          allowPartialResults: allowPartialResults,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('Attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    throw lastError ??
        Exception('Question generation failed after $maxRetries attempts');
  }

  Future<List<Question>> _doGenerateQuestions(
    String prompt,
    String programInterest, {
    required String provider,
    Map<int, String>? categoryMap,
    bool allowPartialResults = false,
  }) async {
    await _examConfigService.ensureLoaded();

    final systemPrompt = _examConfigService.systemPromptForExam(
      examId: examId,
      fallback: "You are a PNLE item writer. "
          "Return VALID JSON ONLY. No markdown. No comments. "
          "Write real exam-style multiple-choice questions, not meta-questions and not topic-label questions. "
          "Never ask the student to identify the skill, category, competency, or lesson being tested. "
          "Every item must have a solvable stem and one clearly correct answer. "
          "Keep all options similar in length. "
          "Never use combined-option wording like 'A and B', 'A and C', 'both A and B', or 'all of the above' in any choice text. "
          "Never make the correct option obviously the longest or shortest by wording. "
          "Use plausible distractors based on common student mistakes. "
          "Use Unicode math symbols only when needed; avoid LaTeX and backslashes. "
          "Distribute correct answers across A/B/C/D without obvious repeating patterns.",
    );

    final body = jsonEncode({
      'provider': provider,
      'systemPrompt': systemPrompt,
      'prompt': prompt,
      'temperature': temperature,
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (provider == 'gemini') 'responseMimeType': 'application/json',
    });

    final headers = await _authHeaders();

    final response = await _httpClient
        .post(
          Uri.parse(QUESTIONS_GATEWAY_URL),
          headers: headers,
          body: body,
        )
        .timeout(_questionTimeout);

    if (response.statusCode != 200) {
      final preview = response.body.length > 240
          ? '${response.body.substring(0, 240)}...'
          : response.body;
      throw Exception(
        'Gateway error (${response.statusCode}): $preview',
      );
    }

    final decoded = jsonDecode(response.body);
    String content = (decoded['content'] as String).trim();

    // CLEANUP (LLM safety)
    content = content.replaceAll('```json', '');
    content = content.replaceAll('```', '');
    content = content.trim();

    final questionsJson = _parseQuestionsWithRecovery(content);
    if (questionsJson.isEmpty) {
      throw Exception('Invalid AI JSON response');
    }

    final expectedCount = _expectedQuestionCount(categoryMap);
    if (questionsJson.length < expectedCount) {
      if (allowPartialResults && questionsJson.isNotEmpty) {
        debugPrint(
          'Warning: Gateway returned partial questions (${questionsJson.length}/$expectedCount). Returning salvage set.',
        );
      } else {
        throw Exception(
          'Incomplete AI JSON response (${questionsJson.length}/$expectedCount questions).',
        );
      }
    }

    final parsedQuestions = <Question>[];

    for (int i = 0; i < questionsJson.length; i++) {
      final q = questionsJson[i];
      final num = q['number'] as int;
      String category;

      if (categoryMap != null && categoryMap.containsKey(num)) {
        category = categoryMap[num]!;
      } else {
        category = 'General';
      }

      parsedQuestions.add(Question(
        number: num,
        category: category,
        question: q['question'],
        choices: List<String>.from(q['choices']),
        answer: q['answer'],
        explanation: q['explanation'],
        source: provider,
      ));
    }

    return parsedQuestions;
  }

  // =========================================================================
  // Explanation generation via gateway
  // =========================================================================

  Future<String> getExplanation({
    required String question,
    required List<String> choices,
    required String userAnswer,
    required String correctAnswer,
  }) async {
    try {
      final prompt = _buildExplanationPrompt(
        question: question,
        choices: choices,
        userAnswer: userAnswer,
        correctAnswer: correctAnswer,
      );

      return await _callExplanationGateway(
        prompt: prompt,
        provider: 'gemini',
      );
    } catch (e) {
      return _explanationErrorMessage(e);
    }
  }

  Future<String> getBetterExplanation({
    required String question,
    required List<String> choices,
    required String userAnswer,
    required String correctAnswer,
  }) async {
    try {
      final prompt = _buildExplanationPrompt(
        question: question,
        choices: choices,
        userAnswer: userAnswer,
        correctAnswer: correctAnswer,
      );

      return await _callExplanationGateway(
        prompt: prompt,
        provider: 'gpt',
        maxTokens: 500,
      );
    } catch (e) {
      return _explanationErrorMessage(e);
    }
  }

  Future<String> _callExplanationGateway({
    required String prompt,
    required String provider,
    int? maxTokens,
  }) async {
    final body = jsonEncode({
      'provider': provider,
      'prompt': prompt,
      if (maxTokens != null) 'maxTokens': maxTokens,
    });

    final headers = await _authHeaders();

    final response = await _httpClient
        .post(
          Uri.parse(EXPLANATION_GATEWAY_URL),
          headers: headers,
          body: body,
        )
        .timeout(_explanationTimeout);

    if (response.statusCode != 200) {
      throw Exception('Gateway error (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final content = (decoded['content'] as String).trim();

    if (content.isEmpty) {
      return 'Unable to prepare explanation. Please try again.';
    }

    return content;
  }

  // =========================================================================
  // Explanation prompt builder (shared between Gemini and GPT paths)
  // =========================================================================

  String _buildExplanationPrompt({
    required String question,
    required List<String> choices,
    required String userAnswer,
    required String correctAnswer,
  }) {
    final choicesStr = choices.asMap().entries.map((e) {
      final letter = String.fromCharCode(97 + e.key);
      return '$letter) ${e.value}';
    }).join(', ');

    String resolveAnswerLetter(String value) {
      final trimmed = value.trim();
      if (trimmed.length == 1) {
        final lower = trimmed.toLowerCase();
        if (lower == 'a' || lower == 'b' || lower == 'c' || lower == 'd') {
          return lower;
        }
      }
      final normalized = trimmed.toLowerCase();
      for (int i = 0; i < choices.length; i++) {
        if (choices[i].trim().toLowerCase() == normalized) {
          return String.fromCharCode(97 + i);
        }
      }
      return 'unknown';
    }

    final userAnswerLetter = resolveAnswerLetter(userAnswer);
    final correctAnswerLetter = resolveAnswerLetter(correctAnswer);
    final userAnswerFeedback = userAnswerLetter != correctAnswerLetter &&
            userAnswerLetter != 'unknown'
        ? ' You selected $userAnswerLetter, which is incorrect because it misses the key point that applies to option $correctAnswerLetter.'
        : '';

    return '''The question is: $question
The choices given are: $choicesStr
The given correct answer is $correctAnswerLetter) $correctAnswer.
User selected: $userAnswerLetter) $userAnswer.

Provide a brief, PNLE-relevant explanation for why this is the correct choice.
Structure the response in 3-5 concise sentences:
1) State why the correct choice is best.
2) Give the key reasoning step or principle that leads to the answer.
3) Briefly contrast why the user-selected option is less accurate.$userAnswerFeedback

LANGUAGE: If the question is in Filipino, explain in Filipino. Otherwise use English.

FORMATTING (MANDATORY):
- Do not use asterisks, bold formatting, or special characters.
- Use plain text only.
- Keep the explanation focused and avoid unnecessary or repetitive text.

Return only the explanation text.''';
  }

  // =========================================================================
  // Error message helper
  // =========================================================================

  String _explanationErrorMessage(Object e) {
    final errorMsg = e.toString().toLowerCase();
    if (errorMsg.contains('429') ||
        errorMsg.contains('quota') ||
        errorMsg.contains('rate limit')) {
      return '⚠️ Service temporarily busy (rate limit). Please wait a moment and try again.';
    } else if (errorMsg.contains('503') ||
        errorMsg.contains('unavailable') ||
        errorMsg.contains('service')) {
      return '⚠️ Explanation service is currently unavailable. Please try again later.';
    } else if (errorMsg.contains('timeout') ||
        errorMsg.contains('deadline')) {
      return '⚠️ Request timed out. Please try again.';
    } else if (errorMsg.contains('connection') ||
        errorMsg.contains('network')) {
      return '⚠️ Network connection error. Please check your internet and try again.';
    }
    return 'Unable to prepare explanation. Please try again.';
  }

  // =========================================================================
  // Question JSON parsing with recovery (extracted from DeepSeekService)
  // =========================================================================

  int _expectedQuestionCount(Map<int, String>? categoryMap) {
    if (categoryMap != null && categoryMap.isNotEmpty) {
      return categoryMap.length;
    }
    return 15;
  }

  List<Map<String, dynamic>> _parseQuestionsWithRecovery(String content) {
    final strict = _parseQuestionsStrict(content);
    if (strict.isNotEmpty) return strict;

    debugPrint('Warning: Strict JSON parse failed. Trying recovery parser...');

    final recoveredFromQuestionsKey =
        _recoverQuestionsFromQuestionsKey(content);
    if (recoveredFromQuestionsKey.isNotEmpty) {
      debugPrint(
          'Recovered ${recoveredFromQuestionsKey.length} questions from questions[] slice.');
      return recoveredFromQuestionsKey;
    }

    final recoveredFromObjects = _recoverQuestionsFromObjectScan(content);
    if (recoveredFromObjects.isNotEmpty) {
      debugPrint(
          'Recovered ${recoveredFromObjects.length} questions from object scan.');
      return recoveredFromObjects;
    }

    debugPrint(
        'Error: JSON decode failed and recovery found no valid questions.');
    debugPrint(content);
    return const [];
  }

  List<Map<String, dynamic>> _parseQuestionsStrict(String content) {
    try {
      final decodedContent = jsonDecode(content);
      if (decodedContent is List) {
        return _sanitizeQuestionItems(decodedContent);
      }
      if (decodedContent is Map && decodedContent['questions'] is List) {
        return _sanitizeQuestionItems(decodedContent['questions'] as List);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _recoverQuestionsFromQuestionsKey(String content) {
    final keyIndex = content.indexOf('"questions"');
    if (keyIndex == -1) return const [];

    final arrayStart = content.indexOf('[', keyIndex);
    if (arrayStart == -1) return const [];

    final arrayEnd = _findMatchingBracket(content, arrayStart, '[', ']');
    if (arrayEnd == -1) return const [];

    final arraySlice = content.substring(arrayStart, arrayEnd + 1);
    try {
      final decoded = jsonDecode(arraySlice);
      if (decoded is List) {
        return _sanitizeQuestionItems(decoded);
      }
    } catch (_) {}

    return const [];
  }

  List<Map<String, dynamic>> _recoverQuestionsFromObjectScan(String content) {
    final objects = <Map<String, dynamic>>[];
    int index = 0;

    while (index < content.length) {
      final start = content.indexOf('{', index);
      if (start == -1) break;

      final end = _findMatchingBracket(content, start, '{', '}');
      if (end == -1) {
        index = start + 1;
        continue;
      }

      final candidate = content.substring(start, end + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          final sanitized = _sanitizeQuestionMap(decoded, objects.length + 1);
          if (sanitized != null) {
            objects.add(sanitized);
          }
        }
      } catch (_) {}

      index = end + 1;
    }

    return objects;
  }

  int _findMatchingBracket(String text, int start, String open, String close) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = start; i < text.length; i++) {
      final ch = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (ch == open) depth++;
      if (ch == close) {
        depth--;
        if (depth == 0) return i;
      }
    }

    return -1;
  }

  List<Map<String, dynamic>> _sanitizeQuestionItems(List rawItems) {
    final sanitized = <Map<String, dynamic>>[];
    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is! Map) continue;

      final converted = _sanitizeQuestionMap(
        item.map((key, value) => MapEntry(key.toString(), value)),
        i + 1,
      );
      if (converted != null) sanitized.add(converted);
    }
    return sanitized;
  }

  Map<String, dynamic>? _sanitizeQuestionMap(
    Map<String, dynamic> raw,
    int fallbackNumber,
  ) {
    final question = _cleanText((raw['question'] ?? '').toString().trim());
    final answer = (raw['answer'] ?? '').toString().trim().toUpperCase();

    if (question.isEmpty) return null;
    if (answer != 'A' && answer != 'B' && answer != 'C' && answer != 'D') {
      return null;
    }

    final rawChoices = raw['choices'];
    if (rawChoices is! List || rawChoices.length != 4) return null;

    // Strip leading letter prefixes like "A. ", "B) ", "a. " that the AI may add,
    // since the UI already renders its own A/B/C/D labels.
    final _letterPrefix = RegExp(r'^[A-Da-d][.)]\s*');

    final choices = rawChoices
        .map((choice) => _cleanText(choice.toString().trim()).replaceFirst(_letterPrefix, ''))
        .where((choice) => choice.isNotEmpty)
        .toList();

    if (choices.length != 4) return null;
    if (_hasCombinedChoice(choices)) return null;

    final parsedNumber = int.tryParse((raw['number'] ?? '').toString());
    final number = parsedNumber ?? fallbackNumber;

    final explanationText = _cleanText((raw['explanation'] ?? '').toString().trim());

    return {
      'number': number,
      'question': question,
      'choices': choices,
      'answer': answer,
      'explanation': explanationText.isEmpty ? null : explanationText,
    };
  }

  /// Replace Unicode replacement characters and common mojibake with proper equivalents.
  String _cleanText(String text) {
    return text
        .replaceAll('\u{FFFD}', '')       // replacement character ·
        .replaceAll('â€™', "'")           // right single quote mojibake
        .replaceAll('â€œ', '"')           // left double quote mojibake
        .replaceAll('â€\u009D', '"')      // right double quote mojibake
        .replaceAll('â€"', '–')           // en-dash mojibake
        .replaceAll('â€"', '—')           // em-dash mojibake
        .replaceAll('Â', '')              // stray Latin-1 padding
        .trim();
  }

  bool _hasCombinedChoice(List<String> choices) {
    final combinedPattern = RegExp(
      r'\b(?:both\s+[A-D]\s+and\s+[A-D]|[A-D]\s*(?:and|&)\s*[A-D]|all\s+of\s+the\s+above|both\s+of\s+the\s+above)\b',
      caseSensitive: false,
    );
    return choices.any((c) => combinedPattern.hasMatch(c));
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/question.dart';
import 'exam_driven_config_service.dart';

class DeepSeekService {
  static const List<String> _apiUrls = [
    'https://api.deepseek.com/v1/chat/completions',
    'https://api.deepseek.com/chat/completions',
  ];
  static const Duration _defaultRequestTimeout = Duration(seconds: 90);
  static const int _defaultMaxRetries = 3;
  static final http.Client _httpClient = http.Client();

  final String apiKey;
  final Duration requestTimeout;
  final int maxRetries;
  final double temperature;
  final int? maxTokens;
  final String examId;
  final ExamDrivenConfigService _examConfigService =
      ExamDrivenConfigService.instance;

  DeepSeekService({
    required this.apiKey,
    this.requestTimeout = _defaultRequestTimeout,
    this.maxRetries = _defaultMaxRetries,
    this.temperature = 0.3,
    this.maxTokens,
    this.examId = 'ustet',
  });

  Future<List<Question>> generateQuestions(
    String prompt,
    String eligibility, {
    Map<int, String>? categoryMap,
    bool allowPartialResults = false,
  }) async {
    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('DeepSeek attempt $attempt/$maxRetries...');
        return await _doGenerateQuestions(
          prompt,
          eligibility,
          categoryMap: categoryMap,
          allowPartialResults: allowPartialResults,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('Attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          // Wait before retrying (1s, then 2s)
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    throw lastError ?? Exception('Question generation failed after $maxRetries attempts');
  }

  Future<List<Question>> _doGenerateQuestions(
    String prompt,
    String eligibility, {
    Map<int, String>? categoryMap,
    bool allowPartialResults = false,
  }) async {
    await _examConfigService.ensureLoaded();

    final systemPrompt = _examConfigService.systemPromptForExam(
      examId: examId,
      fallback:
          "You are a USTET item writer. "
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

    final requestBody = jsonEncode({
      "model": "deepseek-chat",
      "messages": [
        {
          "role": "system",
          "content": systemPrompt,
        },
        {
          "role": "user",
          "content": prompt,
        }
      ],
      "temperature": temperature,
      if (maxTokens != null) "max_tokens": maxTokens,
    });

    http.Response? response;
    String? lastErrorMessage;

    for (int i = 0; i < _apiUrls.length; i++) {
      final apiUrl = _apiUrls[i];
      final endpointLabel = i == 0 ? 'primary' : 'fallback';
      bool shouldTryNextEndpoint = true;

      try {
        final candidate = await _httpClient
            .post(
              Uri.parse(apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: requestBody,
            )
            .timeout(requestTimeout);

        if (candidate.statusCode == 200) {
          response = candidate;
          if (i > 0) {
            debugPrint('DeepSeek succeeded on fallback endpoint.');
          }
          break;
        }

        final bodyPreview = candidate.body.length > 240
            ? '${candidate.body.substring(0, 240)}...'
            : candidate.body;
        lastErrorMessage =
          'DeepSeek API error ($endpointLabel): ${candidate.statusCode} - $bodyPreview';
        debugPrint('Warning: $lastErrorMessage');
      } on TimeoutException {
        lastErrorMessage =
            'DeepSeek request timed out after ${requestTimeout.inSeconds}s. Please try again.';
        debugPrint('Warning: DeepSeek $endpointLabel endpoint timed out.');
        shouldTryNextEndpoint = false;
      } on SocketException catch (e) {
        lastErrorMessage = 'DeepSeek network error: ${e.message}';
        debugPrint('Warning: DeepSeek $endpointLabel endpoint socket error: ${e.message}');
      } on http.ClientException catch (e) {
        lastErrorMessage = 'DeepSeek client error: ${e.message}';
        debugPrint('Warning: DeepSeek $endpointLabel endpoint client error: ${e.message}');
      }

      if (!shouldTryNextEndpoint) break;
    }

    if (response == null) {
      throw Exception(lastErrorMessage ?? 'DeepSeek request failed.');
    }

    // Decode outer DeepSeek response
    final decoded = jsonDecode(response.body);
    String content = decoded['choices'][0]['message']['content'];

    // CLEANUP (LLM safety)
    content = content.trim();
    content = content.replaceAll('```json', '');
    content = content.replaceAll('```', '');

    final questionsJson = _parseQuestionsWithRecovery(content);
    if (questionsJson.isEmpty) {
      throw Exception('Invalid AI JSON response');
    }

    final expectedCount = _expectedQuestionCount(categoryMap);
    if (questionsJson.length < expectedCount) {
      if (allowPartialResults && questionsJson.isNotEmpty) {
        debugPrint(
          'Warning: DeepSeek returned partial questions (${questionsJson.length}/$expectedCount). Returning salvage set.',
        );
      } else {
        throw Exception(
          'Incomplete AI JSON response (${questionsJson.length}/$expectedCount questions).',
        );
      }
    }

    // USTET default random distribution (15 questions):
    // Q1-2 Language, Q3-7 Reading, Q8-11 Math, Q12-15 Science.

    final parsedQuestions = <Question>[];

    for (int i = 0; i < questionsJson.length; i++) {
      final q = questionsJson[i];
      final num = q['number'] as int;
      String category;
      
      // If custom categoryMap is provided (e.g., for Challenge Mode), use it
      if (categoryMap != null && categoryMap.containsKey(num)) {
        category = categoryMap[num]!;
      } else {
        if (num >= 1 && num <= 2) {
          category = 'Mental Ability';
        } else if (num >= 3 && num <= 7) {
          category = 'English';
        } else if (num >= 8 && num <= 11) {
          category = 'Mathematics';
        } else {
          category = 'Science';
        }
      }

      parsedQuestions.add(Question(
        number: num,
        category: category,
        question: q['question'],
        choices: List<String>.from(q['choices']),
        answer: q['answer'],
        explanation: q['explanation'],
        source: 'deepseek',
      ));
    }

    return parsedQuestions;
  }

  int _expectedQuestionCount(Map<int, String>? categoryMap) {
    if (categoryMap != null && categoryMap.isNotEmpty) {
      return categoryMap.length;
    }
    // Default USTET full test size.
    return 15;
  }

  List<Map<String, dynamic>> _parseQuestionsWithRecovery(String content) {
    final strict = _parseQuestionsStrict(content);
    if (strict.isNotEmpty) return strict;

    debugPrint('Warning: Strict JSON parse failed. Trying recovery parser...');

    final recoveredFromQuestionsKey = _recoverQuestionsFromQuestionsKey(content);
    if (recoveredFromQuestionsKey.isNotEmpty) {
      debugPrint('Recovered ${recoveredFromQuestionsKey.length} questions from questions[] slice.');
      return recoveredFromQuestionsKey;
    }

    final recoveredFromObjects = _recoverQuestionsFromObjectScan(content);
    if (recoveredFromObjects.isNotEmpty) {
      debugPrint('Recovered ${recoveredFromObjects.length} questions from object scan.');
      return recoveredFromObjects;
    }

    debugPrint('Error: JSON decode failed and recovery found no valid questions.');
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

      debugPrint('Error: Unexpected JSON structure');
      debugPrint(decodedContent.toString());
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
    } catch (_) {
      // Fall through to object-scan recovery.
    }

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
        // If outer JSON is truncated, continue scanning for later complete objects.
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
      } catch (_) {
        // Ignore invalid object candidate.
      }

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
    final question = (raw['question'] ?? '').toString().trim();
    final answer = (raw['answer'] ?? '').toString().trim().toUpperCase();

    if (question.isEmpty) return null;
    if (answer != 'A' && answer != 'B' && answer != 'C' && answer != 'D') {
      return null;
    }

    final rawChoices = raw['choices'];
    if (rawChoices is! List || rawChoices.length != 4) return null;

    final choices = rawChoices
        .map((choice) => choice.toString().trim())
        .where((choice) => choice.isNotEmpty)
        .toList();

    if (choices.length != 4) return null;
    if (_hasCombinedChoice(choices)) return null;

    final parsedNumber = int.tryParse((raw['number'] ?? '').toString());
    final number = parsedNumber ?? fallbackNumber;

    final explanationText = (raw['explanation'] ?? '').toString().trim();

    return {
      'number': number,
      'question': question,
      'choices': choices,
      'answer': answer,
      'explanation': explanationText.isEmpty ? null : explanationText,
    };
  }

  bool _hasCombinedChoice(List<String> choices) {
    final combinedPattern = RegExp(
      r'\b(?:both\s+[A-D]\s+and\s+[A-D]|[A-D]\s*(?:and|&)\s*[A-D]|all\s+of\s+the\s+above|both\s+of\s+the\s+above)\b',
      caseSensitive: false,
    );
    return choices.any((c) => combinedPattern.hasMatch(c));
  }
}

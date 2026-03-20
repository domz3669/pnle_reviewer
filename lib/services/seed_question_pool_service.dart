import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question.dart';
import '../models/pnle_key_areas.dart';

class SeedQuestionPoolService {
  static const String _assetPath = 'assets/seed/initial_question_pool.json';
  static const String _prefsKey = 'seedQuestionPoolPayloadV1';

  final Random _random = Random();
  bool _initialized = false;

  // mode -> category -> question list
  final Map<String, Map<String, List<Question>>> _pool = {};

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final savedPayload = prefs.getString(_prefsKey);

    if (savedPayload != null) {
      try {
        final raw = jsonDecode(savedPayload);
        if (raw is Map<String, dynamic>) {
          _hydrateFromMap(raw);
          _initialized = true;
          return;
        }
      } catch (_) {
        // Fallback to asset initialization.
      }
    }

    final assetRaw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(assetRaw);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid seed pool payload.');
    }

    _hydrateFromMap(decoded);
    _initialized = true;
    await _persist();
  }

  Future<List<Question>> takeQuestions({
    required String mode,
    required Map<int, String> categoryMap,
  }) async {
    await ensureInitialized();

    if (!_pool.containsKey(mode) || categoryMap.isEmpty) {
      return const [];
    }

    final neededPerCategory = <String, int>{};
    for (final category in categoryMap.values) {
      neededPerCategory[category] = (neededPerCategory[category] ?? 0) + 1;
    }

    final modeBuckets = _pool[mode] ?? {};
    for (final entry in neededPerCategory.entries) {
      final available = modeBuckets[entry.key]?.length ?? 0;
      if (available < entry.value) {
        return const [];
      }
    }

    final result = <Question>[];
    final sortedKeys = categoryMap.keys.toList()..sort();

    for (final qNo in sortedKeys) {
      final category = categoryMap[qNo] ?? '';
      final bucket = modeBuckets[category];

      if (bucket == null || bucket.isEmpty) {
        return const [];
      }

      final idx = _random.nextInt(bucket.length);
      final picked = bucket.removeAt(idx);
      result.add(
        Question(
          number: qNo,
          category: picked.category,
          question: picked.question,
          choices: List<String>.from(picked.choices),
          answer: picked.answer,
          explanation: picked.explanation,
          source: picked.source,
        ),
      );
    }

    await _persist();
    return result;
  }

  bool canServe(String mode, Map<int, String> categoryMap) {
    if (!_initialized || categoryMap.isEmpty) return false;

    final modeBuckets = _pool[mode];
    if (modeBuckets == null) return false;

    final neededPerCategory = <String, int>{};
    for (final category in categoryMap.values) {
      neededPerCategory[category] = (neededPerCategory[category] ?? 0) + 1;
    }

    for (final entry in neededPerCategory.entries) {
      final available = modeBuckets[entry.key]?.length ?? 0;
      if (available < entry.value) return false;
    }

    return true;
  }

  Future<Map<String, int>> getDeficits({
    int threshold = 20,
    int targetSize = 30,
  }) async {
    await ensureInitialized();

    final deficits = <String, int>{};
    const supportedModes = <String>{'randomQuiz', 'focusMode', 'challenge'};

    for (final mode in supportedModes) {
      final modeBuckets = _pool[mode] ?? {};
      for (final category in pnleCategories) {
        final current = modeBuckets[category]?.length ?? 0;
        if (current <= threshold) {
          deficits['$mode::$category'] = max(0, targetSize - current);
        }
      }
    }

    return deficits;
  }

  Future<void> addQuestions(
    String mode,
    String category,
    List<Question> questions, {
    int targetSize = 30,
  }) async {
    await ensureInitialized();

    if (questions.isEmpty) return;

    final modeBuckets = _pool.putIfAbsent(mode, () => {});
    final bucket = modeBuckets.putIfAbsent(category, () => []);

    for (final question in questions) {
      if (question.choices.length < 4) continue;
      if (question.answer.isEmpty) continue;

      final normalized = Question(
        number: bucket.length + 1,
        category: category,
        question: question.question.trim(),
        choices: List<String>.from(question.choices.take(4)),
        answer: question.answer.trim().toUpperCase(),
        explanation: question.explanation,
        source: question.source ?? 'seed_refill',
      );

      if (_isValidAnswer(normalized.answer, normalized.choices.length)) {
        bucket.add(normalized);
      }
    }

    if (bucket.length > targetSize) {
      bucket.removeRange(targetSize, bucket.length);
    }

    await _persist();
  }

  void _hydrateFromMap(Map<String, dynamic> payload) {
    _pool.clear();

    final poolsRaw = payload['pools'];
    if (poolsRaw is! List) {
      throw Exception('Seed payload missing pools list.');
    }

    for (final item in poolsRaw.whereType<Map>()) {
      final modeRaw = item['mode'];
      final categoryRaw = item['category'];
      final questionsRaw = item['questions'];

      if (modeRaw is! String ||
          categoryRaw is! String ||
          questionsRaw is! List) {
        continue;
      }

      final modeBuckets = _pool.putIfAbsent(modeRaw, () => {});
      final bucket = modeBuckets.putIfAbsent(categoryRaw, () => []);

      for (final q in questionsRaw.whereType<Map>()) {
        try {
          final parsed = Question.fromJson(Map<String, dynamic>.from(q));
          if (parsed.choices.length >= 4 &&
              _isValidAnswer(parsed.answer, parsed.choices.length)) {
            bucket.add(parsed);
          }
        } catch (_) {
          // Skip malformed question.
        }
      }
    }
  }

  bool _isValidAnswer(String answer, int choicesLength) {
    if (answer.length != 1) return false;
    final index = answer.codeUnitAt(0) - 65;
    return index >= 0 && index < choicesLength;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();

    final pools = <Map<String, dynamic>>[];
    _pool.forEach((mode, buckets) {
      buckets.forEach((category, questions) {
        pools.add({
          'mode': mode,
          'category': category,
          'questions': questions
              .asMap()
              .entries
              .map(
                (entry) => {
                  'number': entry.key + 1,
                  'category': category,
                  'question': entry.value.question,
                  'choices': entry.value.choices,
                  'answer': entry.value.answer,
                  'explanation': entry.value.explanation,
                  'source': entry.value.source,
                },
              )
              .toList(),
        });
      });
    });

    final payload = {
      'schema': 'seed_pool_v1',
      'pools': pools,
    };

    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}

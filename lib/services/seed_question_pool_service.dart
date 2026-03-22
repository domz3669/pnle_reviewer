import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

  static const Set<String> _supportedModes = {
    'randomQuiz',
    'focusMode',
    'challenge',
    'timedExam',
  };

  String _normalizeMode(String mode) {
    switch (mode) {
      case 'timedMode':
        return 'timedExam';
      default:
        return mode;
    }
  }

  bool _isTemplateQuestionText(String text) {
    final normalized = text.trim().toLowerCase();
    return normalized.startsWith('identify the key area being tested') ||
        normalized.startsWith('focus mode: pick the most precise key') ||
        normalized.contains('scenario emphasis:');
  }

  bool _isUsableQuestion(Question question) {
    if (question.question.trim().isEmpty) return false;
    if (_isTemplateQuestionText(question.question)) return false;
    return true;
  }

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
          _logPoolSummary(source: 'prefs');
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
    _logPoolSummary(source: 'asset');
  }

  void _logPoolSummary({required String source}) {
    try {
      final parts = <String>[];
      int grandTotal = 0;

      for (final mode in _supportedModes) {
        final buckets = _pool[mode] ?? const <String, List<Question>>{};
        final counts = <String>[];
        int modeTotal = 0;
        for (final category in pnleCategories) {
          final count = buckets[category]?.length ?? 0;
          counts.add('$category=$count');
          modeTotal += count;
        }
        grandTotal += modeTotal;
        parts.add('$mode[$modeTotal]{${counts.join(', ')}}');
      }

      debugPrint('[SeedPool] Loaded from $source. Total=$grandTotal :: ${parts.join(' | ')}');
    } catch (e) {
      debugPrint('[SeedPool] Unable to print summary: $e');
    }
  }

  Future<List<Question>> takeQuestions({
    required String mode,
    required Map<int, String> categoryMap,
  }) async {
    await ensureInitialized();

    final normalizedMode = _normalizeMode(mode);

    if (!_pool.containsKey(normalizedMode) || categoryMap.isEmpty) {
      return const [];
    }

    final neededPerCategory = <String, int>{};
    for (final category in categoryMap.values) {
      neededPerCategory[category] = (neededPerCategory[category] ?? 0) + 1;
    }

    final modeBuckets = _pool[normalizedMode] ?? {};

    // Purge template-like placeholders that may exist in older persisted pools.
    var poolChanged = false;
    modeBuckets.forEach((_, bucket) {
      final before = bucket.length;
      bucket.removeWhere((q) => !_isUsableQuestion(q));
      if (bucket.length != before) {
        poolChanged = true;
      }
    });
    if (poolChanged) {
      await _persist();
    }

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
      if (!_isUsableQuestion(picked)) {
        continue;
      }
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

    final modeBuckets = _pool[_normalizeMode(mode)];
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
    for (final mode in _supportedModes) {
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

    final normalizedMode = _normalizeMode(mode);

    if (questions.isEmpty) return;

    final modeBuckets = _pool.putIfAbsent(normalizedMode, () => {});
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
        if (_isUsableQuestion(normalized)) {
          bucket.add(normalized);
        }
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
    if (poolsRaw is List) {
      for (final item in poolsRaw.whereType<Map>()) {
        final modeRaw = item['mode'];
        final categoryRaw = item['category'];
        final questionsRaw = item['questions'];

        if (modeRaw is! String ||
            categoryRaw is! String ||
            questionsRaw is! List) {
          continue;
        }

        _ingestQuestionList(
          mode: modeRaw,
          category: categoryRaw,
          questionsRaw: questionsRaw,
        );
      }
    }

    // Also support nested schema:
    // { exam, total_questions, modes:[{mode,categories:[{category,questions:[]}] }] }
    final modesRaw = payload['modes'];
    if (modesRaw is List) {
      for (final modeItem in modesRaw.whereType<Map>()) {
        final modeRaw = modeItem['mode'];
        final categoriesRaw = modeItem['categories'];
        if (modeRaw is! String || categoriesRaw is! List) {
          continue;
        }

        for (final categoryItem in categoriesRaw.whereType<Map>()) {
          final categoryRaw = categoryItem['category'];
          final questionsRaw = categoryItem['questions'];
          if (categoryRaw is! String || questionsRaw is! List) {
            continue;
          }

          _ingestQuestionList(
            mode: modeRaw,
            category: categoryRaw,
            questionsRaw: questionsRaw,
          );
        }
      }
    }

    _ensureBaselinePoolCoverage(targetSize: 30);
  }

  void _ingestQuestionList({
    required String mode,
    required String category,
    required List questionsRaw,
  }) {
    final normalizedMode = _normalizeMode(mode);
    if (!_supportedModes.contains(normalizedMode)) {
      return;
    }

    final modeBuckets = _pool.putIfAbsent(normalizedMode, () => {});
    final bucket = modeBuckets.putIfAbsent(category, () => []);

    for (final q in questionsRaw.whereType<Map>()) {
      try {
        final parsed = Question.fromJson(Map<String, dynamic>.from(q));
        if (parsed.choices.length >= 4 &&
            _isValidAnswer(parsed.answer, parsed.choices.length) &&
            _isUsableQuestion(parsed)) {
          bucket.add(parsed);
        }
      } catch (_) {
        // Skip malformed question.
      }
    }
  }

  void _ensureBaselinePoolCoverage({int targetSize = 30}) {
    for (final mode in _supportedModes) {
      final modeBuckets = _pool.putIfAbsent(mode, () => {});

      for (final category in pnleCategories) {
        final bucket = modeBuckets.putIfAbsent(category, () => []);
        if (bucket.length >= targetSize) {
          continue;
        }

        final fallbackCandidates = <Question>[];

        final randomBucket = _pool['randomQuiz']?[category] ?? const <Question>[];
        fallbackCandidates.addAll(randomBucket);

        for (final fallbackMode in _supportedModes) {
          if (fallbackMode == mode) continue;
          final other = _pool[fallbackMode]?[category] ?? const <Question>[];
          fallbackCandidates.addAll(other);
        }

        int cursor = 0;
        while (bucket.length < targetSize && fallbackCandidates.isNotEmpty) {
          final source = fallbackCandidates[cursor % fallbackCandidates.length];
          cursor++;

          final cloned = Question(
            number: bucket.length + 1,
            category: category,
            question: source.question,
            choices: List<String>.from(source.choices),
            answer: source.answer,
            explanation: source.explanation,
            source: source.source ?? 'seed_pool_2027',
          );

          if (_isUsableQuestion(cloned) &&
              _isValidAnswer(cloned.answer, cloned.choices.length)) {
            bucket.add(cloned);
          }
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

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/question.dart';

class LocalVisualQuestionService {
  const LocalVisualQuestionService();

  static const int _targetChoiceCount = 4;

  Future<List<Question>> loadQuestions({required String assetPath}) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <Question>[];
    }

    final defaultCategory =
        (decoded['category'] as String?)?.trim().isNotEmpty == true
            ? (decoded['category'] as String).trim()
            : 'Mental Ability / Abstract';

    final rawQuestions = decoded['questions'];
    if (rawQuestions is! List) {
      return const <Question>[];
    }

    final parsed = <Question>[];
    for (final item in rawQuestions) {
      if (item is! Map) continue;
      final row = item.cast<String, dynamic>();

      final number = (row['number'] as num?)?.toInt() ?? parsed.length + 1;
      final questionText = _normalizeVisualPrompt(row['question'] as String?);
      final explanation = (row['explanation'] as String?)?.trim();
      final imageAssetPath = (row['imageAssetPath'] as String?)?.trim();
      final category = (row['category'] as String?)?.trim().isNotEmpty == true
          ? (row['category'] as String).trim()
          : defaultCategory;

      if (imageAssetPath == null || imageAssetPath.isEmpty) {
        continue;
      }

      final answerToken = _normalizeAnswerToken(row['answer']);
      if (answerToken == null) {
        continue;
      }

      final rawChoices = row['choices'];
      final explicitChoices = _parseExplicitChoices(
        rawChoices: rawChoices,
        answerToken: answerToken,
      );

      final reduced = explicitChoices.length >= 2
          ? _buildReducedChoicesFromExplicit(
              explicitChoices: explicitChoices,
              answerToken: answerToken,
              seed: number,
            )
          : _buildReducedChoicesFromFallback(
              answerToken: answerToken,
              rawOptionCount: (row['optionCount'] as num?)?.toInt(),
              seed: number,
            );

      if (reduced == null) {
        continue;
      }

      parsed.add(
        Question(
          number: number,
          category: category,
          question: questionText,
          imageAssetPath: imageAssetPath,
          choices: reduced.choices,
          answer: reduced.answer,
          explanation: explanation,
          source: 'local_visual_odd_one_out',
        ),
      );
    }

    return parsed;
  }

  _AnswerToken? _normalizeAnswerToken(dynamic raw) {
    final value = (raw?.toString() ?? '').trim().toUpperCase();
    if (value.isEmpty) return null;

    final asNumber = int.tryParse(value);
    if (asNumber != null && asNumber > 0) {
      return _AnswerToken.numeric(asNumber);
    }

    if (value.length == 1) {
      final code = value.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        return _AnswerToken.letter(String.fromCharCode(code));
      }
    }

    return null;
  }

  List<String> _parseExplicitChoices({
    required dynamic rawChoices,
    required _AnswerToken answerToken,
  }) {
    if (rawChoices is! List) {
      return const <String>[];
    }

    final normalized = <String>[];
    for (final item in rawChoices) {
      final text = (item?.toString() ?? '').trim();
      if (text.isEmpty) continue;

      switch (answerToken.kind) {
        case _AnswerKind.numeric:
          final n = int.tryParse(text);
          if (n != null && n > 0) {
            normalized.add('$n');
          }
          break;
        case _AnswerKind.letter:
          if (text.length == 1) {
            final upper = text.toUpperCase();
            final code = upper.codeUnitAt(0);
            if (code >= 65 && code <= 90) {
              normalized.add(upper);
            }
          }
          break;
      }
    }

    final unique = <String>[];
    for (final choice in normalized) {
      if (!unique.contains(choice)) {
        unique.add(choice);
      }
    }

    if (!unique.contains(answerToken.value)) {
      return const <String>[];
    }

    return unique.take(26).toList(growable: false);
  }

  _ReducedChoiceSet? _buildReducedChoicesFromExplicit({
    required List<String> explicitChoices,
    required _AnswerToken answerToken,
    required int seed,
  }) {
    if (explicitChoices.length < 2) {
      return null;
    }

    final correct = answerToken.value;
    if (!explicitChoices.contains(correct)) {
      return null;
    }

    final selected = explicitChoices.length <= _targetChoiceCount
        ? List<String>.from(explicitChoices)
        : _pickSubsetIncludingCorrect(
            available: explicitChoices,
            correct: correct,
            seed: seed,
          );

    final answerIndex = selected.indexOf(correct);
    if (answerIndex < 0) {
      return null;
    }

    return _ReducedChoiceSet(
      choices: selected,
      answer: String.fromCharCode(65 + answerIndex),
    );
  }

  _ReducedChoiceSet? _buildReducedChoicesFromFallback({
    required _AnswerToken answerToken,
    required int? rawOptionCount,
    required int seed,
  }) {
    switch (answerToken.kind) {
      case _AnswerKind.numeric:
        final correct = int.parse(answerToken.value);
        final total = _resolveNumericOptionCount(
          rawOptionCount: rawOptionCount,
          correctValue: correct,
        );
        final available =
            List<String>.generate(total, (index) => '${index + 1}');
        final selected = available.length <= _targetChoiceCount
            ? available
            : _pickSubsetIncludingCorrect(
                available: available,
                correct: '$correct',
                seed: seed,
              );
        final answerIndex = selected.indexOf('$correct');
        if (answerIndex < 0) return null;
        return _ReducedChoiceSet(
          choices: selected,
          answer: String.fromCharCode(65 + answerIndex),
        );
      case _AnswerKind.letter:
        final correctCode = answerToken.value.codeUnitAt(0);
        final correctIndex = correctCode - 64;
        final total = _resolveLetterOptionCount(
          rawOptionCount: rawOptionCount,
          correctIndex: correctIndex,
        );
        final available = List<String>.generate(
          total,
          (index) => String.fromCharCode(65 + index),
        );
        final selected = available.length <= _targetChoiceCount
            ? available
            : _pickSubsetIncludingCorrect(
                available: available,
                correct: answerToken.value,
                seed: seed,
              );
        final answerIndex = selected.indexOf(answerToken.value);
        if (answerIndex < 0) return null;
        return _ReducedChoiceSet(
          choices: selected,
          answer: String.fromCharCode(65 + answerIndex),
        );
    }
  }

  int _resolveNumericOptionCount({
    required int? rawOptionCount,
    required int correctValue,
  }) {
    final configured = rawOptionCount ?? 9;
    final bounded = configured.clamp(2, 26).toInt();
    if (correctValue > bounded) {
      return correctValue.clamp(2, 26).toInt();
    }
    return bounded;
  }

  int _resolveLetterOptionCount({
    required int? rawOptionCount,
    required int correctIndex,
  }) {
    final configured = rawOptionCount ?? 5;
    final bounded = configured.clamp(2, 26).toInt();
    if (correctIndex > bounded) {
      return correctIndex.clamp(2, 26).toInt();
    }
    return bounded;
  }

  List<String> _pickSubsetIncludingCorrect({
    required List<String> available,
    required String correct,
    required int seed,
  }) {
    final random = Random(seed * 97 + correct.hashCode * 31 + available.length);
    final distractors = available.where((value) => value != correct).toList()
      ..shuffle(random);
    final selected = <String>[
      correct,
      ...distractors.take(_targetChoiceCount - 1),
    ]..shuffle(random);
    return selected;
  }

  String _normalizeVisualPrompt(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return '';

    final lower = text.toLowerCase();
    if (lower == 'choose the correct answer.' ||
        lower == 'choose the correct answer') {
      return '';
    }

    return text;
  }
}

enum _AnswerKind { numeric, letter }

class _AnswerToken {
  final _AnswerKind kind;
  final String value;

  const _AnswerToken._(this.kind, this.value);

  const _AnswerToken.numeric(int value) : this._(_AnswerKind.numeric, '$value');

  const _AnswerToken.letter(String value) : this._(_AnswerKind.letter, value);
}

class _ReducedChoiceSet {
  final List<String> choices;
  final String answer;

  const _ReducedChoiceSet({
    required this.choices,
    required this.answer,
  });
}

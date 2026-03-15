import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final String apiKey;
  late final GenerativeModel model;

  GeminiService({required this.apiKey}) {
    model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
    );
  }

  Future<String> getExplanation({
    required String question,
    required List<String> choices,
    required String userAnswer,
    required String correctAnswer,
  }) async {
    try {
      // Build choices string (a) choice1, b) choice2, etc.
      final choicesStr = choices.asMap().entries.map((e) {
        final letter = String.fromCharCode(97 + e.key); // a, b, c, d
        return '$letter) ${e.value}';
      }).join(', ');

      // Resolve answer letters from either letter input (A/B/C/D) or full choice text.
      String _resolveAnswerLetter(String value) {
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

      final userAnswerLetter = _resolveAnswerLetter(userAnswer);
      final correctAnswerLetter = _resolveAnswerLetter(correctAnswer);
      final userAnswerFeedback = userAnswerLetter != correctAnswerLetter && userAnswerLetter != 'unknown'
          ? ' You selected $userAnswerLetter, which is incorrect because it misses the key point that applies to option $correctAnswerLetter.'
          : '';

      final prompt = '''The question is: $question
The choices given are: $choicesStr
The given correct answer is $correctAnswerLetter) $correctAnswer.
User selected: $userAnswerLetter) $userAnswer.

Provide a brief, UPCAT-relevant explanation for why this is the correct choice.
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

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        return 'Unable to generate explanation. Please try again.';
      }

      return response.text!.trim();
    } catch (e) {
      final errorMsg = e.toString().toLowerCase();
      
      // Check for rate limiting or service availability issues
      if (errorMsg.contains('429') || errorMsg.contains('quota') || errorMsg.contains('rate limit')) {
        return '⚠️ Service temporarily busy (rate limit). Please wait a moment and try again.';
      } else if (errorMsg.contains('503') || errorMsg.contains('unavailable') || errorMsg.contains('service')) {
        return '⚠️ Gemini is currently experiencing high demand. Please try again later.';
      } else if (errorMsg.contains('timeout') || errorMsg.contains('deadline')) {
        return '⚠️ Request timed out. The AI service is slow. Please try again.';
      } else if (errorMsg.contains('connection') || errorMsg.contains('network')) {
        return '⚠️ Network connection error. Please check your internet and try again.';
      }
      
      return 'Error generating explanation: Please try again.';
    }
  }
}

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';

class GptService {
  final String apiKey;

  GptService({required this.apiKey});

  Future<String> getBetterExplanation({
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
      final userAnswerFeedback = userAnswerLetter != correctAnswerLetter &&
              userAnswerLetter != 'unknown'
          ? ' You selected $userAnswerLetter, which is incorrect because it misses the key point that applies to option $correctAnswerLetter.'
          : '';

      final prompt = '''The question is: $question
The choices given are: $choicesStr
The given correct answer is $correctAnswerLetter) $correctAnswer.
User selected: $userAnswerLetter) $userAnswer.

Provide a brief, USTET-relevant explanation for why this is the correct choice.
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

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'max_tokens': 500,
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final content =
            jsonResponse['choices'][0]['message']['content'] as String;
        return content.trim();
      } else if (response.statusCode == 429) {
        return '⚠️ Explanation service is currently busy. Please wait a moment and try again.';
      } else if (response.statusCode == 503 || response.statusCode == 502) {
        return '⚠️ Explanation service is currently unavailable. Please try again later.';
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return '⚠️ Authentication error. Please check API configuration.';
      } else if (response.statusCode >= 500) {
        return '⚠️ Service error. Please try again.';
      } else {
        return '⚠️ Error: ${response.statusCode}. Please try again.';
      }
    } on SocketException {
      return '⚠️ Network connection error. Please check your internet and try again.';
    } on TimeoutException {
      return '⚠️ Request timed out. Please try again.';
    } catch (e) {
      final errorMsg = e.toString().toLowerCase();

      if (errorMsg.contains('timeout') || errorMsg.contains('deadline')) {
        return '⚠️ Request timed out. Please try again.';
      } else if (errorMsg.contains('connection') ||
          errorMsg.contains('network')) {
        return '⚠️ Network connection error. Please check your internet and try again.';
      }

      return 'Unable to prepare explanation. Please try again.';
    }
  }
}

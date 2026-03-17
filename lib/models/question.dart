class Question {
  final int number;
  final String category;
  final String question;
  final List<String> choices;
  final String answer;
  final String? explanation; // ✅ optional now
  final String? source; // 'deepseek' or 'gemini'

  Question({
    required this.number,
    required this.category,
    required this.question,
    required this.choices,
    required this.answer,
    this.explanation,
    this.source,
  });

  // Shuffle choices and update answer to match new position
  Question shuffled() {
    // Get the correct answer text
    final correctIndex = answer.codeUnitAt(0) - 65; // A=0, B=1, C=2, D=3
    if (correctIndex < 0 || correctIndex >= choices.length) {
      return this; // Invalid answer, return unchanged
    }
    final correctText = choices[correctIndex];

    // Shuffle the choices
    final shuffledChoices = List<String>.from(choices)..shuffle();

    // Find new position of correct answer
    final newCorrectIndex = shuffledChoices.indexOf(correctText);
    final newAnswer = String.fromCharCode(65 + newCorrectIndex); // 0=A, 1=B, 2=C, 3=D

    return Question(
      number: number,
      category: category,
      question: question,
      choices: shuffledChoices,
      answer: newAnswer,
      explanation: explanation,
      source: source,
    );
  }

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      number: json['number'],
      category: json['category'],
      question: json['question'],
      choices: List<String>.from(json['choices']),
      answer: json['answer'],
      explanation: json['explanation'], // may be null
      source: json['source'] as String?,
    );
  }
}
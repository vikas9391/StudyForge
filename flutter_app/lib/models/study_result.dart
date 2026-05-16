// lib/models/study_result.dart
// Data models for API responses.

class QuizQuestion {
  final String question;
  final List<String> options;
  final String answer;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
    question: j['question'] as String? ?? '',
    options:  List<String>.from(j['options'] as List? ?? []),
    answer:   j['answer']  as String? ?? 'A',
  );
}

class Flashcard {
  final String front;
  final String back;

  Flashcard({required this.front, required this.back});

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
    front: j['front'] as String? ?? '',
    back:  j['back']  as String? ?? '',
  );
}

class StudyResult {
  final String resultId;
  final String summary;
  final String fileUrl;
  final List<QuizQuestion> quiz;
  final List<Flashcard> flashcards;

  StudyResult({
    required this.resultId,
    required this.summary,
    required this.fileUrl,
    required this.quiz,
    required this.flashcards,
  });

  factory StudyResult.fromJson(Map<String, dynamic> j) => StudyResult(
    resultId:   j['result_id'] as String? ?? '',
    summary:    j['summary']   as String? ?? '',
    fileUrl:    j['file_url']  as String? ?? '',
    quiz: (j['quiz'] as List? ?? [])
        .map((q) => QuizQuestion.fromJson(q as Map<String, dynamic>))
        .toList(),
    flashcards: (j['flashcards'] as List? ?? [])
        .map((c) => Flashcard.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

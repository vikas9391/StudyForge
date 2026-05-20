// lib/models/study_result.dart
// Data models for API responses.
// V3 additions: SrCard, QuizAttempt, WeakTopic, PublicSession

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
        options: List<String>.from(j['options'] as List? ?? []),
        answer: j['answer'] as String? ?? 'A',
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'answer': answer,
      };
}

class Flashcard {
  final String front;
  final String back;

  Flashcard({required this.front, required this.back});

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'front': front, 'back': back};
}

class StudyResult {
  final String resultId;
  final String summary;
  final String fileUrl;
  final String fileName;
  final DateTime? createdAt;
  final List<QuizQuestion> quiz;
  final List<Flashcard> flashcards;
  // V3
  final bool isPublic;
  final int cloneCount;
  final String? clonedFrom;

  StudyResult({
    required this.resultId,
    required this.summary,
    required this.fileUrl,
    required this.fileName,
    required this.createdAt,
    required this.quiz,
    required this.flashcards,
    this.isPublic = false,
    this.cloneCount = 0,
    this.clonedFrom,
  });

  factory StudyResult.fromJson(Map<String, dynamic> j) {
    final fileUrl = j['file_url'] as String? ?? '';
    String fileName = j['file_name'] as String? ?? '';
    if (fileName.isEmpty && fileUrl.isNotEmpty) {
      final uri = Uri.tryParse(fileUrl);
      final segments = uri?.pathSegments ?? [];
      if (segments.isNotEmpty) {
        final raw = Uri.decodeComponent(segments.last);
        fileName = raw.replaceFirst(RegExp(r'^\d+_'), '').replaceAll('+', ' ').trim();
      }
    }
    DateTime? createdAt;
    final rawDate = j['created_at'] as String?;
    if (rawDate != null && rawDate.isNotEmpty) {
      createdAt = DateTime.tryParse(rawDate)?.toLocal();
    }
    return StudyResult(
      resultId: j['result_id'] as String? ?? j['id'] as String? ?? '',
      summary: j['summary'] as String? ?? '',
      fileUrl: fileUrl,
      fileName: fileName,
      createdAt: createdAt,
      quiz: (j['quiz'] as List? ?? [])
          .map((q) => QuizQuestion.fromJson(q as Map<String, dynamic>))
          .toList(),
      flashcards: (j['flashcards'] as List? ?? [])
          .map((c) => Flashcard.fromJson(c as Map<String, dynamic>))
          .toList(),
      isPublic: j['is_public'] as bool? ?? false,
      cloneCount: j['clone_count'] as int? ?? 0,
      clonedFrom: j['cloned_from'] as String?,
    );
  }

  String displayName(int fallbackIndex) {
    if (fileName.isNotEmpty) return fileName;
    return 'Session ${fallbackIndex + 1}';
  }

  String get relativeTime {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d ${d == 1 ? 'day' : 'days'} ago';
    }
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return '$w ${w == 1 ? 'week' : 'weeks'} ago';
    }
    final mo = (diff.inDays / 30).floor();
    return '$mo ${mo == 1 ? 'month' : 'months'} ago';
  }

  bool get isPending => summary.isEmpty || summary.trim() == '__pending__';
}

// ── V3: Spaced Repetition ──────────────────────────────────────────────────

class SrCard {
  final String id;
  final int cardIndex;
  final String front;
  final String back;
  final String dueDate;
  final int interval;
  final int repetitions;
  final int lastQuality;

  const SrCard({
    required this.id,
    required this.cardIndex,
    required this.front,
    required this.back,
    required this.dueDate,
    required this.interval,
    required this.repetitions,
    required this.lastQuality,
  });

  factory SrCard.fromJson(Map<String, dynamic> j) => SrCard(
        id: j['id'] as String? ?? '',
        cardIndex: j['card_index'] as int? ?? 0,
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
        dueDate: j['due_date'] as String? ?? '',
        interval: j['interval'] as int? ?? 1,
        repetitions: j['repetitions'] as int? ?? 0,
        lastQuality: j['last_quality'] as int? ?? -1,
      );

  bool get isNew => repetitions == 0;
  bool get isMastered => interval >= 21;
}

class SrSession {
  final String resultId;
  final String sessionName;
  final List<SrCard> cards;

  const SrSession({
    required this.resultId,
    required this.sessionName,
    required this.cards,
  });

  factory SrSession.fromJson(Map<String, dynamic> j) => SrSession(
        resultId: j['result_id'] as String? ?? '',
        sessionName: j['session_name'] as String? ?? '',
        cards: (j['cards'] as List? ?? [])
            .map((c) => SrCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

// ── V3: Analytics ──────────────────────────────────────────────────────────

class WeakTopic {
  final String topic;
  final int total;
  final int correct;
  final int wrong;
  final double errorRate;

  const WeakTopic({
    required this.topic,
    required this.total,
    required this.correct,
    required this.wrong,
    required this.errorRate,
  });

  factory WeakTopic.fromJson(Map<String, dynamic> j) => WeakTopic(
        topic: j['topic'] as String? ?? '',
        total: j['total'] as int? ?? 0,
        correct: j['correct'] as int? ?? 0,
        wrong: j['wrong'] as int? ?? 0,
        errorRate: (j['error_rate'] as num? ?? 0).toDouble(),
      );
}

class AccuracyPoint {
  final String date;
  final int pct;
  final int attempts;

  const AccuracyPoint({
    required this.date,
    required this.pct,
    required this.attempts,
  });

  factory AccuracyPoint.fromJson(Map<String, dynamic> j) => AccuracyPoint(
        date: j['date'] as String? ?? '',
        pct: j['pct'] as int? ?? 0,
        attempts: j['attempts'] as int? ?? 0,
      );
}

// ── V3: Public session (browse list item) ──────────────────────────────────

class PublicSession {
  final String id;
  final String fileName;
  final String summarySneek; // first 200 chars
  final int quizCount;
  final int cardCount;
  final int cloneCount;
  final String? createdAt;

  const PublicSession({
    required this.id,
    required this.fileName,
    required this.summarySneek,
    required this.quizCount,
    required this.cardCount,
    required this.cloneCount,
    this.createdAt,
  });

  factory PublicSession.fromJson(Map<String, dynamic> j) => PublicSession(
        id: j['id'] as String? ?? '',
        fileName: j['file_name'] as String? ?? 'Untitled',
        summarySneek: j['summary'] as String? ?? '',
        quizCount: j['quiz_count'] as int? ?? 0,
        cardCount: j['card_count'] as int? ?? 0,
        cloneCount: j['clone_count'] as int? ?? 0,
        createdAt: j['created_at'] as String?,
      );
}
// lib/screens/results_screen.dart  (V3)
// V3 additions:
//  ✅ Manual flashcard editor — add, edit, delete cards inline
//  ✅ SR initialisation — "Start SR Deck" button initialises spaced repetition
//  ✅ Quiz attempt recording — submitting quiz calls POST /analytics/quiz-attempt
//  ✅ Share toggle — make session public/private from the app bar menu

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/study_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../main.dart' show slideRoute;
import 'sr_review_screen.dart';

class ResultsScreen extends StatefulWidget {
  final String resultId;
  const ResultsScreen({super.key, required this.resultId});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  final _api  = ApiService();
  final _auth = AuthService();
  late TabController _tabs;

  StudyResult? _result;
  bool    _loading  = true;
  String? _error;

  // V3 — mutable flashcards list (so edits are reflected immediately)
  List<Flashcard> _flashcards = [];
  bool _isPublic = false;
  bool _togglingVisibility = false;
  bool _initingSr = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _fetchResult();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetchResult() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _api.getResult(widget.resultId);
      if (mounted) {
        setState(() {
          _result     = r;
          _flashcards = List.from(r.flashcards);
          _isPublic   = r.isPublic;
          _loading    = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── V3: toggle visibility ─────────────────────────────────────────────────

  Future<void> _toggleVisibility() async {
    setState(() => _togglingVisibility = true);
    try {
      final newVal = !_isPublic;
      await _api.setSessionVisibility(widget.resultId, newVal);
      if (mounted) {
        setState(() { _isPublic = newVal; _togglingVisibility = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newVal
              ? 'Session is now public — others can clone it.'
              : 'Session is now private.',
              style: TextStyle(color: AppColors.textPrimary)),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.border)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _togglingVisibility = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.accentRed,
        ));
      }
    }
  }

  // ── V3: init SR deck ──────────────────────────────────────────────────────

  Future<void> _initSrDeck() async {
    final uid = _auth.userId;
    if (uid == null || _result == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _initingSr = true);
    try {
      await _api.initSrCards(
        resultId: widget.resultId,
        userId: uid,
        cards: _flashcards,
      );
      if (!mounted) return;
      setState(() => _initingSr = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('SR deck ready! ${_flashcards.length} cards added.',
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        action: SnackBarAction(
          label: 'Review now',
          textColor: AppColors.primary,
          onPressed: () => Navigator.of(context).push(
              slideRoute(const SrReviewScreen())),
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _initingSr = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.accentRed,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: BackButton(color: AppColors.textSecond),
        title: Text('Study Materials', style: AppText.subheading),
        actions: [
          if (!_loading && _error == null) ...[
            // Share toggle
            if (_togglingVisibility)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
              )
            else
              IconButton(
                icon: Icon(
                  _isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
                  color: _isPublic ? AppColors.accentGreen : AppColors.textSecond,
                  size: 20,
                ),
                tooltip: _isPublic ? 'Public — tap to make private' : 'Private — tap to share',
                onPressed: _toggleVisibility,
              ),
          ],
        ],
        bottom: (_loading || _error != null)
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabs,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        gradient: AppColors.primaryGrad,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 8)],
                      ),
                      labelStyle: AppText.label.copyWith(color: Colors.white, letterSpacing: 0.2),
                      unselectedLabelStyle: AppText.label,
                      tabs: const [
                        Tab(text: 'Summary'),
                        Tab(text: 'Quiz'),
                        Tab(text: 'Flashcards'),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2.5))
            : _error != null
                ? _buildError()
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _SummaryTab(summary: _result!.summary),
                      _QuizTab(
                        questions:  _result!.quiz,
                        resultId:   widget.resultId,
                        sessionName: _result!.displayName(0),
                        userId:     _auth.userId ?? '',
                        api:        _api,
                      ),
                      _FlashcardsTab(
                        flashcards: _flashcards,
                        onChanged:  (updated) => setState(() => _flashcards = updated),
                        onInitSr:   _initingSr ? null : _initSrDeck,
                        initingSr:  _initingSr,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.accentRed),
        const SizedBox(height: 16),
        Text('Could not load results', style: AppText.subheading),
        const SizedBox(height: 8),
        Text(_error!, style: AppText.caption, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _fetchResult,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SUMMARY TAB
// ══════════════════════════════════════════════════════════════════════════════

class _SummaryTab extends StatelessWidget {
  final String summary;
  const _SummaryTab({required this.summary});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.summarize_rounded,
                color: AppColors.accentBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Summary',
                style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
            Text('Auto-generated from your document', style: AppText.caption),
          ]),
        ]),
        const SizedBox(height: 16),
        const Divider(color: AppColors.borderLight, height: 1),
        const SizedBox(height: 16),
        Text(summary.isEmpty ? 'No summary was generated.' : summary,
            style: AppText.bodySmall.copyWith(color: AppColors.textBody, height: 1.8)),
      ]),
    ).animate().fadeIn(),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// QUIZ TAB — V3: records attempt to analytics endpoint
// ══════════════════════════════════════════════════════════════════════════════

class _QuizTab extends StatefulWidget {
  final List<QuizQuestion> questions;
  final String resultId;
  final String sessionName;
  final String userId;
  final ApiService api;

  const _QuizTab({
    required this.questions,
    required this.resultId,
    required this.sessionName,
    required this.userId,
    required this.api,
  });

  @override
  State<_QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<_QuizTab> {
  final Map<int, String> _selected = {};
  bool _submitted  = false;
  bool _recording  = false;
  int _currentStreak = 0;
  int _bestStreak    = 0;

  int get _score => _selected.entries
      .where((e) => e.value == widget.questions[e.key].answer)
      .length;

  Future<void> _submit() async {
    int streak = 0, best = 0;
    final answers = <Map<String, dynamic>>[];

    for (var i = 0; i < widget.questions.length; i++) {
      final q         = widget.questions[i];
      final userAns   = _selected[i] ?? '';
      final isCorrect = userAns == q.answer;
      if (isCorrect) { streak++; if (streak > best) best = streak; }
      else streak = 0;

      answers.add({
        'question':       q.question,
        'correct_answer': q.answer,
        'user_answer':    userAns,
        'is_correct':     isCorrect,
        'topic_hint':     q.question.split(' ').take(4).join(' '),
      });
    }

    setState(() {
      _submitted     = true;
      _currentStreak = streak;
      _bestStreak    = best;
    });

    // V3: record attempt (fire-and-forget — non-blocking)
    if (widget.userId.isNotEmpty) {
      setState(() => _recording = true);
      widget.api.recordQuizAttempt(
        userId:      widget.userId,
        resultId:    widget.resultId,
        sessionName: widget.sessionName,
        score:       _score,
        total:       widget.questions.length,
        answers:     answers,
      ).whenComplete(() { if (mounted) setState(() => _recording = false); });
    }
  }

  void _reset() => setState(() {
    _selected.clear();
    _submitted = false;
    _currentStreak = 0;
    _bestStreak = 0;
  });

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Center(child: Text('No quiz questions generated.', style: AppText.caption));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_submitted) _buildLiveTracker(),
        if (_submitted) ...[
          _buildProgressRing(),
          const SizedBox(height: 14),
          _buildStreakRow(),
          const SizedBox(height: 14),
        ],

        ...widget.questions.asMap().entries.map((e) => _buildQuestion(e.key, e.value)),
        const SizedBox(height: 8),

        GestureDetector(
          onTap: () => _submitted ? _reset() : _submit(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 52,
            decoration: BoxDecoration(
              gradient: _submitted ? null : AppColors.primaryGrad,
              color: _submitted ? AppColors.accentGreen.withOpacity(0.12) : null,
              borderRadius: BorderRadius.circular(14),
              border: _submitted ? Border.all(color: AppColors.accentGreen) : null,
              boxShadow: _submitted ? []
                  : [BoxShadow(color: AppColors.primaryGlow, blurRadius: 16)],
            ),
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_recording) ...[
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 8),
                ],
                Text(
                  _submitted ? '↺  Try Again' : 'Submit Answers',
                  style: AppText.body.copyWith(
                    color: _submitted ? AppColors.accentGreen : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildLiveTracker() {
    final answered = _selected.length;
    final total    = widget.questions.length;
    final correct  = _selected.entries
        .where((e) => e.value == widget.questions[e.key].answer)
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        _TrackerPill(icon: Icons.edit_note_rounded,
            label: '$answered / $total answered', color: AppColors.primary),
        if (answered > 0) ...[
          const SizedBox(width: 8),
          _TrackerPill(icon: Icons.check_circle_outline_rounded,
              label: '$correct correct', color: AppColors.accentGreen),
          const SizedBox(width: 8),
          _TrackerPill(icon: Icons.cancel_outlined,
              label: '${answered - correct} wrong', color: AppColors.accentRed),
        ],
      ]),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildProgressRing() {
    final total = widget.questions.length;
    final pct   = total > 0 ? _score / total : 0.0;
    final color = pct >= 0.7 ? AppColors.accentGreen
        : pct >= 0.4 ? AppColors.accentAmber : AppColors.accentRed;
    final emoji = pct >= 0.8 ? '🎉' : pct >= 0.5 ? '👍' : '📚';
    final msg   = pct >= 0.8 ? 'Excellent work!'
        : pct >= 0.5 ? 'Good effort!' : 'Keep studying!';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: pct),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, value, __) => SizedBox(
            width: 80, height: 80,
            child: CustomPaint(
              painter: _RingPainter(
                progress: value, color: color,
                trackColor: color.withOpacity(0.15),
              ),
              child: Center(child: Text(
                '${(value * 100).round()}%',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
              )),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text('$_score / $total correct',
              style: AppText.subheading.copyWith(color: color)),
          Text(msg, style: AppText.caption),
        ])),
      ]),
    ).animate().scale(duration: 450.ms, curve: Curves.elasticOut,
        begin: const Offset(0.85, 0.85));
  }

  Widget _buildStreakRow() {
    if (_bestStreak < 2) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentAmber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentAmber.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Text('🔥', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Best streak: $_bestStreak in a row',
              style: AppText.bodySmall.copyWith(
                  fontWeight: FontWeight.w700, color: AppColors.accentAmber)),
          if (_currentStreak >= 2)
            Text('Ended with $_currentStreak correct ⚡',
                style: AppText.caption.copyWith(
                    color: AppColors.accentAmber.withOpacity(0.8))),
        ]),
      ]),
    ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.05);
  }

  Widget _buildQuestion(int i, QuizQuestion q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.12),
            ),
            child: Center(child: Text('${i + 1}',
                style: AppText.label.copyWith(color: AppColors.primary))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(q.question,
              style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),
        ...q.options.map((opt) {
          final letter     = opt.isNotEmpty ? opt[0] : '';
          final isSelected = _selected[i] == letter;
          final isCorrect  = q.answer == letter;
          Color bgColor  = AppColors.surface;
          Color brdColor = AppColors.border;
          Color txtColor = AppColors.textPrimary;
          Widget? trailIcon;

          if (_submitted) {
            if (isCorrect) {
              bgColor  = AppColors.accentGreen.withOpacity(0.10);
              brdColor = AppColors.accentGreen; txtColor = AppColors.accentGreen;
              trailIcon = const Icon(Icons.check_circle_rounded,
                  color: AppColors.accentGreen, size: 16);
            } else if (isSelected) {
              bgColor  = AppColors.accentRed.withOpacity(0.08);
              brdColor = AppColors.accentRed; txtColor = AppColors.accentRed;
              trailIcon = const Icon(Icons.cancel_rounded,
                  color: AppColors.accentRed, size: 16);
            }
          } else if (isSelected) {
            bgColor  = AppColors.primary.withOpacity(0.10);
            brdColor = AppColors.primary; txtColor = AppColors.primaryLight;
          }

          final displayText = opt.length > 2 ? opt.substring(3) : opt;
          return GestureDetector(
            onTap: _submitted ? null : () => setState(() => _selected[i] = letter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: bgColor, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brdColor),
              ),
              child: Row(children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(5)),
                  child: Center(child: Text(letter,
                      style: AppText.label.copyWith(fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(displayText,
                    style: AppText.caption.copyWith(color: txtColor))),
                if (trailIcon != null) trailIcon,
              ]),
            ),
          );
        }),
      ]),
    ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.08);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FLASHCARDS TAB — V3: manual editor + SR init button
// ══════════════════════════════════════════════════════════════════════════════

class _FlashcardsTab extends StatefulWidget {
  final List<Flashcard> flashcards;
  final ValueChanged<List<Flashcard>> onChanged;
  final VoidCallback? onInitSr;
  final bool initingSr;

  const _FlashcardsTab({
    required this.flashcards,
    required this.onChanged,
    required this.onInitSr,
    required this.initingSr,
  });

  @override
  State<_FlashcardsTab> createState() => _FlashcardsTabState();
}

class _FlashcardsTabState extends State<_FlashcardsTab> {
  bool _editMode = false;

  void _addCard() {
    final updated = List<Flashcard>.from(widget.flashcards)
      ..add(Flashcard(front: '', back: ''));
    widget.onChanged(updated);
  }

  void _deleteCard(int i) {
    final updated = List<Flashcard>.from(widget.flashcards)..removeAt(i);
    widget.onChanged(updated);
  }

  void _editCard(int i) async {
    final card = widget.flashcards[i];
    final frontCtrl = TextEditingController(text: card.front);
    final backCtrl  = TextEditingController(text: card.back);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(i < widget.flashcards.length - 1 || card.front.isNotEmpty
            ? 'Edit card' : 'Add card',
            style: TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _CardField(ctrl: frontCtrl, label: 'Term / Question'),
          const SizedBox(height: 12),
          _CardField(ctrl: backCtrl,  label: 'Definition / Answer', maxLines: 3),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: AppColors.textSecond))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Save', style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (saved == true && mounted) {
      final updated = List<Flashcard>.from(widget.flashcards);
      updated[i] = Flashcard(front: frontCtrl.text.trim(), back: backCtrl.text.trim());
      widget.onChanged(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header bar
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(
            child: Text(
              _editMode
                  ? 'Edit mode — tap a card to change it'
                  : 'Tap a card to flip',
              style: AppText.label.copyWith(color: AppColors.textMuted),
            ),
          ),
          // SR init button
          if (!_editMode)
            GestureDetector(
              onTap: widget.onInitSr,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accentGreen.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.initingSr)
                    const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: AppColors.accentGreen))
                  else
                    const Icon(Icons.repeat_rounded,
                        size: 13, color: AppColors.accentGreen),
                  const SizedBox(width: 5),
                  Text(widget.initingSr ? 'Adding…' : 'Add to SR deck',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: AppColors.accentGreen)),
                ]),
              ),
            ),
          const SizedBox(width: 8),
          // Edit toggle
          GestureDetector(
            onTap: () => setState(() => _editMode = !_editMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _editMode ? AppColors.primaryGlow : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _editMode
                    ? AppColors.primary.withOpacity(0.3) : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_editMode ? Icons.check_rounded : Icons.edit_rounded,
                    size: 13,
                    color: _editMode ? AppColors.primary : AppColors.textSecond),
                const SizedBox(width: 5),
                Text(_editMode ? 'Done' : 'Edit',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: _editMode ? AppColors.primary : AppColors.textSecond)),
              ]),
            ),
          ),
        ]),
      ),

      Expanded(
        child: widget.flashcards.isEmpty
            ? _buildEmptyCards()
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.88,
                ),
                itemCount: widget.flashcards.length + (_editMode ? 1 : 0),
                itemBuilder: (ctx, i) {
                  // "Add card" button at end in edit mode
                  if (_editMode && i == widget.flashcards.length) {
                    return GestureDetector(
                      onTap: () { _addCard(); _editCard(widget.flashcards.length); },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                              width: 1.5),
                        ),
                        child: const Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 32, color: AppColors.primary),
                            SizedBox(height: 6),
                            Text('Add card', style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                          ],
                        )),
                      ),
                    );
                  }

                  if (_editMode) {
                    return _EditableCardTile(
                      card: widget.flashcards[i],
                      index: i,
                      onEdit: () => _editCard(i),
                      onDelete: () => _deleteCard(i),
                    );
                  }

                  return _FlipCard(
                    card: widget.flashcards[i],
                    delay: Duration(milliseconds: i * 45),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildEmptyCards() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.style_outlined, size: 40, color: AppColors.textMuted),
      const SizedBox(height: 12),
      Text('No flashcards yet', style: AppText.bodySmall),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () { setState(() => _editMode = true); _addCard(); _editCard(0); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGrad,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('Add a card',
              style: TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── Editable card tile (edit mode) ────────────────────────────────────────────

class _EditableCardTile extends StatelessWidget {
  final Flashcard card;
  final int       index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EditableCardTile({
    required this.card,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onEdit,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${index + 1}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.delete_outline_rounded,
                size: 16, color: AppColors.accentRed),
          ),
        ]),
        const SizedBox(height: 8),
        Text(card.front.isNotEmpty ? card.front : 'Tap to add term',
            maxLines: 3, overflow: TextOverflow.ellipsis,
            style: AppText.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: card.front.isNotEmpty ? AppColors.textPrimary : AppColors.textMuted,
            )),
        const Spacer(),
        Row(children: [
          const Icon(Icons.edit_rounded, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('tap to edit',
              style: AppText.label.copyWith(color: AppColors.textMuted, fontSize: 9)),
        ]),
      ]),
    ),
  );
}

// ── Card text field helper ────────────────────────────────────────────────────

class _CardField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final int maxLines;
  const _CardField({required this.ctrl, required this.label, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.textSecond),
      filled: true,
      fillColor: AppColors.bg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
    ),
  );
}

// ── Flip card (unchanged from V2) ────────────────────────────────────────────

class _FlipCard extends StatefulWidget {
  final Flashcard card;
  final Duration  delay;
  const _FlipCard({required this.card, required this.delay});

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 420));
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _flip() {
    if (_ctrl.isAnimating) return;
    _showBack ? _ctrl.reverse() : _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 210), () {
      if (mounted) setState(() => _showBack = !_showBack);
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _flip,
    child: AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final angle    = _anim.value * math.pi;
        final showBack = _anim.value >= 0.5;
        final faceAngle = showBack ? angle - math.pi : angle;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(faceAngle),
          child: showBack
              ? _FlashFace(text: widget.card.back, label: 'ANSWER',
                    color: AppColors.accentGreen, isBack: true)
              : _FlashFace(text: widget.card.front, label: 'TERM',
                    color: AppColors.primary, isBack: false),
        );
      },
    ),
  ).animate()
      .fadeIn(delay: widget.delay, duration: 350.ms)
      .scale(begin: const Offset(0.88, 0.88), delay: widget.delay, duration: 350.ms);
}

class _FlashFace extends StatelessWidget {
  final String text;
  final String label;
  final Color  color;
  final bool   isBack;
  const _FlashFace({required this.text, required this.label,
      required this.color, required this.isBack});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isBack ? AppColors.accentGreen.withOpacity(0.06) : AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.35), width: isBack ? 1.5 : 1),
      boxShadow: isBack
          ? [BoxShadow(color: color.withOpacity(0.07), blurRadius: 14)]
          : [],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: AppText.label.copyWith(color: color)),
      ),
      const Spacer(),
      Text(text,
          style: AppText.bodySmall.copyWith(
              fontWeight: isBack ? FontWeight.w400 : FontWeight.w700, height: 1.5),
          maxLines: 6, overflow: TextOverflow.ellipsis),
      const Spacer(),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Icon(isBack ? Icons.flip_to_front_rounded : Icons.flip_to_back_rounded,
            size: 12, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text('tap to flip',
            style: AppText.label.copyWith(color: AppColors.textMuted, fontSize: 9)),
      ]),
    ]),
  );
}

// ── Shared painters / widgets ─────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color  color;
  final Color  trackColor;
  const _RingPainter({required this.progress,
      required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r  = size.width / 2 - 6;
    const sw = 7.0;
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = trackColor..style = PaintingStyle.stroke..strokeWidth = sw);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
          -math.pi / 2, 2 * math.pi * progress, false,
          Paint()..color = color..style = PaintingStyle.stroke
            ..strokeWidth = sw..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

class _TrackerPill extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _TrackerPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}
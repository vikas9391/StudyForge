// lib/screens/results_screen.dart
// Results screen — tabbed view showing Summary, Quiz, and Flashcards.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/study_result.dart';
import '../services/api_service.dart';

class ResultsScreen extends StatefulWidget {
  final String resultId;
  const ResultsScreen({super.key, required this.resultId});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabs;

  StudyResult? _result;
  bool    _loading = true;
  String? _error;

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
      if (mounted) setState(() { _result = r; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.textSecond),
        title:   Text('Study Materials', style: AppText.subheading),
        // Pill-style tab bar embedded in AppBar
        bottom: (_loading || _error != null)
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color:        AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller:       _tabs,
                      dividerColor:     Colors.transparent,
                      indicator: BoxDecoration(
                        gradient:     AppColors.primaryGrad,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [
                          BoxShadow(
                            color:      AppColors.primaryGlow,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      labelStyle: AppText.label.copyWith(
                          color: Colors.white, letterSpacing: 0.2),
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
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2.5))
            : _error != null
                ? _buildError()
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _SummaryTab(summary: _result!.summary),
                      _QuizTab(questions: _result!.quiz),
                      _FlashcardsTab(flashcards: _result!.flashcards),
                    ],
                  ),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            size: 52, color: AppColors.accentRed),
        const SizedBox(height: 16),
        Text('Could not load results', style: AppText.subheading),
        const SizedBox(height: 8),
        Text(_error!, style: AppText.caption, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _fetchResult,
          icon:  const Icon(Icons.refresh_rounded),
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(children: [
            Container(
              width:  36,
              height: 36,
              decoration: BoxDecoration(
                color:        AppColors.accentBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.summarize_rounded,
                  color: AppColors.accentBlue, size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Summary',
                  style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
              Text('Auto-generated from your document',
                  style: AppText.caption),
            ]),
          ]),

          const SizedBox(height: 16),
          const Divider(color: AppColors.borderLight, height: 1),
          const SizedBox(height: 16),

          Text(
            summary.isEmpty ? 'No summary was generated.' : summary,
            style: AppText.bodySmall.copyWith(
              color:  AppColors.textBody,
              height: 1.8,
            ),
          ),
        ]),
      ).animate().fadeIn(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QUIZ TAB
// ══════════════════════════════════════════════════════════════════════════════

class _QuizTab extends StatefulWidget {
  final List<QuizQuestion> questions;
  const _QuizTab({required this.questions});

  @override
  State<_QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<_QuizTab> {
  final Map<int, String> _selected = {};
  bool _submitted = false;

  int get _score => _selected.entries
      .where((e) => e.value == widget.questions[e.key].answer)
      .length;

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Center(
          child: Text('No quiz questions generated.', style: AppText.caption));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // Score banner (after submission)
        if (_submitted) ...[
          _buildScoreBanner(),
          const SizedBox(height: 14),
        ],

        // Questions
        ...widget.questions.asMap().entries.map(
            (e) => _buildQuestion(e.key, e.value)),

        const SizedBox(height: 8),

        // Submit / Try Again button
        GestureDetector(
          onTap: () => setState(() {
            if (_submitted) {
              _selected.clear();
              _submitted = false;
            } else {
              _submitted = true;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 52,
            decoration: BoxDecoration(
              gradient: _submitted ? null : AppColors.primaryGrad,
              color:    _submitted
                  ? AppColors.accentGreen.withOpacity(0.12)
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: _submitted
                  ? Border.all(color: AppColors.accentGreen)
                  : null,
              boxShadow: _submitted
                  ? []
                  : [BoxShadow(
                      color: AppColors.primaryGlow, blurRadius: 16)],
            ),
            child: Center(
              child: Text(
                _submitted ? '↺  Try Again' : 'Submit Answers',
                style: AppText.body.copyWith(
                  color:      _submitted
                      ? AppColors.accentGreen
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildScoreBanner() {
    final total = widget.questions.length;
    final pct   = total > 0 ? _score / total : 0.0;
    final color = pct >= 0.7
        ? AppColors.accentGreen
        : pct >= 0.4
            ? AppColors.accentAmber
            : AppColors.accentRed;
    final emoji = pct >= 0.8 ? '🎉' : pct >= 0.5 ? '👍' : '📚';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 32)),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_score / $total correct',
              style: AppText.subheading.copyWith(color: color)),
          Text('${(pct * 100).round()}% accuracy',
              style: AppText.caption),
        ]),
      ]),
    ).animate().scale(duration: 400.ms, curve: Curves.elasticOut);
  }

  Widget _buildQuestion(int i, QuizQuestion q) {
    return Container(
      margin:   const EdgeInsets.only(bottom: 14),
      padding:  const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Question number + text
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width:  26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.12),
            ),
            child: Center(
              child: Text('${i + 1}',
                  style: AppText.label.copyWith(color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(q.question,
                style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
          ),
        ]),

        const SizedBox(height: 12),

        // Options
        ...q.options.map((opt) {
          final letter     = opt.isNotEmpty ? opt[0] : '';
          final isSelected = _selected[i] == letter;
          final isCorrect  = q.answer == letter;

          Color   bgColor   = AppColors.surface;
          Color   brdColor  = AppColors.border;
          Color   txtColor  = AppColors.textPrimary;
          Widget? trailIcon;

          if (_submitted) {
            if (isCorrect) {
              bgColor  = AppColors.accentGreen.withOpacity(0.10);
              brdColor = AppColors.accentGreen;
              txtColor = AppColors.accentGreen;
              trailIcon = const Icon(Icons.check_circle_rounded,
                  color: AppColors.accentGreen, size: 16);
            } else if (isSelected) {
              bgColor  = AppColors.accentRed.withOpacity(0.08);
              brdColor = AppColors.accentRed;
              txtColor = AppColors.accentRed;
              trailIcon = const Icon(Icons.cancel_rounded,
                  color: AppColors.accentRed, size: 16);
            }
          } else if (isSelected) {
            bgColor  = AppColors.primary.withOpacity(0.10);
            brdColor = AppColors.primary;
            txtColor = AppColors.primaryLight;
          }

          // Strip the "A. " prefix for cleaner display
          final displayText = opt.length > 2 ? opt.substring(3) : opt;

          return GestureDetector(
            onTap: _submitted
                ? null
                : () => setState(() => _selected[i] = letter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin:   const EdgeInsets.only(bottom: 8),
              padding:  const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color:        bgColor,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: brdColor),
              ),
              child: Row(children: [
                // Letter badge
                Container(
                  width:  22,
                  height: 22,
                  decoration: BoxDecoration(
                    color:        AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Center(
                    child: Text(letter,
                        style: AppText.label.copyWith(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(displayText,
                      style: AppText.caption.copyWith(color: txtColor)),
                ),
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
// FLASHCARDS TAB
// ══════════════════════════════════════════════════════════════════════════════

class _FlashcardsTab extends StatefulWidget {
  final List<Flashcard> flashcards;
  const _FlashcardsTab({required this.flashcards});

  @override
  State<_FlashcardsTab> createState() => _FlashcardsTabState();
}

class _FlashcardsTabState extends State<_FlashcardsTab> {
  final Set<int> _flipped = {};

  @override
  Widget build(BuildContext context) {
    if (widget.flashcards.isEmpty) {
      return Center(
          child: Text('No flashcards generated.', style: AppText.caption));
    }

    return Column(children: [
      // Hint text
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Text(
          'Tap a card to reveal the answer',
          style: AppText.label.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ),

      // Card grid
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:  2,
            crossAxisSpacing: 10,
            mainAxisSpacing:  10,
            childAspectRatio: 0.88,
          ),
          itemCount: widget.flashcards.length,
          itemBuilder: (ctx, i) {
            final card      = widget.flashcards[i];
            final isFlipped = _flipped.contains(i);

            return GestureDetector(
              onTap: () => setState(() {
                if (isFlipped) _flipped.remove(i); else _flipped.add(i);
              }),
              child: AnimatedSwitcher(
                duration:       const Duration(milliseconds: 380),
                switchInCurve:  Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: _FlashFace(
                  key:    ValueKey('${i}_$isFlipped'),
                  text:   isFlipped ? card.back : card.front,
                  label:  isFlipped ? 'ANSWER' : 'TERM',
                  color:  isFlipped
                      ? AppColors.accentGreen
                      : AppColors.primary,
                  isBack: isFlipped,
                ),
              ),
            ).animate()
                .fadeIn(delay: (i * 45).ms)
                .scale(begin: const Offset(0.88, 0.88));
          },
        ),
      ),
    ]);
  }
}

class _FlashFace extends StatelessWidget {
  final String text;
  final String label;
  final Color  color;
  final bool   isBack;

  const _FlashFace({
    super.key,
    required this.text,
    required this.label,
    required this.color,
    required this.isBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isBack
            ? AppColors.accentGreen.withOpacity(0.06)
            : AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.35),
          width: isBack ? 1.5 : 1,
        ),
        boxShadow: isBack
            ? [BoxShadow(
                color:      color.withOpacity(0.07),
                blurRadius: 14,
              )]
            : [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Label pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: AppText.label.copyWith(color: color),
          ),
        ),

        const Spacer(),

        // Card text
        Text(
          text,
          style: AppText.bodySmall.copyWith(
            fontWeight: isBack ? FontWeight.w400 : FontWeight.w700,
            height:     1.5,
          ),
          maxLines:  6,
          overflow:  TextOverflow.ellipsis,
        ),

        const Spacer(),

        // Flip hint
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Icon(
            isBack
                ? Icons.flip_to_front_rounded
                : Icons.flip_to_back_rounded,
            size:  12,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            'tap to flip',
            style: AppText.label.copyWith(
                color: AppColors.textMuted, fontSize: 9),
          ),
        ]),
      ]),
    );
  }
}

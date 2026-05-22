// lib/screens/shared_sessions_screen.dart
// Browse public study sessions shared by other users.
// Featured shelf (most cloned) + search + clone into own library.
// V2 — emojis replaced with icon badges

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/study_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../main.dart' show slideRoute;
import 'results_screen.dart';
import '../widgets/app_bottom_nav.dart';

class SharedSessionsScreen extends StatefulWidget {
  const SharedSessionsScreen({super.key});

  @override
  State<SharedSessionsScreen> createState() => _SharedSessionsScreenState();
}

class _SharedSessionsScreenState extends State<SharedSessionsScreen> {
  final _api        = ApiService();
  final _auth       = AuthService();
  final _searchCtrl = TextEditingController();

  List<PublicSession> _featured = [];
  List<PublicSession> _browse   = [];

  bool    _loading     = true;
  bool    _searching   = false;
  bool    _loadingMore = false;
  String? _error;
  int     _offset      = 0;
  final   _cloning     = <String>{};

  AppNavTab _currentTab = AppNavTab.community;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.getFeaturedSessions(),
        _api.browsePublicSessions(limit: 20, offset: 0),
      ]);
      if (mounted) {
        setState(() {
          _featured = results[0];
          _browse   = results[1];
          _offset   = 20;
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final results = await _api.browsePublicSessions(
          search: query.isEmpty ? null : query, limit: 20, offset: 0);
      if (mounted) setState(() { _browse = results; _offset = 20; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _api.browsePublicSessions(
          search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
          limit: 20, offset: _offset);
      if (mounted) {
        setState(() {
          _browse.addAll(more);
          _offset += more.length;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_searchCtrl.text.trim() == q) _search(q);
    });
  }

  Future<void> _clone(PublicSession session) async {
    final uid = _auth.userId;
    if (uid == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _cloning.add(session.id));
    try {
      final newId = await _api.cloneSession(resultId: session.id, userId: uid);
      if (!mounted) return;
      setState(() => _cloning.remove(session.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cloned to your library!',
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        action: SnackBarAction(
          label: 'Open',
          textColor: AppColors.primary,
          onPressed: () => Navigator.of(context).push(
              slideRoute(ResultsScreen(resultId: newId))),
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _cloning.remove(session.id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Clone failed: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.accentRed.withOpacity(0.85),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Community Sessions', style: AppText.subheading),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
              : _error != null
              ? _buildError()
              : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.primary,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildSearchBar()),

                if (_searchCtrl.text.isEmpty && _featured.isNotEmpty)
                  SliverToBoxAdapter(child: _buildFeaturedShelf()),

                SliverToBoxAdapter(child: _buildBrowseHeader()),

                if (_searching)
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_browse.isEmpty)
                  SliverToBoxAdapter(child: _buildEmpty())
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                        if (i == _browse.length) return _buildLoadMore();
                        return _buildSessionCard(_browse[i], i);
                      },
                      childCount: _browse.length + 1,
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: AppBottomNav(
              currentTab: _currentTab,
              onTabChanged: (tab) => setState(() => _currentTab = tab),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: Icon(Icons.people_outline_rounded,
              size: 30, color: AppColors.accentRed),
        ),
      ),
      const SizedBox(height: 16),
      Text('Could not load sessions', style: AppText.subheading),
      const SizedBox(height: 8),
      Text(_error!, textAlign: TextAlign.center, style: AppText.caption),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: _load, child: const Text('Retry')),
    ]),
  );

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: TextField(
      controller: _searchCtrl,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search public sessions…',
        hintStyle: TextStyle(color: AppColors.textSecond, fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.textSecond),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? GestureDetector(
          onTap: () { _searchCtrl.clear(); _search(''); },
          child: Icon(Icons.close_rounded, size: 16, color: AppColors.textSecond),
        )
            : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    ),
  ).animate().fadeIn();

  // ── Featured shelf — ⭐ emoji replaced with icon badge ───────────────────

  Widget _buildFeaturedShelf() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 0, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(children: [
          // ⭐ → icon badge
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.accentAmber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.star_rounded,
                  size: 16, color: AppColors.accentAmber),
            ),
          ),
          const SizedBox(width: 8),
          Text('Featured',
              style: AppText.subheading.copyWith(fontSize: 15)),
          const SizedBox(width: 6),
          Text('most cloned', style: AppText.caption),
        ]),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 20),
          itemCount: _featured.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _buildFeaturedCard(_featured[i], i),
        ),
      ),
    ]),
  );

  Widget _buildFeaturedCard(PublicSession s, int i) {
    final colors = [AppColors.primary, AppColors.accentGreen,
      AppColors.accentAmber, AppColors.accentBlue];
    final color = colors[i % colors.length];

    return GestureDetector(
      onTap: () => _clone(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.library_books_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            Text('${s.cloneCount} clones',
                style: TextStyle(fontSize: 11, color: color,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(s.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Row(children: [
            _MiniPill(label: '${s.quizCount}Q', color: color),
            const SizedBox(width: 6),
            _MiniPill(label: '${s.cardCount} cards', color: color),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.copy_all_rounded,
                  size: 12, color: Colors.white),
              const SizedBox(width: 5),
              const Text('Clone',
                  style: TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: i * 60))
        .slideX(begin: 0.1);
  }

  // ── Browse header ─────────────────────────────────────────────────────────

  Widget _buildBrowseHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Row(children: [
      Text('All Sessions',
          style: AppText.subheading.copyWith(fontSize: 15)),
      const SizedBox(width: 8),
      if (_browse.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primaryGlow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${_browse.length}+',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
        ),
    ]),
  );

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() => Padding(
    padding: const EdgeInsets.all(40),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppColors.primaryGlow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Icon(Icons.search_off_rounded,
                size: 26, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 14),
        Text('No sessions found', style: AppText.bodySmall),
        const SizedBox(height: 6),
        Text('Try a different search term.', style: AppText.caption),
      ]),
    ),
  );

  // ── Session card ──────────────────────────────────────────────────────────

  Widget _buildSessionCard(PublicSession s, int i) {
    final isCloning = _cloning.contains(s.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.library_books_rounded,
                    size: 20, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Row(children: [
                  _MiniPill(label: '${s.quizCount} Q',
                      color: AppColors.accentGreen),
                  const SizedBox(width: 6),
                  _MiniPill(label: '${s.cardCount} cards',
                      color: AppColors.accentAmber),
                  const SizedBox(width: 6),
                  _MiniPill(label: '${s.cloneCount} clones',
                      color: AppColors.primary),
                ]),
              ]),
            ),
          ]),

          if (s.summarySneek.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(s.summarySneek,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(height: 1.5)),
          ],

          const SizedBox(height: 12),
          GestureDetector(
            onTap: isCloning ? null : () => _clone(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isCloning ? null : AppColors.primaryGrad,
                color: isCloning ? AppColors.border : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isCloning)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                else
                  const Icon(Icons.copy_all_rounded,
                      size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(isCloning ? 'Cloning…' : 'Clone to my library',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: isCloning
                          ? AppColors.textSecond
                          : Colors.white,
                    )),
              ]),
            ),
          ),
        ]),
      ),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: 60 + i * 40))
        .slideY(begin: 0.06);
  }

  // ── Load more ─────────────────────────────────────────────────────────────

  Widget _buildLoadMore() => Padding(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: _loadingMore
          ? const CircularProgressIndicator(
          color: AppColors.primary, strokeWidth: 2)
          : TextButton(
        onPressed: _loadMore,
        child: Text('Load more',
            style: TextStyle(color: AppColors.primary)),
      ),
    ),
  );
}

// ── Mini pill chip ────────────────────────────────────────────────────────────

class _MiniPill extends StatelessWidget {
  final String label;
  final Color  color;
  const _MiniPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.20)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: color)),
  );
}

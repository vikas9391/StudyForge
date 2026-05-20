// lib/screens/home_screen.dart  — V3 DROP-IN
//
// Changes from the previous version (on top of V2 patch notes):
//
//  ✅ V3: Three new quick-action cards below the upload CTA
//        → Spaced Repetition  (SrReviewScreen)
//        → Analytics          (AnalyticsScreen)
//        → Community Sessions (SharedSessionsScreen)
//  ✅ V3: SR due-card count badge fetched on load and shown on the SR card
//  ✅ V3: Imports for three new screens added
//
// All previous V2 changes (offline banner, rename API, retry, isFirstUpload)
// are preserved unchanged.
//
// SEARCH FOR "✅ V3" to find every new/modified block.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../main.dart' show slideRoute;
import '../services/profile_service.dart';
import '../models/profile.dart';
import '../models/study_result.dart';
import 'upload_screen.dart';
import 'results_screen.dart';
import 'profile_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'sr_review_screen.dart';          // ✅ V3
import 'analytics_screen.dart';          // ✅ V3
import 'shared_sessions_screen.dart';    // ✅ V3

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth        = AuthService();
  final _api         = ApiService();
  final _profileSvc  = ProfileService();
  final _searchCtrl  = TextEditingController();
  final _scrollCtrl  = ScrollController();

  List<Map<String, dynamic>> _sessions         = [];
  List<StudyResult>          _parsed           = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  List<StudyResult>          _filteredParsed   = [];

  UserProfile? _userProfile;
  bool         _loading       = true;
  bool         _isAdmin       = false;
  bool         _searchVisible = false;
  String       _searchQuery   = '';

  DateTime? _lastSynced;

  Timer? _greetingTimer;
  String _greeting = '';

  bool _isOffline = false;

  final Map<String, bool> _retrying = {};

  // ✅ V3 — SR due count for badge
  int _srDueCount = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _greeting = _computeGreeting();
    _loadData();
    _startGreetingTimer();
    _searchCtrl.addListener(_onSearchChanged);

    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Greeting timer ────────────────────────────────────────────────────────

  void _startGreetingTimer() {
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final next = _computeGreeting();
      if (next != _greeting && mounted) setState(() => _greeting = next);
    });
  }

  String _computeGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q == _searchQuery) return;
    setState(() { _searchQuery = q; _applyFilter(); });
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredSessions = List.from(_sessions);
      _filteredParsed   = List.from(_parsed);
    } else {
      _filteredSessions = [];
      _filteredParsed   = [];
      for (var i = 0; i < _parsed.length; i++) {
        final name    = _parsed[i].displayName(i).toLowerCase();
        final summary = _parsed[i].summary.toLowerCase();
        if (name.contains(_searchQuery) || summary.contains(_searchQuery)) {
          _filteredSessions.add(_sessions[i]);
          _filteredParsed.add(_parsed[i]);
        }
      }
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final uid = _auth.userId;
      if (uid != null) {
        // ✅ V3 — load SR due count alongside existing data
        final results = await Future.wait([
          _api.getUserResults(uid),
          _profileSvc.getProfile(uid),
          _api.getDueCards(uid),           // ✅ V3
        ]);
        if (mounted) {
          final sessions   = results[0] as List<Map<String, dynamic>>;
          final dueSessions = results[2] as List<SrSession>;          // ✅ V3
          final dueCount   = dueSessions.fold<int>(                   // ✅ V3
              0, (sum, s) => sum + s.cards.length);

          setState(() {
            _sessions     = sessions;
            _parsed       = sessions.map((r) => StudyResult.fromJson(r)).toList();
            _userProfile  = results[1] as UserProfile;
            _isAdmin      = _userProfile!.isAdmin;
            _lastSynced   = DateTime.now();
            _srDueCount   = dueCount;                                 // ✅ V3
            _applyFilter();
          });
        }
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Delete session ────────────────────────────────────────────────────────

  Future<void> _deleteSession(int filteredIndex) async {
    HapticFeedback.mediumImpact();
    final masterIndex = _sessions.indexOf(_filteredSessions[filteredIndex]);
    if (masterIndex < 0) return;

    final removedRaw    = _sessions[masterIndex];
    final removedParsed = _parsed[masterIndex];
    final id = removedRaw['result_id'] as String? ??
        removedRaw['id']        as String? ?? '';
    if (id.isEmpty) return;

    setState(() {
      _sessions.removeAt(masterIndex);
      _parsed.removeAt(masterIndex);
      _applyFilter();
    });

    try {
      await _api.deleteResult(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Session deleted',
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:         BorderSide(color: AppColors.border),
        ),
        margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ));
    } catch (_) {
      if (mounted) {
        setState(() {
          _sessions.insert(masterIndex, removedRaw);
          _parsed.insert(masterIndex, removedParsed);
          _applyFilter();
        });
      }
    }
  }

  // ── Rename session ────────────────────────────────────────────────────────

  Future<void> _renameSession(int filteredIndex) async {
    final masterIndex = _sessions.indexOf(_filteredSessions[filteredIndex]);
    if (masterIndex < 0) return;

    final current = _parsed[masterIndex].displayName(masterIndex);
    final ctrl    = TextEditingController(text: current);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename session',
            style: TextStyle(
              color:      AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize:   16,
            )),
        content: TextField(
          controller: ctrl,
          autofocus:  true,
          style:      TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText:  'Session name',
            hintStyle: TextStyle(color: AppColors.textSecond),
            filled:    true,
            fillColor: AppColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecond)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Save',
                style: TextStyle(
                  color:      AppColors.primary,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    final old = _parsed[masterIndex];
    final id  = _sessions[masterIndex]['result_id'] as String? ??
        _sessions[masterIndex]['id']        as String? ?? '';

    setState(() {
      _parsed[masterIndex] = StudyResult(
        resultId:   old.resultId,
        summary:    old.summary,
        fileUrl:    old.fileUrl,
        fileName:   newName,
        createdAt:  old.createdAt,
        quiz:       old.quiz,
        flashcards: old.flashcards,
      );
      _sessions[masterIndex] = {
        ..._sessions[masterIndex],
        'file_name': newName,
      };
      _applyFilter();
    });

    if (id.isNotEmpty) {
      try {
        await _api.renameResult(id, newName);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Renamed locally — could not sync to server.'),
            backgroundColor: AppColors.accentAmber.withOpacity(0.12),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ));
        }
      }
    }
  }

  // ── Retry processing ──────────────────────────────────────────────────────

  Future<void> _retrySession(int filteredIndex) async {
    HapticFeedback.mediumImpact();
    final masterIndex = _sessions.indexOf(_filteredSessions[filteredIndex]);
    if (masterIndex < 0) return;

    final raw  = _sessions[masterIndex];
    final id   = raw['result_id'] as String? ?? raw['id'] as String? ?? '';
    final url  = raw['file_url'] as String? ?? '';
    final uid  = _auth.userId ?? '';

    if (id.isEmpty || uid.isEmpty) return;

    setState(() => _retrying[id] = true);

    try {
      final result = await _api.retryProcessing(
        resultId: id,
        userId:   uid,
        fileUrl:  url,
      );

      if (!mounted) return;

      final updated = {
        ...raw,
        'summary':    result.summary,
        'quiz':       result.quiz.map((q) => {
          'question': q.question,
          'options':  q.options,
          'answer':   q.answer,
        }).toList(),
        'flashcards': result.flashcards.map((f) => {
          'front': f.front,
          'back':  f.back,
        }).toList(),
      };

      setState(() {
        _sessions[masterIndex] = updated;
        _parsed[masterIndex]   = StudyResult.fromJson(updated);
        _retrying.remove(id);
        _applyFilter();
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Study materials generated!',
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:         BorderSide(color: AppColors.border),
        ),
        margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _retrying.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Retry failed: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.accentRed.withOpacity(0.85),
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> _signOut() async => _auth.signOut();

  // ── Display helpers ───────────────────────────────────────────────────────

  String get _displayName {
    final name = _userProfile?.fullName.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = _auth.userEmail ?? '';
    return email.contains('@') ? email.split('@').first : email;
  }

  String get _displayEmail    => _auth.userEmail ?? '';
  String get _displayInitials =>
      _userProfile?.initials ??
          (_auth.userEmail?.isNotEmpty == true
              ? _auth.userEmail![0].toUpperCase()
              : '?');

  StudyResult? get _mostRecent {
    for (final s in _parsed) {
      if (!s.isPending) return s;
    }
    return null;
  }

  String get _lastSyncedLabel {
    if (_lastSynced == null) return '';
    final diff = DateTime.now().difference(_lastSynced!);
    if (diff.inSeconds < 10) return 'Just synced';
    if (diff.inMinutes < 1)  return 'Synced ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    return 'Synced ${diff.inHours}h ago';
  }

  String _dateGroup(StudyResult s) {
    if (s.createdAt == null) return 'Older';
    final diff = DateTime.now().difference(s.createdAt!);
    if (diff.inDays < 7)  return 'This week';
    if (diff.inDays < 30) return 'This month';
    return 'Older';
  }

  List<_GroupedItem> get _groupedItems {
    final groups = <String, List<int>>{};
    for (var i = 0; i < _filteredParsed.length; i++) {
      final g = _dateGroup(_filteredParsed[i]);
      groups.putIfAbsent(g, () => []).add(i);
    }
    const order = ['This week', 'This month', 'Older'];
    final items = <_GroupedItem>[];
    for (final label in order) {
      if (groups.containsKey(label)) {
        items.add(_GroupedItem(isHeader: true,  label: label, index: -1));
        for (final idx in groups[label]!) {
          items.add(_GroupedItem(isHeader: false, label: label, index: idx));
        }
      }
    }
    return items;
  }

  // ── Avatar dropdown ───────────────────────────────────────────────────────

  void _showAvatarMenu(BuildContext context) async {
    final RenderBox avatar  = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
    Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset position = avatar.localToGlobal(
      Offset(0, avatar.size.height + 8),
      ancestor: overlay,
    );

    final result = await showMenu<String>(
      context:  context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + avatar.size.width,
        position.dy + 200,
      ),
      elevation: 4,
      shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color:     AppColors.surface,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _MenuHeader(
            initials: _displayInitials,
            name:     _displayName,
            email:    _displayEmail,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value:   'profile',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child:   _MenuItem(
            icon:  Icons.person_outline_rounded,
            label: 'Profile',
          ),
        ),
        if (_isAdmin)
          PopupMenuItem<String>(
            value:   'admin',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child:   _MenuItem(
              icon:  Icons.admin_panel_settings_outlined,
              label: 'Admin dashboard',
              color: AppColors.accentAmber,
            ),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value:   'signout',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child:   _MenuItem(
            icon:  Icons.logout_rounded,
            label: 'Sign out',
            color: AppColors.accentRed,
          ),
        ),
      ],
    );

    if (!mounted) return;

    switch (result) {
      case 'profile':
        await Navigator.of(context).push(slideRoute(const ProfileScreen()));
        _loadData();
      case 'admin':
        Navigator.of(context).push(slideRoute(const AdminDashboardScreen()));
      case 'signout':
        _signOut();
    }
  }

  // ── Tile context menu ─────────────────────────────────────────────────────

  void _showTileMenu(BuildContext context, int filteredIndex) async {
    HapticFeedback.mediumImpact();
    final RenderBox box     = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
    Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset pos = box.localToGlobal(Offset.zero, ancestor: overlay);

    final result = await showMenu<String>(
      context:  context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + box.size.height / 2,
        pos.dx + box.size.width,
        pos.dy + box.size.height,
      ),
      elevation: 4,
      shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color:     AppColors.surface,
      items: [
        PopupMenuItem<String>(
          value:   'rename',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child:   _MenuItem(
            icon:  Icons.drive_file_rename_outline_rounded,
            label: 'Rename',
          ),
        ),
        PopupMenuItem<String>(
          value:   'delete',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child:   _MenuItem(
            icon:  Icons.delete_outline_rounded,
            label: 'Delete',
            color: AppColors.accentRed,
          ),
        ),
      ],
    );

    if (!mounted) return;
    if (result == 'delete') _deleteSession(filteredIndex);
    if (result == 'rename') _renameSession(filteredIndex);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedItems;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildOfflineBanner(),

            Expanded(
              child: RefreshIndicator(
                onRefresh:       _loadData,
                color:           AppColors.primary,
                backgroundColor: AppColors.surface,
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildStats()),
                    SliverToBoxAdapter(child: _buildUploadCTA()),
                    SliverToBoxAdapter(child: _buildV3QuickActions()), // ✅ V3

                    if (!_loading && _mostRecent != null)
                      SliverToBoxAdapter(
                          child: _buildContinueCard(_mostRecent!)),

                    SliverToBoxAdapter(child: _buildSectionLabel()),
                    SliverToBoxAdapter(child: _buildSearchBar()),

                    if (_loading)
                      SliverToBoxAdapter(child: _buildShimmer())
                    else if (_sessions.isEmpty)
                      SliverToBoxAdapter(child: _buildEmpty())
                    else if (_filteredParsed.isEmpty &&
                          _searchQuery.isNotEmpty)
                        SliverToBoxAdapter(child: _buildNoResults())
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (ctx, i) {
                              final item = grouped[i];
                              if (item.isHeader) {
                                return _buildGroupHeader(item.label);
                              }
                              return _buildSessionTile(item.index);
                            },
                            childCount: grouped.length,
                          ),
                        ),

                    const SliverToBoxAdapter(
                        child: SizedBox(height: 40)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Offline banner ────────────────────────────────────────────────────────

  Widget _buildOfflineBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve:    Curves.easeInOut,
      height:   _isOffline ? 40 : 0,
      color:    AppColors.accentRed.withOpacity(0.90),
      child: _isOffline
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded,
            color: Colors.white, size: 15),
        const SizedBox(width: 8),
        Text(
          'You\'re offline',
          style: AppText.label.copyWith(color: Colors.white),
        ),
      ])
          : null,
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => _showAvatarMenu(ctx),
                child: Container(
                  width:  52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape:    BoxShape.circle,
                    gradient: AppColors.primaryGrad,
                    boxShadow: [
                      BoxShadow(
                        color:      AppColors.primary.withOpacity(0.28),
                        blurRadius: 14,
                        offset:     const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _displayInitials,
                      style: const TextStyle(
                        color:       Colors.white,
                        fontWeight:  FontWeight.w800,
                        fontSize:    19,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_greeting 👋',
                      style: TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w500,
                        color:      AppColors.textSecond,
                        letterSpacing: 0.2,
                      )),
                  const SizedBox(height: 2),
                  Text(_displayName,
                      style: TextStyle(
                        fontSize:   17,
                        fontWeight: FontWeight.w700,
                        color:      AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),

          if (_lastSynced != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 66),
              Icon(Icons.sync_rounded,
                  size:  11,
                  color: AppColors.textSecond.withOpacity(0.55)),
              const SizedBox(width: 4),
              Text(_lastSyncedLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color:    AppColors.textSecond.withOpacity(0.55),
                  )),
            ]),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.06);
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Widget _buildStats() {
    final totalQ = _sessions.fold<int>(
        0, (s, r) => s + ((r['quiz']       as List?)?.length ?? 0));
    final totalC = _sessions.fold<int>(
        0, (s, r) => s + ((r['flashcards'] as List?)?.length ?? 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        _AnimatedStatCard(
          emoji: '📚',
          label: 'Sessions',
          value: _sessions.length,
          bg:    AppColors.accentBlue.withOpacity(0.10),
          fg:    AppColors.accentBlue,
          onTap: _loading
              ? null
              : () {
            HapticFeedback.lightImpact();
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve:    Curves.easeInOut,
            );
          },
        ),
        const SizedBox(width: 10),
        _AnimatedStatCard(
          emoji: '❓',
          label: 'Questions',
          value: totalQ,
          bg:    AppColors.accentGreen.withOpacity(0.10),
          fg:    AppColors.accentGreen,
        ),
        const SizedBox(width: 10),
        _AnimatedStatCard(
          emoji: '🃏',
          label: 'Flashcards',
          value: totalC,
          bg:    AppColors.accentAmber.withOpacity(0.10),
          fg:    AppColors.accentAmber,
        ),
      ]),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.12);
  }

  // ── Upload CTA ────────────────────────────────────────────────────────────

  Widget _buildUploadCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: GestureDetector(
        onTap: () async {
          HapticFeedback.lightImpact();
          await Navigator.of(context).push(
            slideRoute(UploadScreen(
              isFirstUpload: _sessions.isEmpty,
            )),
          );
          _loadData();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          decoration: BoxDecoration(
            gradient:     AppColors.primaryGrad,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color:      AppColors.primary.withOpacity(0.30),
                blurRadius: 24,
                offset:     const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:        Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('New session',
                          style: TextStyle(
                            color:       Colors.white,
                            fontSize:    11,
                            fontWeight:  FontWeight.w600,
                            letterSpacing: 0.5,
                          )),
                    ),
                    const SizedBox(height: 12),
                    const Text('Upload a document\nand start learning',
                        style: TextStyle(
                          color:       Colors.white,
                          fontSize:    18,
                          fontWeight:  FontWeight.w800,
                          height:      1.25,
                          letterSpacing: -0.4,
                        )),
                    const SizedBox(height: 6),
                    Text('PDF · DOCX · YouTube · URL · Image',
                        style: TextStyle(
                          color:    Colors.white.withOpacity(0.68),
                          fontSize: 12,
                        )),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color:        Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Get started  →',
                          style: TextStyle(
                            color:      AppColors.primary,
                            fontSize:   13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          )),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(
                      color: Colors.white.withOpacity(0.20), width: 1.5),
                ),
                child: const Center(
                  child: Icon(Icons.upload_file_rounded,
                      size: 34, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.15);
  }

  // ── ✅ V3 — Quick-action row (SR / Analytics / Community) ─────────────────

  Widget _buildV3QuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(children: [
        // Spaced Repetition
        Expanded(
          child: _V3ActionCard(
            icon:    Icons.repeat_rounded,
            label:   'Review',
            sublabel: _srDueCount > 0 ? '$_srDueCount due' : 'Up to date',
            color:   AppColors.primary,
            bg:      AppColors.primaryGlow,
            badge:   _srDueCount > 0 ? _srDueCount : null,
            onTap:   () async {
              HapticFeedback.lightImpact();
              await Navigator.of(context)
                  .push(slideRoute(const SrReviewScreen()));
              _loadData(); // refresh due count after review
            },
          ),
        ),
        const SizedBox(width: 10),
        // Analytics
        Expanded(
          child: _V3ActionCard(
            icon:    Icons.bar_chart_rounded,
            label:   'Analytics',
            sublabel: 'Weak topics',
            color:   AppColors.accentGreen,
            bg:      AppColors.accentGreen.withOpacity(0.10),
            onTap:   () {
              HapticFeedback.lightImpact();
              Navigator.of(context)
                  .push(slideRoute(const AnalyticsScreen()));
            },
          ),
        ),
        const SizedBox(width: 10),
        // Community
        Expanded(
          child: _V3ActionCard(
            icon:    Icons.people_outline_rounded,
            label:   'Community',
            sublabel: 'Browse decks',
            color:   AppColors.accentAmber,
            bg:      AppColors.accentAmber.withOpacity(0.10),
            onTap:   () {
              HapticFeedback.lightImpact();
              Navigator.of(context)
                  .push(slideRoute(const SharedSessionsScreen()));
            },
          ),
        ),
      ]),
    ).animate().fadeIn(delay: 270.ms, duration: 380.ms).slideY(begin: 0.12);
  }

  // ── Continue card ─────────────────────────────────────────────────────────

  Widget _buildContinueCard(StudyResult session) {
    final index = _parsed.indexOf(session);
    final name  = session.displayName(index < 0 ? 0 : index);
    final id    = session.resultId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GestureDetector(
        onTap: () {
          if (id.isEmpty) return;
          HapticFeedback.lightImpact();
          Navigator.of(context)
              .push(slideRoute(ResultsScreen(resultId: id)));
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(
                color: AppColors.primary.withOpacity(0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color:      AppColors.primary.withOpacity(0.07),
                blurRadius: 16,
                offset:     const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color:        AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Icon(Icons.play_circle_outline_rounded,
                    size: 22, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Continue where you left off',
                      style: TextStyle(
                        fontSize:   11,
                        fontWeight: FontWeight.w600,
                        color:      AppColors.primary,
                        letterSpacing: 0.1,
                      )),
                  const SizedBox(height: 3),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w700,
                        color:      AppColors.textPrimary,
                        letterSpacing: -0.2,
                      )),
                  if (session.relativeTime.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(session.relativeTime,
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textSecond)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 13, color: AppColors.primary),
          ]),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 350.ms).slideY(begin: 0.1);
  }

  // ── Section label ─────────────────────────────────────────────────────────

  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Row(children: [
        Text('Recent Sessions',
            style: TextStyle(
              fontSize:   16,
              fontWeight: FontWeight.w800,
              color:      AppColors.textPrimary,
              letterSpacing: -0.3,
            )),
        const SizedBox(width: 8),
        if (!_loading && _sessions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${_sessions.length}',
                style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w700,
                  color:      AppColors.primary,
                )),
          ),
        const Spacer(),
        if (!_loading && _sessions.isNotEmpty)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                  _applyFilter();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _searchVisible
                    ? AppColors.primaryGlow
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _searchVisible
                      ? AppColors.primary.withOpacity(0.3)
                      : AppColors.border,
                ),
              ),
              child: Icon(
                _searchVisible
                    ? Icons.search_off_rounded
                    : Icons.search_rounded,
                size:  16,
                color: _searchVisible
                    ? AppColors.primary
                    : AppColors.textSecond,
              ),
            ),
          ),
      ]),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    if (!_searchVisible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        controller: _searchCtrl,
        autofocus:  true,
        style:      TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText:   'Search sessions…',
          hintStyle:  TextStyle(color: AppColors.textSecond, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: AppColors.textSecond),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              setState(() { _searchQuery = ''; _applyFilter(); });
            },
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.textSecond),
          )
              : null,
          filled:          true,
          fillColor:       AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:   BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:   BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:   BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1);
  }

  // ── Group header ──────────────────────────────────────────────────────────

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(label,
          style: TextStyle(
            fontSize:   12,
            fontWeight: FontWeight.w700,
            color:      AppColors.textSecond,
            letterSpacing: 0.4,
          )),
    );
  }

  // ── Session tile ──────────────────────────────────────────────────────────

  Widget _buildSessionTile(int filteredIndex) {
    final r      = _filteredSessions[filteredIndex];
    final parsed = _filteredParsed[filteredIndex];

    final quizCount = (r['quiz']       as List?)?.length ?? 0;
    final cardCount = (r['flashcards'] as List?)?.length ?? 0;
    final id        = r['result_id'] as String? ?? r['id'] as String? ?? '';
    final title     = parsed.displayName(filteredIndex);
    final timeLabel = parsed.relativeTime;
    final isPending = parsed.isPending;
    final summary   = isPending ? '' : parsed.summary;
    final isRetrying = _retrying[id] == true;

    final accentColors = [
      AppColors.accentBlue, AppColors.accentGreen,
      AppColors.accentAmber, AppColors.primary,
    ];
    final accentBgs = [
      AppColors.accentBlue.withOpacity(0.10),
      AppColors.accentGreen.withOpacity(0.10),
      AppColors.accentAmber.withOpacity(0.10),
      AppColors.primaryGlow,
    ];
    final accent   = accentColors[filteredIndex % accentColors.length];
    final accentBg = accentBgs[filteredIndex % accentBgs.length];

    const tileIcons = [
      Icons.menu_book_rounded,
      Icons.psychology_rounded,
      Icons.bolt_rounded,
      Icons.track_changes_rounded,
    ];

    return Dismissible(
      key: ValueKey(id.isNotEmpty
          ? id
          : 'session-$filteredIndex-${parsed.createdAt}'),
      direction:   DismissDirection.endToStart,
      onDismissed: (_) => _deleteSession(filteredIndex),
      background: Container(
        margin:    const EdgeInsets.fromLTRB(20, 0, 20, 10),
        decoration: BoxDecoration(
          color:        AppColors.accentRed.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.accentRed.withOpacity(0.25)),
        ),
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 22),
        child: Icon(Icons.delete_outline_rounded,
            color: AppColors.accentRed, size: 24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Builder(
          builder: (tileCtx) => GestureDetector(
            onTap: () {
              if (isPending || id.isEmpty) return;
              HapticFeedback.lightImpact();
              Navigator.of(context)
                  .push(slideRoute(ResultsScreen(resultId: id)));
            },
            onLongPress: () => _showTileMenu(tileCtx, filteredIndex),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(
                    color: AppColors.border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset:     const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color:        accentBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Icon(
                        tileIcons[filteredIndex % tileIcons.length],
                        size:  22,
                        color: accent,
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize:   15,
                                  fontWeight: FontWeight.w700,
                                  color:      AppColors.textPrimary,
                                  letterSpacing: -0.2,
                                )),
                          ),
                          if (isPending && !isRetrying)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accentAmber.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Processing',
                                  style: TextStyle(
                                    fontSize:   10,
                                    fontWeight: FontWeight.w600,
                                    color:      AppColors.accentAmber,
                                  )),
                            ),
                          if (isRetrying)
                            SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color:       AppColors.primary,
                              ),
                            ),
                        ]),

                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(timeLabel,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color:    AppColors.textSecond)),
                        ],

                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height:   1.45,
                                color:    AppColors.textBody,
                              )),
                        ],

                        const SizedBox(height: 10),

                        if (isPending && !isRetrying) ...[
                          GestureDetector(
                            onTap: () => _retrySession(filteredIndex),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.primary.withOpacity(0.3)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        size:  13,
                                        color: AppColors.primary),
                                    const SizedBox(width: 5),
                                    Text('Retry generation',
                                        style: TextStyle(
                                          fontSize:   11,
                                          fontWeight: FontWeight.w600,
                                          color:      AppColors.primary,
                                        )),
                                  ]),
                            ),
                          ),
                        ] else ...[
                          Wrap(spacing: 6, children: [
                            _FriendlyPill(
                              label: '$quizCount questions',
                              icon:  Icons.help_outline_rounded,
                              color: AppColors.accentGreen,
                              bg:    AppColors.accentGreen.withOpacity(0.10),
                            ),
                            _FriendlyPill(
                              label: '$cardCount cards',
                              icon:  Icons.style_outlined,
                              color: AppColors.accentAmber,
                              bg:    AppColors.accentAmber.withOpacity(0.10),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),
                  if (!isPending)
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 13, color: AppColors.textSecond),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
      delay:    Duration(milliseconds: 260 + filteredIndex * 60),
      duration: 350.ms,
    ).slideX(begin: 0.06);
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 24),
      child: Center(
        child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color:        AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(Icons.inbox_rounded,
                  size: 32, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 18),
          Text('Nothing here yet',
              style: TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w800,
                color:      AppColors.textPrimary,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 8),
          Text(
            'Upload your first document above\n'
                'and we\'ll create a study set for you.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, height: 1.55, color: AppColors.textSecond),
          ),
        ]),
      ),
    ).animate().fadeIn(duration: 400.ms)
        .scale(begin: const Offset(0.95, 0.95));
  }

  // ── No search results ─────────────────────────────────────────────────────

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(children: [
          Icon(Icons.search_off_rounded,
              size: 36, color: AppColors.textSecond),
          const SizedBox(height: 12),
          Text('No sessions match "$_searchQuery"',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color:    AppColors.textSecond,
                  height:   1.5)),
        ]),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Loading shimmer ───────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(3, (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 96,
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: AppColors.border),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(
            duration: 1100.ms,
            color:    AppColors.primaryGlow)),
      ),
    );
  }
}

// ── ✅ V3 — Quick-action card widget ─────────────────────────────────────────

class _V3ActionCard extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       sublabel;
  final Color        color;
  final Color        bg;
  final int?         badge;
  final VoidCallback onTap;

  const _V3ActionCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.bg,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(18),
          border:       Border.all(color: color.withOpacity(0.15), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color:        color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(icon, size: 18, color: color),
                  ),
                ),
                if (badge != null && badge! > 0)
                  Positioned(
                    top: -5, right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color:        color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge! > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w700,
                  color:      color,
                  letterSpacing: -0.1,
                )),
            const SizedBox(height: 2),
            Text(sublabel,
                style: TextStyle(
                  fontSize:   10.5,
                  color:      color.withOpacity(0.70),
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Grouped item model ────────────────────────────────────────────────────────

class _GroupedItem {
  final bool   isHeader;
  final String label;
  final int    index;
  const _GroupedItem({
    required this.isHeader,
    required this.label,
    required this.index,
  });
}

// ── Animated stat card ────────────────────────────────────────────────────────

class _AnimatedStatCard extends StatelessWidget {
  final String       emoji;
  final String       label;
  final int          value;
  final Color        bg;
  final Color        fg;
  final VoidCallback? onTap;

  const _AnimatedStatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: fg.withOpacity(0.12), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween:    Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve:    Curves.easeOut,
            builder: (_, v, __) => Text('${v.round()}',
                style: TextStyle(
                  fontSize:   22,
                  fontWeight: FontWeight.w800,
                  color:      fg,
                  letterSpacing: -0.5,
                )),
          ),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w500,
                color:      fg.withOpacity(0.75),
              )),
        ]),
      ),
    ),
  );
}

// ── Menu header / item ────────────────────────────────────────────────────────

class _MenuHeader extends StatelessWidget {
  final String initials;
  final String name;
  final String email;
  const _MenuHeader({
    required this.initials,
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: const BoxDecoration(
            shape:    BoxShape.circle,
            gradient: AppColors.primaryGrad,
          ),
          child: Center(
            child: Text(initials,
                style: const TextStyle(
                  color:      Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize:   15,
                )),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w700,
                  color:      AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
                overflow: TextOverflow.ellipsis),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(email,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecond),
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;
  const _MenuItem({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textBody;
    return Row(children: [
      Icon(icon, size: 17, color: c),
      const SizedBox(width: 10),
      Text(label,
          style: TextStyle(
            fontSize:   13.5,
            fontWeight: FontWeight.w500,
            color:      c,
          )),
    ]);
  }
}

// ── Pill chip ─────────────────────────────────────────────────────────────────

class _FriendlyPill extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final Color    bg;
  const _FriendlyPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color:        bg,
      borderRadius: BorderRadius.circular(20),
      border:       Border.all(color: color.withOpacity(0.20)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
            fontSize:   11,
            fontWeight: FontWeight.w600,
            color:      color,
          )),
    ]),
  );
}
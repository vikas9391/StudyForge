// lib/screens/home_screen.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../models/profile.dart';
import '../models/study_result.dart';
import '../widgets/app_bottom_nav.dart';
import 'upload_screen.dart';
import 'results_screen.dart';
import 'profile_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'sr_review_screen.dart';
import 'analytics_screen.dart';
import 'shared_sessions_screen.dart';
import 'notifications_screen.dart';
import '../main.dart' show slideRoute, navigatorKey, AuthGate;
import '../services/home_cache.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSignOut;
  const HomeScreen({super.key, this.onSignOut});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api        = ApiService();
  final _profileSvc = ProfileService();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _sessions         = [];
  List<StudyResult>          _parsed           = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  List<StudyResult>          _filteredParsed   = [];

  UserProfile? _userProfile;
  bool         _loading        = true;
  bool         _isAdmin        = false;
  bool         _searchVisible  = false;
  String       _searchQuery    = '';

  DateTime? _lastSynced;

  Timer?  _greetingTimer;
  String  _greeting = '';

  bool _isOffline = false;
  int _unreadCount = 0;

  final Map<String, bool> _retrying = {};

  AppNavTab _currentTab = AppNavTab.home;

  // ── Real stats state ───────────────────────────────────────────────────────
  int    _questionsThisWeek  = 0;
  int    _flashcardsThisWeek = 0;
  int    _questionsDelta     = 0;
  int    _flashcardsDelta    = 0;
  double _accuracyRate       = 0.0; // 0.0–1.0
  List<SrSession> _srSessions = [];
  int _totalDueCards = 0;
  // ── Lifecycle ──────────────────────────────────────────────────────────────

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

  // ── Greeting ───────────────────────────────────────────────────────────────

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

  // ── Search ─────────────────────────────────────────────────────────────────

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

  // ── Data loading ───────────────────────────────────────────────────────────
  //
  // Strategy:
  //  1. If cache has data → paint UI instantly (no shimmer).
  //  2. If cache is stale (>3 min) → background-refresh silently.
  //  3. forceRefresh=true (pull-to-refresh, after upload/delete) → always fetch.

  Future<void> _loadData({bool forceRefresh = false}) async {
    final cache = HomeCache.instance;

    // ── Step 1: Serve from cache immediately ──────────────────────────────
    if (cache.hasData && !forceRefresh) {
      if (mounted) {
        setState(() {
          _sessions           = List.from(cache.sessions!);
          _parsed             = List.from(cache.parsed!);
          _userProfile        = cache.profile;
          _isAdmin            = cache.profile?.isAdmin ?? false;
          _questionsThisWeek  = cache.questionsThisWeek;
          _flashcardsThisWeek = cache.flashcardsThisWeek;
          _questionsDelta     = cache.questionsDelta;
          _flashcardsDelta    = cache.flashcardsDelta;
          _accuracyRate       = cache.accuracyRate;
          _unreadCount        = cache.unreadCount;
          _loading            = false;
          _applyFilter();
        });
      }
      // If still fresh, stop — no network call needed.
      if (!cache.isStale()) return;
    } else {
      // No cache at all → show shimmer while we fetch.
      if (mounted) setState(() => _loading = true);
    }

    // ── Step 2: Fetch from network ────────────────────────────────────────
    try {
      final uid = AuthService.userId;
      if (uid.isEmpty) return;

      // Sessions (required)
      final resultsData = await _api.getUserResults(uid);

      // Profile (non-fatal)
      UserProfile? profile;
      try {
        profile = await _profileSvc.getProfile(uid);
      } catch (e) {
        debugPrint('Profile fetch failed: $e');
      }

      final parsed = resultsData.map((r) => StudyResult.fromJson(r)).toList();

      // Update cache
      cache.updateSessions(resultsData, parsed);
      cache.updateProfile(profile);

      if (mounted) {
        setState(() {
          _sessions    = resultsData;
          _parsed      = parsed;
          _userProfile = profile;
          _isAdmin     = profile?.isAdmin ?? false;
          _lastSynced  = DateTime.now();
          _loading     = false;
          _applyFilter();
        });
      }

      // Stats + notifications (non-fatal, sequential to avoid hammering DB)
      try {
        final weeklyStats = await _api.getWeeklyStats(uid);
        final summary     = await _api.getAnalyticsSummary(uid);

        List<dynamic> notifs = [];
        try {
          notifs = await _api.getNotifications(uid);
        } catch (_) {}

        final unread = notifs
            .where((n) => n is Map
            ? !(n['is_read'] as bool? ?? false)
            : !n.isRead)
            .length;

        final qWeek  = (weeklyStats['questions_this_week']  as num?)?.toInt() ?? 0;
        final cWeek  = (weeklyStats['flashcards_this_week'] as num?)?.toInt() ?? 0;
        final qDelta = (weeklyStats['questions_delta']       as num?)?.toInt() ?? 0;
        final cDelta = (weeklyStats['flashcards_delta']      as num?)?.toInt() ?? 0;
        final avgAcc =
            ((summary['avg_accuracy'] as num?)?.toDouble() ?? 0.0) / 100.0;

        cache.updateStats(
          questionsThisWeek:  qWeek,
          flashcardsThisWeek: cWeek,
          questionsDelta:     qDelta,
          flashcardsDelta:    cDelta,
          accuracyRate:       avgAcc,
        );
        cache.updateUnread(unread);
        cache.markFetched();

        try {
          final srSessions = await _api.getDueCards(uid);
          final dueTotal   = srSessions.fold<int>(
              0, (s, r) => s + r.cards.length);
          if (mounted) {
            setState(() {
              _srSessions    = srSessions;
              _totalDueCards = dueTotal;
            });
          }
        } catch (_) {}   // non-fatal — SR section just stays hidden

        if (mounted) {
          setState(() {
            _questionsThisWeek  = qWeek;
            _flashcardsThisWeek = cWeek;
            _questionsDelta     = qDelta;
            _flashcardsDelta    = cDelta;
            _accuracyRate       = avgAcc;
            _unreadCount        = unread;
          });
        }
      } catch (e) {
        debugPrint('Stats/notifications fetch failed: $e');
        cache.markFetched(); // avoid hammering server on repeated failures
      }
    } catch (e) {
      debugPrint('Core data load failed: $e');
      if (e.toString().contains('Session expired') && mounted) {
        await AuthService.clearTokens();
        widget.onSignOut?.call();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Delete session ─────────────────────────────────────────────────────────

  Future<void> _deleteSession(int filteredIndex) async {
    HapticFeedback.mediumImpact();
    final masterIndex = _sessions.indexOf(_filteredSessions[filteredIndex]);
    if (masterIndex < 0) return;
    final removedRaw    = _sessions[masterIndex];
    final removedParsed = _parsed[masterIndex];
    final id = removedRaw['result_id'] as String? ?? removedRaw['id'] as String? ?? '';
    if (id.isEmpty) return;

    setState(() {
      _sessions.removeAt(masterIndex);
      _parsed.removeAt(masterIndex);
      _applyFilter();
    });

    try {
      await _api.deleteResult(id);
      HomeCache.instance.invalidate(); // force fresh fetch next visit
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Session deleted',
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
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

  // ── Rename session ─────────────────────────────────────────────────────────

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
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Session name',
            hintStyle: TextStyle(color: AppColors.textSecond),
            filled: true, fillColor: AppColors.bg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: AppColors.textSecond))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text('Save',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    final old = _parsed[masterIndex];
    final id  = _sessions[masterIndex]['result_id'] as String?
        ?? _sessions[masterIndex]['id'] as String? ?? '';

    setState(() {
      _parsed[masterIndex] = StudyResult(
        resultId: old.resultId, summary: old.summary, fileUrl: old.fileUrl,
        fileName: newName,      createdAt: old.createdAt,
        quiz: old.quiz,         flashcards: old.flashcards,
      );
      _sessions[masterIndex] = {..._sessions[masterIndex], 'file_name': newName};
      _applyFilter();
    });

    if (id.isNotEmpty) {
      try {
        await _api.renameResult(id, newName);
        HomeCache.instance.invalidate(); // keep cache in sync
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Renamed locally — could not sync to server.'),
            backgroundColor: AppColors.accentAmber.withOpacity(0.12),
            behavior: SnackBarBehavior.floating,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ));
        }
      }
    }
  }

  // ── Retry session ──────────────────────────────────────────────────────────

  Future<void> _retrySession(int filteredIndex) async {
    HapticFeedback.mediumImpact();
    final masterIndex = _sessions.indexOf(_filteredSessions[filteredIndex]);
    if (masterIndex < 0) return;
    final raw = _sessions[masterIndex];
    final id  = raw['result_id'] as String? ?? raw['id'] as String? ?? '';
    final url = raw['file_url'] as String? ?? '';
    final uid = AuthService.userId;
    if (id.isEmpty || uid.isEmpty) return;

    setState(() => _retrying[id] = true);

    try {
      final result =
      await _api.retryProcessing(resultId: id, userId: uid, fileUrl: url);
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
      HomeCache.instance.invalidate();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Study materials generated!',
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
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
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _displayName {
    final name = _userProfile?.fullName.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = AuthService.userEmail;
    return email.contains('@') ? email.split('@').first : email;
  }

  String get _displayEmail => AuthService.userEmail;
  String get _displayInitials =>
      _userProfile?.initials ??
          (AuthService.userEmail.isNotEmpty
              ? AuthService.userEmail[0].toUpperCase()
              : '?');

  String get _lastSyncedLabel {
    if (_lastSynced == null) return '';
    final diff = DateTime.now().difference(_lastSynced!);
    if (diff.inSeconds < 10) return 'Just synced';
    if (diff.inMinutes < 1)  return 'Synced ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    return 'Synced ${diff.inHours}h ago';
  }

  StudyResult? get _mostRecent {
    for (final s in _parsed) {
      if (!s.isPending) return s;
    }
    return null;
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
    final items  = <_GroupedItem>[];
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

  // ── Delta label helpers ────────────────────────────────────────────────────

  String _deltaLabel(int delta, String unit) {
    if (delta == 0) return 'No change this week';
    final sign = delta > 0 ? '+' : '';
    return '$sign$delta $unit this week';
  }

  Color _deltaColor(int delta) =>
      delta >= 0 ? AppColors.deltaGreen : AppColors.accentRed;

  // ── Avatar menu ────────────────────────────────────────────────────────────

  void _showAvatarMenu(BuildContext context) async {
    final RenderBox avatar =
    context.findRenderObject() as RenderBox;
    final RenderBox overlay =
    Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset pos = avatar.localToGlobal(
        Offset(0, avatar.size.height + 8),
        ancestor: overlay);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          pos.dx, pos.dy, pos.dx + avatar.size.width, pos.dy + 200),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.surface,
      items: [
        PopupMenuItem<String>(
            enabled: false, padding: EdgeInsets.zero,
            child: _MenuHeader(
                initials: _displayInitials,
                name:     _displayName,
                email:    _displayEmail)),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
            value:   'profile',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child:   _MenuItem(
                icon: Icons.person_outline_rounded, label: 'Profile')),
        if (_isAdmin)
          PopupMenuItem<String>(
              value:   'admin',
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child:   _MenuItem(
                  icon:  Icons.admin_panel_settings_outlined,
                  label: 'Admin dashboard',
                  color: AppColors.accentAmber)),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
            value:   'signout',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child:   _MenuItem(
                icon:  Icons.logout_rounded,
                label: 'Sign out',
                color: AppColors.accentRed)),
      ],
    );
    if (!mounted || result == null) return;
    switch (result) {
      case 'profile':
        await Navigator.of(context).push(slideRoute(const ProfileScreen()));
        // Don't invalidate — profile change doesn't affect sessions list
        if (mounted) _loadData();
      case 'admin':
        if (mounted)
          Navigator.of(context)
              .push(slideRoute(const AdminDashboardScreen()));
      case 'signout':
        HomeCache.instance.invalidate();
        await AuthService.signOut();
        if (!mounted) return;
        widget.onSignOut?.call();
    }
  }

  void _showTileMenu(BuildContext context, int filteredIndex) async {
    HapticFeedback.mediumImpact();
    final RenderBox box =
    context.findRenderObject() as RenderBox;
    final RenderBox overlay =
    Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset pos = box.localToGlobal(Offset.zero, ancestor: overlay);

    final result = await showMenu<String>(
      context:  context,
      position: RelativeRect.fromLTRB(
          pos.dx, pos.dy + box.size.height / 2,
          pos.dx + box.size.width, pos.dy + box.size.height),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: AppColors.surface,
      items: [
        PopupMenuItem<String>(
            value:   'rename',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child:   _MenuItem(
                icon: Icons.drive_file_rename_outline_rounded,
                label: 'Rename')),
        PopupMenuItem<String>(
            value:   'delete',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child:   _MenuItem(
                icon:  Icons.delete_outline_rounded,
                label: 'Delete',
                color: AppColors.accentRed)),
      ],
    );

    if (!mounted) return;
    if (result == 'delete') _deleteSession(filteredIndex);
    if (result == 'rename') _renameSession(filteredIndex);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDE8),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildOfflineBanner(),
                Expanded(
                  child: RefreshIndicator(
                    // forceRefresh=true so pull-to-refresh always hits the network
                    onRefresh: () => _loadData(forceRefresh: true),
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    child: CustomScrollView(
                      controller: _scrollCtrl,
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        SliverToBoxAdapter(child: _buildUploadCTA()),
                        SliverToBoxAdapter(child: _buildStats()),
                        if (!_loading && _mostRecent != null)
                          SliverToBoxAdapter(
                              child: _buildContinueCard(_mostRecent!)),
                        SliverToBoxAdapter(
                            child: _buildRecentSourcesHeader()),
                        if (_loading)
                          SliverToBoxAdapter(child: _buildShimmer())
                        else if (_sessions.isEmpty)
                          SliverToBoxAdapter(child: _buildEmpty())
                        else if (_filteredParsed.isEmpty &&
                              _searchQuery.isNotEmpty)
                            SliverToBoxAdapter(child: _buildNoResults())
                          else
                            SliverToBoxAdapter(child: _buildSourcesCard()),
                        if (!_loading && _totalDueCards > 0)
                          SliverToBoxAdapter(child: _buildDueForReview()),
                        const SliverToBoxAdapter(
                            child: SizedBox(height: 110)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: AppBottomNav(
                currentTab: _currentTab,
                onTabChanged: (tab) =>
                    setState(() => _currentTab = tab),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Offline banner ─────────────────────────────────────────────────────────

  Widget _buildOfflineBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      height: _isOffline ? 40 : 0,
      color: AppColors.accentRed.withOpacity(0.90),
      child: _isOffline
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded,
            color: Colors.white, size: 15),
        const SizedBox(width: 8),
        Text("You're offline",
            style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ])
          : null,
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => _showAvatarMenu(ctx),
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.avatarBlue,
                    ),
                    child: Center(
                      child: Text(_displayInitials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_greeting 👋',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecond,
                            fontWeight: FontWeight.w400)),
                    const SizedBox(height: 1),
                    Text(_displayName,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await Navigator.of(context)
                      .push(slideRoute(const NotificationsScreen()));
                  // Refresh unread dot when returning
                  final uid = AuthService.userId;
                  if (uid.isNotEmpty && mounted) {
                    try {
                      final notifs = await _api.getNotifications(uid);
                      setState(() => _unreadCount =
                          notifs.where((n) => !n.isRead).length);
                    } catch (_) {}
                  }
                },
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Stack(
                    children: [
                      Center(
                          child: Icon(Icons.notifications_outlined,
                              size: 16, color: AppColors.textSecond)),
                      if (_unreadCount > 0)
                        Positioned(
                          top: 4, right: 4,
                          child: Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                                color: AppColors.accentRed,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.surface, width: 1)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_lastSynced != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 52),
              Icon(Icons.sync_rounded,
                  size: 11,
                  color: AppColors.textSecond.withOpacity(0.55)),
              const SizedBox(width: 4),
              Text(_lastSyncedLabel,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecond.withOpacity(0.55))),
            ]),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.06);
  }

  // ── Upload CTA ─────────────────────────────────────────────────────────────

  Widget _buildUploadCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.ctaBlue,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create a study set',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                'Upload any source — we\'ll generate Q&A and flashcards instantly',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75), fontSize: 12)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                await Navigator.of(context).push(slideRoute(
                    UploadScreen(isFirstUpload: _sessions.isEmpty)));
                // Invalidate so returning home shows new upload
                HomeCache.instance.invalidate();
                _loadData(forceRefresh: true);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.white.withOpacity(0.45), width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                            width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Drop a PDF or paste a link',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('or tap a source below',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _SourceButton(
                    label: 'PDF',
                    icon: Icons.picture_as_pdf_outlined),
                const SizedBox(width: 8),
                _SourceButton(
                    label: 'Link /\nURL', icon: Icons.link_rounded),
                const SizedBox(width: 8),
                _SourceButton(
                    label: 'YouTube',
                    icon: Icons.play_circle_outline_rounded),
                const SizedBox(width: 8),
                _SourceButton(
                    label: 'Camera', icon: Icons.camera_alt_outlined),
                const SizedBox(width: 8),
                _SourceButton(
                    label: 'DOCX',
                    icon: Icons.description_outlined),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.12);
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Widget _buildStats() {
    final totalQ = _sessions.fold<int>(
        0, (s, r) => s + ((r['quiz'] as List?)?.length ?? 0));
    final totalC = _sessions.fold<int>(
        0, (s, r) => s + ((r['flashcards'] as List?)?.length ?? 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your stats',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text('This month',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _StatCard(
                label:      'Questions generated',
                value:      '$totalQ',
                delta:      _deltaLabel(_questionsDelta, 'new'),
                deltaColor: _deltaColor(_questionsDelta),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label:      'Flashcards created',
                value:      '$totalC',
                delta:      _deltaLabel(_flashcardsDelta, 'new'),
                deltaColor: _deltaColor(_flashcardsDelta),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _StatCard(
                label:      'Docs processed',
                value:      '${_sessions.length}',
                delta:      'PDFs, links & more',
                deltaColor: AppColors.textSecond,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label:      'Accuracy rate',
                value:      _accuracyRate > 0
                    ? '${(_accuracyRate * 100).round()}%'
                    : '—',
                showBar:    _accuracyRate > 0,
                barValue:   _accuracyRate,
                delta:      _accuracyRate == 0 ? 'No quizzes yet' : null,
                deltaColor: AppColors.textSecond,
              ),
            ),
          ]),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 400.ms);
  }

  // ── Continue card ──────────────────────────────────────────────────────────

  Widget _buildContinueCard(StudyResult session) {
    final index = _parsed.indexOf(session);
    final name  = session.displayName(index < 0 ? 0 : index);
    final id    = session.resultId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.continueAmber, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CONTINUE WHERE YOU LEFT OFF',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.continueAmber,
                    letterSpacing: 0.6)),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.insert_drive_file_outlined,
                    size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        session.relativeTime.isNotEmpty
                            ? '${session.relativeTime} · 12 questions left to review'
                            : '12 questions left to review',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecond)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (id.isEmpty) return;
                    HapticFeedback.lightImpact();
                    Navigator.of(context)
                        .push(slideRoute(ResultsScreen(resultId: id, initialTab: 1)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Center(
                        child: Text('Review Q&A',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (id.isEmpty) return;
                    HapticFeedback.lightImpact();
                    Navigator.of(context)
                        .push(slideRoute(ResultsScreen(resultId: id, initialTab: 2)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                        color: AppColors.continueAmberBg,
                        borderRadius: BorderRadius.circular(10)),
                    child: Center(
                        child: Text('Flashcards',
                            style: TextStyle(
                                color: AppColors.continueAmberFg,
                                fontSize: 13,
                                fontWeight: FontWeight.w600))),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 350.ms).slideY(begin: 0.1);
  }

  // ── Recent sources header ──────────────────────────────────────────────────

  Widget _buildRecentSourcesHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Text('Recent sources',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 8),
          if (_sessions.isNotEmpty)
            Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${_sessions.length}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary))),
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
                          : AppColors.border),
                ),
                child: Icon(
                  _searchVisible
                      ? Icons.search_off_rounded
                      : Icons.search_rounded,
                  size: 16,
                  color: _searchVisible
                      ? AppColors.primary
                      : AppColors.textSecond,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    if (!_searchVisible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: TextField(
        controller: _searchCtrl,
        autofocus:  true,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText:  'Search sessions…',
          hintStyle: TextStyle(color: AppColors.textSecond, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: AppColors.textSecond),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              setState(() {
                _searchQuery = '';
                _applyFilter();
              });
            },
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.textSecond),
          )
              : null,
          filled:         true,
          fillColor:      AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
              BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1);
  }

  // ── Sources card (grouped list) ────────────────────────────────────────────

  Widget _buildSourcesCard() {
    final grouped = _groupedItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in grouped)
                  if (item.isHeader)
                    _buildGroupHeader(item.label)
                  else
                    _buildSourceTile(item.index),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 250.ms, duration: 350.ms);
  }

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecond,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildSourceTile(int filteredIndex) {
    final r      = _filteredSessions[filteredIndex];
    final parsed = _filteredParsed[filteredIndex];

    final quizCount  = (r['quiz']       as List?)?.length ?? 0;
    final cardCount  = (r['flashcards'] as List?)?.length ?? 0;
    final id         = r['result_id'] as String? ?? r['id'] as String? ?? '';
    final title      = parsed.displayName(filteredIndex);
    final timeLabel  = parsed.relativeTime;
    final isPending  = parsed.isPending;
    final summary    = isPending ? '' : parsed.summary;
    final isRetrying = _retrying[id] == true;

    final accent =
    AppColors.tileAccents[filteredIndex % AppColors.tileAccents.length];
    final accentBg =
    AppColors.tileAccentBgs[filteredIndex % AppColors.tileAccentBgs.length];

    const tileIcons = [
      Icons.description_outlined,
      Icons.language_rounded,
      Icons.notes_rounded,
      Icons.play_circle_outline_rounded,
    ];

    final isLast = filteredIndex == _filteredParsed.length - 1;

    return Dismissible(
      key: ValueKey(id.isNotEmpty ? id : 'src-$filteredIndex'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteSession(filteredIndex),
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border:
          Border.all(color: AppColors.accentRed.withOpacity(0.25)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child:
        Icon(Icons.delete_outline_rounded, color: AppColors.accentRed),
      ),
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
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                    bottom: BorderSide(
                        color:
                        AppColors.border.withOpacity(0.5)))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: accentBg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Icon(
                          tileIcons[
                          filteredIndex % tileIcons.length],
                          size: 18,
                          color: accent)),
                ),
                const SizedBox(width: 12),
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                        if (isPending && !isRetrying)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.accentAmber
                                    .withOpacity(0.10),
                                borderRadius:
                                BorderRadius.circular(20)),
                            child: Text('Processing',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accentAmber)),
                          ),
                        if (isRetrying)
                          SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary)),
                      ]),
                      const SizedBox(height: 2),
                      Text(timeLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecond)),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: AppColors.textBody)),
                      ],
                      const SizedBox(height: 8),
                      if (isPending && !isRetrying)
                        GestureDetector(
                          onTap: () => _retrySession(filteredIndex),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withOpacity(0.10),
                                borderRadius:
                                BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withOpacity(0.3))),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded,
                                      size: 12,
                                      color: AppColors.primary),
                                  const SizedBox(width: 4),
                                  Text('Retry generation',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary)),
                                ]),
                          ),
                        )
                      else if (!isRetrying)
                        Wrap(spacing: 6, children: [
                          _Pill(
                              label: '$quizCount Q&A',
                              color: AppColors.primary,
                              bg: AppColors.primaryGlow),
                          _Pill(
                              label: '$cardCount cards',
                              color: AppColors.continueAmberFg,
                              bg: AppColors.continueAmberBg),
                        ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!isPending)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.arrow_forward_ios_rounded,
                        size: 13, color: AppColors.textSecond),
                  ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
      delay:    Duration(milliseconds: 260 + filteredIndex * 50),
      duration: 300.ms,
    );
  }

  // ── Due for review ─────────────────────────────────────────────────────────

  Widget _buildDueForReview() {
    // Use real SR data, up to 3 sessions
    final reviewSessions = _srSessions.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Due for review',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('Spaced repetition keeps it fresh',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecond)),
                    ]),
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: AppColors.reviewRedBg,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('$_totalDueCards cards',
                        style: TextStyle(
                            color: AppColors.reviewRedFg,
                            fontSize: 11,
                            fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(reviewSessions.length, (i) {
              final session  = reviewSessions[i];
              final dueCount = session.cards.length;
              // Find the matching parsed session name by resultId
              final matchIdx = _sessions.indexWhere(
                      (s) => (s['result_id'] ?? s['id']) == session.resultId);
              final name = matchIdx >= 0
                  ? _parsed[matchIdx].displayName(matchIdx)
                  : 'Session ${i + 1}';

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                    border: i < reviewSessions.length - 1
                        ? Border(
                        bottom: BorderSide(
                            color: AppColors.border.withOpacity(0.5)))
                        : null),
                child: Row(children: [
                  Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: AppColors.reviewDots[
                          i % AppColors.reviewDots.length],
                          shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary))),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.reviewCountBgs[
                          i % AppColors.reviewCountBgs.length],
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('$dueCount',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.reviewCountFgs[
                              i % AppColors.reviewCountFgs.length]))),
                ]),
              );
            }),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context)
                    .push(slideRoute(const SrReviewScreen()));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12)),
                child: const Center(
                    child: Text('Start review session',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600))),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 350.ms);
  }
  // ── Empty / no-results / shimmer ───────────────────────────────────────────

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(children: [
          Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(20)),
              child: const Center(
                  child: Icon(Icons.inbox_rounded,
                      size: 32, color: AppColors.primary))),
          const SizedBox(height: 18),
          Text('Nothing here yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(
              'Upload your first document above\nand we\'ll create a study set for you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AppColors.textSecond)),
        ]),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .scale(begin: const Offset(0.95, 0.95));
  }

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
                  color: AppColors.textSecond,
                  height: 1.5)),
        ]),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: List.generate(
            3,
                (i) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 80,
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border)),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .shimmer(
                duration: 1100.ms,
                color: AppColors.primaryGlow)),
      ),
    );
  }
}

// ─── Grouped item model ───────────────────────────────────────────────────────

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

// ─── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String  label;
  final String  value;
  final String? delta;
  final Color?  deltaColor;
  final bool    showBar;
  final double  barValue;

  const _StatCard({
    required this.label,
    required this.value,
    this.delta,
    this.deltaColor,
    this.showBar = false,
    this.barValue = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
              TextStyle(fontSize: 11, color: AppColors.textSecond)),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, t, __) => Text(value,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.0)),
          ),
          if (showBar) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: barValue,
                minHeight: 4,
                backgroundColor: AppColors.border,
                color: AppColors.primary,
              ),
            ),
          ] else if (delta != null) ...[
            const SizedBox(height: 3),
            Text(delta!,
                style: TextStyle(
                    fontSize: 11,
                    color: deltaColor ?? AppColors.textSecond)),
          ],
        ],
      ),
    );
  }
}

// ─── Source button (inside CTA) ───────────────────────────────────────────────

class _SourceButton extends StatelessWidget {
  final String   label;
  final IconData icon;
  const _SourceButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.13),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.white.withOpacity(0.5), width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(icon, size: 13, color: Colors.white),
            ),
            const SizedBox(height: 5),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    height: 1.2)),
          ],
        ),
      ),
    );
  }
}

// ─── Pill chip ────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color  color;
  final Color  bg;
  const _Pill({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color)),
  );
}

// ─── Menu header / item ───────────────────────────────────────────────────────

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
              shape: BoxShape.circle, color: AppColors.avatarBlue),
          child: Center(
              child: Text(initials,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2),
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
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: c)),
    ]);
  }
}
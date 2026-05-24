import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/notification_item.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api  = ApiService();

  List<NotificationItem> _all      = [];
  String                 _filter   = 'All';
  bool                   _loading  = true;

  static const _filters = ['All', 'Unread', 'Ready', 'Review', 'Insight', 'Streak'];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    try {
      final uid = AuthService.userId;
      if (uid.isNotEmpty) {
        final items = await _api.getNotifications(uid);
        if (mounted) setState(() => _all = items);
      }
    } catch (_) {
      // Fall back to empty list — no crash
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<NotificationItem> get _filtered {
    switch (_filter) {
      case 'Unread': return _all.where((n) => !n.isRead).toList();
      case 'All':    return _all;
      default:       return _all.where((n) =>
      n.type.toLowerCase() == _filter.toLowerCase()).toList();
    }
  }

  int get _unreadCount => _all.where((n) => !n.isRead).length;

  // Groups filtered list into Today / Yesterday / Earlier
  Map<String, List<NotificationItem>> get _grouped {
    final groups = <String, List<NotificationItem>>{
      'Today': [], 'Yesterday': [], 'Earlier': [],
    };
    for (final n in _filtered) {
      final diff = DateTime.now().difference(n.createdAt);
      if (diff.inHours < 24)  groups['Today']!.add(n);
      else if (diff.inHours < 48) groups['Yesterday']!.add(n);
      else                    groups['Earlier']!.add(n);
    }
    return groups;
  }

  Future<void> _markRead(String id) async {
    setState(() {
      _all = _all.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList();
    });
    try { await _api.markNotificationRead(id); } catch (_) {}
  }

  Future<void> _markAllRead() async {
    HapticFeedback.lightImpact();
    setState(() => _all = _all.map((n) => n.copyWith(isRead: true)).toList());
    final uid = AuthService.userId;
    if (uid.isNotEmpty) {
      try { await _api.markAllNotificationsRead(uid); } catch (_) {}
    }
  }

  Future<void> _delete(String id) async {
    HapticFeedback.mediumImpact();
    setState(() => _all.removeWhere((n) => n.id == id));
    try { await _api.deleteNotification(id); } catch (_) {}
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDE8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterRow(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadNotifications,
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                child: _loading
                    ? _buildShimmer()
                    : _filtered.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 14, color: AppColors.textSecond),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3)),
                if (_unreadCount > 0)
                  Text('$_unreadCount unread',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecond)),
              ],
            ),
          ),
          // Mark all read
          if (_unreadCount > 0)
            GestureDetector(
              onTap: _markAllRead,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text('Mark all read',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.06);
  }

  Widget _buildFilterRow() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f      = _filters[i];
          final active = _filter == f;
          final label  = f == 'Unread' && _unreadCount > 0
              ? 'Unread · $_unreadCount'
              : f;
          return GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => _filter = f); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:  active ? AppColors.primaryGlow : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? AppColors.primary.withOpacity(0.4)
                      : AppColors.border,
                ),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppColors.primary : AppColors.textSecond)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList() {
    final groups = _grouped;
    const order  = ['Today', 'Yesterday', 'Earlier'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        for (final groupKey in order)
          if (groups[groupKey]!.isNotEmpty) ...[
            _buildGroupHeader(groupKey),
            _buildGroupCard(groups[groupKey]!),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecond,
              letterSpacing: 0.6)),
    );
  }

  Widget _buildGroupCard(List<NotificationItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            _buildTile(items[i], isLast: i == items.length - 1),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildTile(NotificationItem n, {required bool isLast}) {
    final (accent, accentBg, icon) = _tileStyle(n.type);

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(n.id),
      background: Container(
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: AppColors.accentRed),
      ),
      child: GestureDetector(
        onTap: () => _markRead(n.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: n.isRead ? Colors.transparent : AppColors.primary.withOpacity(0.03),
            border: isLast
                ? null
                : Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon bubble
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Icon(icon, size: 18, color: accent)),
              ),
              const SizedBox(width: 12),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(n.title,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: n.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                      if (!n.isRead)
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.textBody
                                .withOpacity(n.isRead ? 0.75 : 1.0))),
                    const SizedBox(height: 4),
                    Text(n.timeLabel,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecond)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Map notification type → (accent color, bg color, icon)
  (Color, Color, IconData) _tileStyle(String type) {
    switch (type) {
      case 'ready':
        return (AppColors.primary, AppColors.primaryGlow,
        Icons.insert_drive_file_outlined);
      case 'review':
        return (AppColors.continueAmber, AppColors.continueAmberBg,
        Icons.style_outlined);
      case 'streak':
        return (AppColors.accentRed, const Color(0xFFFEE2E2),
        Icons.local_fire_department_outlined);
      case 'insight':
        return (AppColors.deltaGreen, const Color(0xFFDCFCE7),
        Icons.trending_up_rounded);
      default:
        return (AppColors.textSecond, AppColors.border,
        Icons.notifications_outlined);
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(20)),
              child: const Center(
                  child: Icon(Icons.notifications_none_rounded,
                      size: 32, color: AppColors.primary)),
            ),
            const SizedBox(height: 18),
            Text('All caught up',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text('No notifications right now.\nWe\'ll ping you when something needs attention.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, height: 1.55, color: AppColors.textSecond)),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: List.generate(4, (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 1100.ms, color: AppColors.primaryGlow)),
      ),
    );
  }
}
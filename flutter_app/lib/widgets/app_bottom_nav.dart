// lib/widgets/app_bottom_nav.dart
// Shared bottom navigation bar — import this on every top-level screen.
//
// Usage:
//   Stack(
//     children: [
//       // ... your page content ...
//       Positioned(
//         left: 0, right: 0, bottom: 0,
//         child: AppBottomNav(currentTab: AppNavTab.home),
//       ),
//     ],
//   )
//
// Wrap your Scaffold body in SafeArea and add
//   const SizedBox(height: 110)   ← as the last sliver/item so content
// doesn't get hidden behind the nav bar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../main.dart' show slideRoute;

// ── Screens (add yours here as you create them) ───────────────────────────────
import '../screens/home_screen.dart';
import '../screens/sr_review_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/shared_sessions_screen.dart';
import '../screens/profile_screen.dart';

// ── Tab enum (shared across the whole app) ────────────────────────────────────
enum AppNavTab { home, review, analytics, community, profile }

class AppBottomNav extends StatelessWidget {
  final AppNavTab currentTab;

  /// Optional callback fired *before* the push so the caller can do
  /// any state clean-up (e.g. reload data after returning from Profile).
  final void Function(AppNavTab tab)? onTabChanged;

  const AppBottomNav({
    super.key,
    required this.currentTab,
    this.onTabChanged,
  });

  // ── Navigation logic ────────────────────────────────────────────────────────

  void _navigate(BuildContext context, AppNavTab tab) async {
    if (tab == currentTab) return;
    HapticFeedback.lightImpact();
    onTabChanged?.call(tab);

    switch (tab) {
      case AppNavTab.home:
      // Pop back to home if we're somewhere else; push if not in stack.
        Navigator.of(context).pushAndRemoveUntil(
          slideRoute(const HomeScreen()),
              (route) => false,
        );
      case AppNavTab.review:
        await Navigator.of(context).push(slideRoute(const SrReviewScreen()));
      case AppNavTab.analytics:
        await Navigator.of(context).push(slideRoute(const AnalyticsScreen()));
      case AppNavTab.community:
        await Navigator.of(context).push(slideRoute(const SharedSessionsScreen()));
      case AppNavTab.profile:
        await Navigator.of(context).push(slideRoute(const ProfileScreen()));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Row(
              children: [
                _NavItem(
                  icon:       Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label:      'Home',
                  selected:   currentTab == AppNavTab.home,
                  onTap:      () => _navigate(context, AppNavTab.home),
                ),
                _NavItem(
                  icon:       Icons.repeat_outlined,
                  activeIcon: Icons.repeat_rounded,
                  label:      'Review',
                  selected:   currentTab == AppNavTab.review,
                  onTap:      () => _navigate(context, AppNavTab.review),
                ),
                _NavItem(
                  icon:       Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart_rounded,
                  label:      'Analytics',
                  selected:   currentTab == AppNavTab.analytics,
                  onTap:      () => _navigate(context, AppNavTab.analytics),
                ),
                _NavItem(
                  icon:       Icons.people_outline_rounded,
                  activeIcon: Icons.people_rounded,
                  label:      'Community',
                  selected:   currentTab == AppNavTab.community,
                  onTap:      () => _navigate(context, AppNavTab.community),
                ),
                _NavItem(
                  icon:       Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label:      'Profile',
                  selected:   currentTab == AppNavTab.profile,
                  onTap:      () => _navigate(context, AppNavTab.profile),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Private nav-item widget ───────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData     icon;
  final IconData     activeIcon;
  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecond;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.w500,
                color:      color,
              ),
            ),
            if (selected)
              Container(
                width:  5,
                height: 5,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
// lib/main.dart
// App entry point — initialises Supabase, then routes to Login or Home
// based on current auth state. No Firebase needed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/sf_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for a consistent mobile experience
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Make status bar transparent so the gradient bleeds through
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:           Colors.transparent,
    statusBarBrightness:      Brightness.dark,
    statusBarIconBrightness:  Brightness.light,
  ));

  // Load .env file
  await dotenv.load(fileName: '.env');

  // Initialise Supabase (free tier, no credit card required)
  await Supabase.initialize(
    url:     dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const StudyforgeApp());
}

// Convenience global — use anywhere: supabase.auth.currentUser etc.
final supabase = Supabase.instance.client;

class StudyforgeApp extends StatelessWidget {
  const StudyforgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                      'Studyforge',
      debugShowCheckedModeBanner: false,
      theme:                      buildAppTheme(),

      // Auth gate: react to Supabase session changes in real time
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // Still waiting for Supabase to respond
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }

          // User is signed in → Home dashboard
          if (supabase.auth.currentSession != null) {
            return const HomeScreen();
          }

          // Not signed in → Login
          return const LoginScreen();
        },
      ),
    );
  }
}

// ── Splash screen shown during Supabase init ──────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SFLogo(size: 72),
              const SizedBox(height: 20),
              Text('Studyforge', style: AppText.display(28)),
              const SizedBox(height: 8),
              Text('Turn documents into mastery', style: AppText.caption),
              const SizedBox(height: 32),
              const SizedBox(
                width:  22,
                height: 22,
                child:  CircularProgressIndicator(
                  color:       AppColors.primary,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared page transition helpers ────────────────────────────────────────────

/// Smooth fade transition (used for auth → home)
Route fadeRoute(Widget page) => PageRouteBuilder(
  pageBuilder:        (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) =>
      FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 380),
);

/// Slide-from-right transition (used for detail screens)
Route slideRoute(Widget page) => PageRouteBuilder(
  pageBuilder:        (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 380),
);

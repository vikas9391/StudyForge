// lib/main.dart
// App entry point — JWT auth state from SharedPreferences.
// Supabase has been removed. Auth is now handled by Django + JWT.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/constants.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'widgets/sf_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
    statusBarBrightness:     Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // Load .env
  await dotenv.load(fileName: '.env');

  // Load cached userId + email into AuthService sync getters.
  await AuthService.init();

  runApp(const StudyforgeApp());
}

// ── App root ──────────────────────────────────────────────────────────────────
// ── App root ──────────────────────────────────────────────────────────────────

final navigatorKey = GlobalKey<NavigatorState>();  // ← move here, top-level

class StudyforgeApp extends StatelessWidget {
  const StudyforgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey:               navigatorKey,   // ← add this
      title:                      'Studyforge',
      debugShowCheckedModeBanner: false,
      theme:                      buildAppTheme(),
      home:                       const AuthGate(),
    );
  }
}

// ── Auth gate — rebuilds whenever login / logout changes ──────────────────────
//
// LoginScreen calls Navigator.pushReplacement → AuthGate (after sign-in).
// HomeScreen calls AuthService.signOut() → Navigator.pushReplacement → AuthGate.
// Both paths trigger a fresh FutureBuilder check.

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _loginFuture;

  @override
  void initState() {
    super.initState();
    _loginFuture = AuthService.isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loginFuture,
      builder: (context, snapshot) {
        // Show splash while checking
        if (!snapshot.hasData) return const SplashScreen();

        if (snapshot.data == true) {
          return HomeScreen(onSignOut: _onSignOut);
        } else {
          return LoginScreen(onSignIn: _onSignIn);
        }
      },
    );
  }

  void _onSignIn() {
    setState(() {
      _loginFuture = AuthService.isLoggedIn();
    });
  }
  void _onSignOut() {
    setState(() {
      _loginFuture = Future.value(false);
    });
  }
}

// ── Splash screen ─────────────────────────────────────────────────────────────
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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

// ── Page transition helpers ───────────────────────────────────────────────────

Route fadeRoute(Widget page) => PageRouteBuilder(
  pageBuilder:        (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) =>
      FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 380),
);

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
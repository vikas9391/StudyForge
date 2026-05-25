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
import '../services/home_cache.dart';


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

  // Load cached userId + email into AuthService sync getters,
  // then proactively refresh the access token so it's ready before
  // HomeScreen._loadData() fires. If the refresh token is also expired,
  // clearTokens() is called inside init() so the user lands on LoginScreen.
  await AuthService.init();

  runApp(const StudyforgeApp());
}

// ── Navigator key — used for programmatic navigation outside widget tree ───────
final navigatorKey = GlobalKey<NavigatorState>();

// ── App root ──────────────────────────────────────────────────────────────────

class StudyforgeApp extends StatelessWidget {
  const StudyforgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey:               navigatorKey,
      title:                      'Studyforge',
      debugShowCheckedModeBanner: false,
      theme:                      buildAppTheme(),
      home:                       const AuthGate(),
    );
  }
}

// ── Auth gate — rebuilds whenever login / logout changes ──────────────────────
//
// After AuthService.init() runs in main(), isLoggedIn() reflects the
// post-refresh state: if both tokens were expired, clearTokens() will have
// wiped the access_token, so isLoggedIn() returns false → LoginScreen.
//
// Sign-in path:  LoginScreen calls onSignIn → _AuthGateState re-checks isLoggedIn()
// Sign-out path: HomeScreen calls onSignOut → _AuthGateState forces false directly

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
    AuthService.onSessionChanged = () {
      HomeCache.instance.invalidate();
    };
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
      // Force immediately to LoginScreen without re-checking prefs,
      // since AuthService.signOut() already cleared all tokens.
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
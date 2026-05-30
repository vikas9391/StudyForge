import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'core/constants.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/auth_service.dart';
import 'services/home_cache.dart';
import 'widgets/sf_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
    statusBarBrightness:     Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  await dotenv.load(fileName: '.env');
  await AuthService.init();

  runApp(const StudyforgeApp());
}

// ── Navigator key ─────────────────────────────────────────────────────────────
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
      home:                       const _DeepLinkHandler(),
    );
  }
}

// ── Deep link handler — wraps AuthGate, intercepts reset links ────────────────

class _DeepLinkHandler extends StatefulWidget {
  const _DeepLinkHandler();

  @override
  State<_DeepLinkHandler> createState() => _DeepLinkHandlerState();
}

class _DeepLinkHandlerState extends State<_DeepLinkHandler> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // App already running — link arrives as stream event
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });

    // App cold-started by tapping the link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'studyforge' && uri.host == 'reset-password') {
      final uid   = uri.queryParameters['uid']   ?? '';
      final token = uri.queryParameters['token'] ?? '';
      if (uid.isNotEmpty && token.isNotEmpty) {
        // Small delay ensures the navigator is mounted
        Future.delayed(const Duration(milliseconds: 200), () {
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => ResetPasswordScreen(uid: uid, token: token),
          ));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => const AuthGate();
}

// ── Auth gate ─────────────────────────────────────────────────────────────────

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
    // FIX: Small delay lets Flutter finish rendering the first frame before
    // making any I/O calls, preventing main-thread overload on startup.
    _loginFuture = Future.delayed(
      const Duration(milliseconds: 150),
          () => AuthService.isLoggedIn(),
    );
    AuthService.onSessionChanged = () {
      HomeCache.instance.invalidate();
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loginFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SplashScreen();
        if (snapshot.data == true) {
          return HomeScreen(onSignOut: _onSignOut);
        } else {
          return LoginScreen(onSignIn: _onSignIn);
        }
      },
    );
  }

  void _onSignIn() => setState(() {
    _loginFuture = AuthService.isLoggedIn();
  });

  void _onSignOut() => setState(() {
    _loginFuture = Future.value(false);
  });
}

// ── Splash screen ─────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
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
              // 1. Logo — scales in with elastic bounce + shimmer sweep
              const SFLogo(size: 110),

              const SizedBox(height: 24),

              // 2. App name — slides up after logo lands
              Text('Studyforge', style: AppText.display(28))
                  .animate()
                  .slideY(
                begin: 0.4,
                end: 0,
                delay: 600.ms,
                duration: 500.ms,
                curve: Curves.easeOutCubic,
              )
                  .fadeIn(delay: 600.ms, duration: 500.ms),

              const SizedBox(height: 8),

              // 3. Tagline — fades in a bit after
              Text('Turn documents into mastery', style: AppText.caption)
                  .animate()
                  .fadeIn(delay: 900.ms, duration: 500.ms)
                  .slideY(
                begin: 0.3,
                end: 0,
                delay: 900.ms,
                duration: 400.ms,
                curve: Curves.easeOut,
              ),

              const SizedBox(height: 40),

              // 4. Spinner — appears last
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              )
                  .animate()
                  .fadeIn(delay: 1100.ms, duration: 400.ms),
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
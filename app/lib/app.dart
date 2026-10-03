import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/courses_screen.dart';
import 'screens/login_screen.dart';
import 'screens/no_access_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/auth_service.dart';
import 'services/data_service.dart';

class SecureEduApp extends StatelessWidget {
  const SecureEduApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Edu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Routes the student based on auth + verification + subscription state:
///
///   signed out ─────────────► LoginScreen
///   email not verified ─────► VerifyEmailScreen
///   no active subscription ─► NoAccessScreen
///   active subscription ────► CoursesScreen
///
/// This is UX only; the backend independently enforces every check.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.userChanges,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        if (!user.emailVerified) {
          return VerifyEmailScreen(email: user.email ?? '');
        }
        final email = user.email ?? '';
        return StreamBuilder<Subscription?>(
          // Key on uid so switching accounts resubscribes cleanly.
          key: ValueKey(user.uid),
          stream: DataService.instance.subscription(email),
          builder: (context, sub) {
            if (sub.connectionState == ConnectionState.waiting) {
              return const _Splash();
            }
            final s = sub.data;
            if (s == null || !s.isActive) {
              return NoAccessScreen(email: email, subscription: s);
            }
            return CoursesScreen(subscription: s);
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Email/password accounts must prove they own the address before the
/// subscription (which is keyed by email) is honoured. Google accounts are
/// already verified and never see this screen.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyAuthError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 72),
            const SizedBox(height: 16),
            Text(
              'We sent a verification link to ${widget.email}. '
              'Open it, then tap the button below.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _do(AuthService.instance.reloadUser, ''),
              child: const Text("I've verified my email"),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _do(
                      AuthService.instance.resendVerification,
                      'Verification email sent again.',
                    ),
              child: const Text('Resend email'),
            ),
            TextButton(
              onPressed: _busy ? null : AuthService.instance.signOut,
              child: const Text('Use a different account'),
            ),
          ],
        ),
      ),
    );
  }
}

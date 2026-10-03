import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key, required this.email, this.subscription});

  final String email;
  final Subscription? subscription;

  @override
  Widget build(BuildContext context) {
    final expired = subscription != null && !subscription!.isActive;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access pending'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              expired ? Icons.timer_off_outlined : Icons.lock_outline,
              size: 72,
            ),
            const SizedBox(height: 16),
            Text(
              expired
                  ? 'Your subscription has expired.'
                  : 'This email is not on the approved students list yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Signed in as $email.\n'
              'Contact ${AppConfig.supportEmail} to activate access. '
              'This screen updates automatically once you are approved.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: AuthService.instance.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

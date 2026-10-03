import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<StudentProfile?>(
        stream: DataService.instance.profile(user.uid),
        builder: (context, snap) {
          final p = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(p?.name.isNotEmpty == true ? p!.name : '—'),
                subtitle: const Text('Name'),
                trailing: p == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _edit(context, p),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: Text(user.email ?? ''),
                subtitle: const Text('Email'),
              ),
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: Text(p?.phone?.isNotEmpty == true ? p!.phone! : '—'),
                subtitle: const Text('Phone'),
              ),
              const Divider(),
              StreamBuilder<Subscription?>(
                stream: DataService.instance.subscription(user.email ?? ''),
                builder: (context, s) {
                  final sub = s.data;
                  final expiry = sub?.expiresAt == null
                      ? 'No expiry'
                      : 'Valid till '
                            '${DateFormat.yMMMd().format(sub!.expiresAt!)}';
                  return ListTile(
                    leading: Icon(
                      sub?.isActive == true
                          ? Icons.verified
                          : Icons.error_outline,
                    ),
                    title: Text(
                      sub?.isActive == true
                          ? 'Active${sub!.plan != null ? ' · ${sub.plan}' : ''}'
                          : 'No active subscription',
                    ),
                    subtitle: Text(sub?.isActive == true ? expiry : ''),
                  );
                },
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.phone_android),
                title: Text('This account is locked to one device'),
                subtitle: Text(
                  'Changing phones? Ask support to reset your device.',
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                onPressed: () async {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  await AuthService.instance.signOut();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, StudentProfile p) async {
    final name = TextEditingController(text: p.name);
    final phone = TextEditingController(text: p.phone);
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true && name.text.trim().isNotEmpty) {
      await DataService.instance.updateProfile(
        p.uid,
        name: name.text,
        phone: phone.text,
      );
    }
    name.dispose();
    phone.dispose();
  }
}

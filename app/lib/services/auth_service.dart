import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _googleInitialized = false;

  /// Emits on sign-in, sign-out AND profile changes (e.g. after
  /// `reload()` flips `emailVerified`), which the auth gate relies on.
  Stream<User?> get userChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(name.trim());
    await _ensureProfile(user, name: name.trim(), phone: phone?.trim());
    await user.sendEmailVerification();
  }

  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(serverClientId: AppConfig.googleServerClientId);
      _googleInitialized = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return an ID token.',
      );
    }
    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    await _ensureProfile(cred.user!, name: account.displayName ?? '');
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> resendVerification() async =>
      _auth.currentUser?.sendEmailVerification();

  /// Re-fetches the user so a freshly verified email is picked up, and
  /// force-refreshes the ID token so Firestore rules see
  /// `email_verified == true` immediately.
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
  }

  Future<void> signOut() async {
    if (_googleInitialized) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  /// Creates `users/{uid}` on first sign-in. Firestore rules only allow the
  /// whitelisted fields below, so a client can never grant itself access.
  Future<void> _ensureProfile(User user, {String? name, String? phone}) async {
    final ref = _db.collection('users').doc(user.uid);
    if ((await ref.get()).exists) return;
    await ref.set({
      'name':
          _nonEmpty(name) ??
          _nonEmpty(user.displayName) ??
          user.email!.split('@').first,
      'email': user.email,
      'phone': phone ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

String? _nonEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

/// Maps Firebase error codes to messages students can act on.
String friendlyAuthError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for this email. Try logging in.';
      case 'weak-password':
        return 'Password must be at least 8 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and retry.';
      case 'network-request-failed':
        return 'No internet connection.';
    }
    return e.message ?? 'Sign-in failed (${e.code}).';
  }
  if (e is GoogleSignInException) {
    return e.code == GoogleSignInExceptionCode.canceled
        ? 'Google sign-in was cancelled.'
        : 'Google sign-in failed: ${e.description ?? e.code.name}';
  }
  return 'Something went wrong. Please try again.';
}

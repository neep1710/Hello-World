/// App-wide configuration. Keep secrets OUT of this file: everything here
/// ships inside the APK and can be read by anyone who decompiles it.
class AppConfig {
  AppConfig._();

  /// Region your Cloud Functions are deployed to (see functions/src/index.ts).
  static const functionsRegion = 'asia-south1';

  /// OAuth "Web client ID" from Firebase console → Authentication →
  /// Sign-in method → Google → Web SDK configuration. Required on Android
  /// so Google Sign-In returns an ID token Firebase can verify.
  static const googleServerClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';

  /// Playback speeds offered by the player.
  static const playbackSpeeds = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

  /// Support contact shown to students without an active subscription.
  static const supportEmail = 'support@yourinstitute.com';
}

// PLACEHOLDER — regenerate with:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=<your-firebase-project-id> --platforms=android,ios
// That command overwrites this file with your project's real values.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured for $defaultTargetPlatform. '
      'Run `flutterfire configure` (see docs/BLUEPRINT.md, step 2).',
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Screen-capture protection.
///
/// * Android: `FLAG_SECURE` is set on the whole window in `MainActivity.kt`
///   before Flutter draws its first frame. Screenshots, screen recordings,
///   the Recents thumbnail and casting to non-secure displays all show
///   black. Nothing to do from Dart.
/// * iOS: Apple offers no API to *block* capture. The native side
///   (`ScreenSecurityPlugin.swift`) reports when the screen is being
///   recorded/mirrored, and the player hides and pauses the video while
///   that is true.
class ScreenSecurity {
  ScreenSecurity._();

  static const _events = EventChannel('secure_edu/screen_capture');

  /// Emits `true` while the screen is being recorded or mirrored (iOS).
  /// Always `false` on Android, where FLAG_SECURE already blanks output.
  static Stream<bool> get isCaptured {
    if (!Platform.isIOS) return Stream.value(false);
    return _events.receiveBroadcastStream().map((e) => e == true);
  }
}

import 'package:cloud_functions/cloud_functions.dart';

import '../config.dart';
import 'device_id.dart';

class PlaybackGrant {
  const PlaybackGrant({
    required this.url,
    required this.expiresAt,
    required this.watermark,
  });

  /// Short-lived, per-student signed HLS URL. Never persist or display it.
  final Uri url;
  final DateTime expiresAt;
  final String watermark;
}

class PlaybackException implements Exception {
  const PlaybackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks the backend for a signed stream URL. The backend re-checks auth,
/// e-mail verification, subscription, course entitlement, device binding
/// and App Check before signing anything.
class PlaybackService {
  PlaybackService._();
  static final instance = PlaybackService._();

  final _fn = FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
      .httpsCallable('getPlaybackToken');

  Future<PlaybackGrant> requestPlayback({
    required String courseId,
    required String videoId,
  }) async {
    try {
      final res = await _fn.call<Map<String, dynamic>>({
        'courseId': courseId,
        'videoId': videoId,
        'deviceId': await DeviceId.get(),
      });
      final data = res.data;
      return PlaybackGrant(
        url: Uri.parse(data['url'] as String),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (data['expiresAt'] as num).toInt(),
        ),
        watermark: data['watermark'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      throw PlaybackException(_message(e));
    }
  }

  String _message(FirebaseFunctionsException e) {
    switch (e.message) {
      case 'DEVICE_MISMATCH':
        return 'Your account is registered on another device. '
            'Contact ${AppConfig.supportEmail} to move it to this phone.';
      case 'NOT_SUBSCRIBED':
        return 'Your subscription does not include this course.';
      case 'EMAIL_NOT_VERIFIED':
        return 'Please verify your email address first.';
    }
    if (e.code == 'unauthenticated') return 'Please sign in again.';
    if (e.code == 'unavailable') return 'No internet connection.';
    return 'Unable to start playback (${e.code}).';
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class StudentProfile {
  const StudentProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
  });

  final String uid;
  final String name;
  final String email;
  final String? phone;

  factory StudentProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StudentProfile(
      uid: doc.id,
      name: d['name'] as String? ?? '',
      email: d['email'] as String? ?? '',
      phone: d['phone'] as String?,
    );
  }
}

class Subscription {
  const Subscription({
    required this.status,
    required this.courseIds,
    this.plan,
    this.expiresAt,
  });

  final String status;
  final List<String> courseIds;
  final String? plan;
  final DateTime? expiresAt;

  /// UI-side check only. The real gate is enforced server-side in the
  /// `getPlaybackToken` Cloud Function before any video URL is issued.
  bool get isActive =>
      status == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  bool coversCourse(String courseId) =>
      isActive && (courseIds.contains('*') || courseIds.contains(courseId));

  factory Subscription.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Subscription(
      status: d['status'] as String? ?? 'inactive',
      courseIds: List<String>.from(d['courseIds'] as List? ?? const []),
      plan: d['plan'] as String?,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
    );
  }
}

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.description,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String description;
  final String? thumbnailUrl;

  factory Course.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Course(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      thumbnailUrl: d['thumbnailUrl'] as String?,
    );
  }
}

class Chapter {
  const Chapter({required this.id, required this.title, required this.order});

  final String id;
  final String title;
  final int order;

  factory Chapter.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Chapter(
      id: doc.id,
      title: d['title'] as String? ?? '',
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Public lecture metadata. Note there is deliberately NO video URL or
/// provider ID here: those live in `videoSources/{videoId}`, which only the
/// Cloud Function can read.
class Lecture {
  const Lecture({
    required this.id,
    required this.courseId,
    required this.chapterId,
    required this.title,
    required this.order,
    required this.durationSec,
  });

  final String id;
  final String courseId;
  final String chapterId;
  final String title;
  final int order;
  final int durationSec;

  String get durationLabel {
    final d = Duration(seconds: durationSec);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  factory Lecture.fromDoc(
    String courseId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return Lecture(
      id: doc.id,
      courseId: courseId,
      chapterId: d['chapterId'] as String? ?? '',
      title: d['title'] as String? ?? '',
      order: (d['order'] as num?)?.toInt() ?? 0,
      durationSec: (d['durationSec'] as num?)?.toInt() ?? 0,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';

/// Read-only access to profile, subscription and course catalogue.
/// All writes except the student's own name/phone are blocked by
/// Firestore rules and happen via the Admin SDK (see functions/scripts).
class DataService {
  DataService._();
  static final instance = DataService._();

  final _db = FirebaseFirestore.instance;

  Stream<StudentProfile?> profile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? StudentProfile.fromDoc(d) : null);

  Future<void> updateProfile(
    String uid, {
    required String name,
    String? phone,
  }) => _db.collection('users').doc(uid).update({
    'name': name.trim(),
    'phone': (phone ?? '').trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Subscriptions are keyed by lower-cased email so an admin can approve a
  /// student before they have ever installed the app.
  Stream<Subscription?> subscription(String email) => _db
      .collection('subscriptions')
      .doc(email.toLowerCase())
      .snapshots()
      .map((d) => d.exists ? Subscription.fromDoc(d) : null);

  Stream<List<Course>> publishedCourses() => _db
      .collection('courses')
      .where('published', isEqualTo: true)
      .orderBy('order')
      .snapshots()
      .map((s) => s.docs.map(Course.fromDoc).toList());

  Future<List<Chapter>> chapters(String courseId) async {
    final s = await _db
        .collection('courses/$courseId/chapters')
        .orderBy('order')
        .get();
    return s.docs.map(Chapter.fromDoc).toList();
  }

  Future<List<Lecture>> lectures(String courseId) async {
    final s = await _db
        .collection('courses/$courseId/videos')
        .orderBy('order')
        .get();
    return s.docs.map((d) => Lecture.fromDoc(courseId, d)).toList();
  }
}

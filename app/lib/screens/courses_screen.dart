import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_service.dart';
import 'course_detail_screen.dart';
import 'profile_screen.dart';

class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key, required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Courses'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
      body: StreamBuilder<List<Course>>(
        stream: DataService.instance.publishedCourses(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load courses.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final courses = snap.data!
              .where((c) => subscription.coversCourse(c.id))
              .toList();
          if (courses.isEmpty) {
            return const Center(
              child: Text('No courses are assigned to your account yet.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: courses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final c = courses[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundImage: c.thumbnailUrl == null
                        ? null
                        : NetworkImage(c.thumbnailUrl!),
                    child: c.thumbnailUrl == null
                        ? const Icon(Icons.menu_book)
                        : null,
                  ),
                  title: Text(c.title),
                  subtitle: Text(
                    c.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CourseDetailScreen(course: c),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

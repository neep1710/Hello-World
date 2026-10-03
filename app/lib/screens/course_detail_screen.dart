import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_service.dart';
import 'player_screen.dart';

/// Chapter-wise lecture list for one course.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.course});

  final Course course;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final Future<(List<Chapter>, List<Lecture>)> _load = _fetch();

  Future<(List<Chapter>, List<Lecture>)> _fetch() async {
    final data = DataService.instance;
    final results = await Future.wait([
      data.chapters(widget.course.id),
      data.lectures(widget.course.id),
    ]);
    return (results[0] as List<Chapter>, results[1] as List<Lecture>);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.course.title)),
      body: FutureBuilder<(List<Chapter>, List<Lecture>)>(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load lectures.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (chapters, lectures) = snap.data!;
          if (chapters.isEmpty) {
            return const Center(child: Text('Lectures coming soon.'));
          }
          return ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, i) {
              final ch = chapters[i];
              final items = lectures
                  .where((l) => l.chapterId == ch.id)
                  .toList();
              return ExpansionTile(
                initiallyExpanded: i == 0,
                title: Text('Chapter ${i + 1}: ${ch.title}'),
                subtitle: Text('${items.length} lectures'),
                children: [
                  for (final l in items)
                    ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(l.title),
                      trailing: Text(l.durationLabel),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(lecture: l),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

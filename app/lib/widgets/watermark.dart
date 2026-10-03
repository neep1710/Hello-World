import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Faint, periodically relocating text (student email + short ID) drawn
/// over the video. It cannot stop someone filming the screen with another
/// phone, but every leaked copy identifies the account that leaked it.
class MovingWatermark extends StatefulWidget {
  const MovingWatermark({super.key, required this.text});

  final String text;

  @override
  State<MovingWatermark> createState() => _MovingWatermarkState();
}

class _MovingWatermarkState extends State<MovingWatermark> {
  final _rng = Random();
  late Timer _timer;
  Alignment _alignment = Alignment.topLeft;

  @override
  void initState() {
    super.initState();
    _move();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _move());
  }

  void _move() => setState(() {
    _alignment = Alignment(
      _rng.nextDouble() * 1.6 - 0.8,
      _rng.nextDouble() * 1.6 - 0.8,
    );
  });

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedAlign(
        alignment: _alignment,
        duration: const Duration(seconds: 2),
        curve: Curves.easeInOut,
        child: Text(
          widget.text,
          style: const TextStyle(
            color: Color(0x4DFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 2, color: Color(0x40000000))],
          ),
        ),
      ),
    );
  }
}

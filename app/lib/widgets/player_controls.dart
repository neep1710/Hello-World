import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config.dart';

/// Fully custom controls: play/pause, ±10s, scrubber, speed and
/// fullscreen. There is no share, download, copy-link or "open in
/// browser" affordance anywhere in the player.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.visible,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onInteraction,
  });

  final VideoPlayerController controller;
  final bool visible;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onInteraction;

  void _seekBy(Duration delta) {
    final v = controller.value;
    var target = v.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > v.duration) target = v.duration;
    controller.seekTo(target);
    onInteraction();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          color: Colors.black38,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, v, _) => Column(
              children: [
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundButton(
                      icon: Icons.replay_10,
                      onPressed: () => _seekBy(const Duration(seconds: -10)),
                    ),
                    const SizedBox(width: 24),
                    _RoundButton(
                      icon: v.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 56,
                      onPressed: () {
                        v.isPlaying ? controller.pause() : controller.play();
                        onInteraction();
                      },
                    ),
                    const SizedBox(width: 24),
                    _RoundButton(
                      icon: Icons.forward_10,
                      onPressed: () => _seekBy(const Duration(seconds: 10)),
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    colors: VideoProgressColors(
                      playedColor: Theme.of(context).colorScheme.primary,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Text(
                      '${_fmt(v.position)} / ${_fmt(v.duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const Spacer(),
                    _SpeedButton(
                      speed: v.playbackSpeed,
                      onSelected: (s) {
                        controller.setPlaybackSpeed(s);
                        onInteraction();
                      },
                    ),
                    IconButton(
                      color: Colors.white,
                      icon: Icon(
                        isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      ),
                      onPressed: onToggleFullscreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    this.size = 36,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    iconSize: size,
    color: Colors.white,
    icon: Icon(icon),
    onPressed: onPressed,
  );
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.onSelected});

  final double speed;
  final ValueChanged<double> onSelected;

  static String _label(double s) =>
      s == s.truncateToDouble() ? '${s.toInt()}x' : '${s}x';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final s in AppConfig.playbackSpeeds)
          PopupMenuItem(value: s, child: Text(_label(s))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          _label(speed),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

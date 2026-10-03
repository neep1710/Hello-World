import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../security/screen_security.dart';
import '../services/playback_service.dart';
import '../widgets/player_controls.dart';
import '../widgets/watermark.dart';

/// Secure in-app player.
///
/// * The stream URL is a short-lived signed token fetched per play; it is
///   never shown, logged, copied or stored.
/// * No platform/YouTube chrome: no title links, share, "watch on"
///   buttons or related videos. Only the custom [PlayerControls].
/// * A moving watermark identifies the viewer.
/// * Playback pauses when the app is backgrounded and, on iOS, the video is
///   hidden while the screen is recorded or mirrored.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.lecture});

  final Lecture lecture;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String _watermark = '';
  String? _error;
  bool _captured = false;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  Timer? _hideTimer;
  StreamSubscription<bool>? _captureSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _captureSub = ScreenSecurity.isCaptured.listen((captured) {
      if (captured) _controller?.pause();
      setState(() => _captured = captured);
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final grant = await PlaybackService.instance.requestPlayback(
        courseId: widget.lecture.courseId,
        videoId: widget.lecture.id,
      );
      final controller = VideoPlayerController.networkUrl(
        grant.url,
        formatHint: VideoFormat.hls,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _watermark = grant.watermark;
      });
      if (!_captured) await controller.play();
      _scheduleHide();
    } on PlaybackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load the video. Please retry.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _restoreSystemUi();
    }
    if (mounted) setState(() {});
    _scheduleHide();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _captureSub?.cancel();
    _controller?.dispose();
    WakelockPlus.disable();
    if (_fullscreen) _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = AspectRatio(
      aspectRatio: _controller?.value.isInitialized == true
          ? _controller!.value.aspectRatio
          : 16 / 9,
      child: _buildPlayer(),
    );

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                title: Text(widget.lecture.title),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
        body: SafeArea(
          child: _fullscreen
              ? Center(child: player)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    player,
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.lecture.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    if (_captured) {
      return const Center(
        child: Text(
          'Screen recording or mirroring detected.\n'
          'Stop it to continue watching.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    final c = _controller;
    if (c == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(c),
          MovingWatermark(text: _watermark),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, v, _) => v.isBuffering
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink(),
          ),
          PlayerControls(
            controller: c,
            visible: _controlsVisible,
            isFullscreen: _fullscreen,
            onToggleFullscreen: _toggleFullscreen,
            onInteraction: _scheduleHide,
          ),
        ],
      ),
    );
  }
}

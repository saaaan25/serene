import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Custom StreamAudioSource that serves raw PCM audio data from memory
/// without ever writing to disk, ensuring volatile in-memory playback
class InMemoryAudioSource extends StreamAudioSource {
  final Uint8List audioData;

  InMemoryAudioSource({required this.audioData});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // Return the requested range of audio bytes
    final length = audioData.length;
    final actualStart = (start ?? 0);
    final actualEnd = (end ?? length);

    if (actualStart >= actualEnd || actualStart >= length) {
      return StreamAudioResponse(
        contentLength: 0,
        offset: actualStart,
        sourceLength: length,
        stream: Stream.empty(),
        contentType: 'audio/wav',
      );
    }

    final data = audioData.sublist(actualStart, actualEnd > length ? length : actualEnd);

    return StreamAudioResponse(
      contentLength: data.length,
      offset: actualStart,
      sourceLength: length,
      stream: Stream.value(data),
      contentType: 'audio/wav',
    );
  }
}

/// Widget that plays in-memory audio with full playback controls
/// Implements Play/Pause, progress slider, and time display
/// SECURITY: Never writes audio to disk; all data stays in RAM
class InMemoryAudioPlayer extends StatefulWidget {
  final Uint8List audioData;
  final String? title;
  final VoidCallback? onDispose;

  const InMemoryAudioPlayer({
    super.key,
    required this.audioData,
    this.title,
    this.onDispose,
  });

  @override
  State<InMemoryAudioPlayer> createState() => _InMemoryAudioPlayerState();
}

class _InMemoryAudioPlayerState extends State<InMemoryAudioPlayer> {
  late AudioPlayer _audioPlayer;
  late StreamSubscription<PlayerState> _playerStateSubscription;
  late StreamSubscription<Duration> _positionSubscription;
  late StreamSubscription<Duration?> _durationSubscription;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _playerStateSubscription =
        _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    _durationSubscription =
        _audioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration ?? Duration.zero;
        });
      }
    });
  }

  Future<void> _initializeAudio() async {
    try {
      final source = InMemoryAudioSource(audioData: widget.audioData);
      await _audioPlayer.setAudioSource(source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading audio: $e')),
        );
      }
    }
  }

  void _togglePlayPause() async {
    if (_totalDuration == Duration.zero) {
      await _initializeAudio();
    }

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  void _onSliderChanged(double value) {
    _audioPlayer.seek(Duration(milliseconds: value.toInt()));
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2b49), // Surface Bright
        borderRadius: BorderRadius.circular(24.0), // ROUND_FULL
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          if (widget.title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                widget.title!,
                style: const TextStyle(
                  color: Color(0xFFdee5ff), // On-Surface
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Play/Pause Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 56.0,
                height: 56.0,
                decoration: BoxDecoration(
                  color: const Color(0xFFa1d1fe), // Primary Blue
                  borderRadius: BorderRadius.circular(28.0), // ROUND_FULL
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28.0,
                ),
              ),
            ),
          ),

          // Progress Slider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Slider(
              value: _currentPosition.inMilliseconds.toDouble(),
              max: _totalDuration.inMilliseconds.toDouble() > 0
                  ? _totalDuration.inMilliseconds.toDouble()
                  : 1.0,
              onChanged: _onSliderChanged,
              activeColor: const Color(0xFFa1d1fe), // Primary
              inactiveColor:
                  const Color(0xFF40485d).withOpacity(0.3), // Outline-Variant
            ),
          ),

          // Time Display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_currentPosition),
                  style: const TextStyle(
                    color: Color(0xFFdee5ff), // On-Surface
                    fontSize: 12.0,
                  ),
                ),
                Text(
                  _formatDuration(_totalDuration),
                  style: const TextStyle(
                    color: Color(0xFF40485d), // Outline-Variant
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up subscriptions
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();

    // Dispose audio player and purge volatile buffer
    _audioPlayer.dispose();

    // Notify parent if callback is provided
    widget.onDispose?.call();

    super.dispose();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Durée maximale d'un message vocal : l'enregistrement s'arrête et part
/// tout seul au-delà.
const kMaxVoiceDuration = Duration(minutes: 2);

String formatVoiceDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Enregistrement terminé, prêt à être envoyé.
class VoiceRecording {
  final File file;
  final Duration duration;

  const VoiceRecording(this.file, this.duration);
}

/// Demande l'accès au micro. Renvoie `false` si l'utilisateur refuse.
Future<bool> requestMicrophone() => AudioRecorder().hasPermission();

/// Barre affichée à la place du champ de saisie pendant l'enregistrement :
/// point rouge pulsant, chrono, bouton corbeille et bouton d'envoi.
/// L'enregistrement démarre dès l'affichage.
class VoiceRecorderBar extends StatefulWidget {
  final ValueChanged<VoiceRecording> onSend;
  final VoidCallback onCancel;

  const VoiceRecorderBar({super.key, required this.onSend, required this.onCancel});

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // AAC mono 64 kb/s : ~500 Ko par minute, largement assez pour la voix.
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
        path: path,
      );
      _stopwatch.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => _elapsed = _stopwatch.elapsed);
        if (_elapsed >= kMaxVoiceDuration) _send();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de démarrer l’enregistrement.')),
      );
      widget.onCancel();
    }
  }

  Future<void> _send() async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    _stopwatch.stop();
    final duration = _stopwatch.elapsed;
    final path = await _recorder.stop();
    // Un appui accidentel (< 1 s) n'envoie rien.
    if (path == null || duration < const Duration(seconds: 1)) {
      if (path != null) unawaited(File(path).delete().catchError((_) => File(path)));
      widget.onCancel();
      return;
    }
    widget.onSend(VoiceRecording(File(path), duration));
  }

  Future<void> _cancel() async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    await _recorder.cancel();
    widget.onCancel();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    if (!_finished) _recorder.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _cancel,
              tooltip: 'Annuler l’enregistrement',
              icon: const Icon(Icons.delete_outline_rounded, size: 26, color: AppColors.danger),
            ),
            const SizedBox(width: 4),
            FadeTransition(
              opacity: Tween<double>(begin: 0.25, end: 1).animate(_pulse),
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatVoiceDuration(_elapsed),
              style: AppTextStyles.bodyLargeSemibold.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enregistrement…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
              ),
            ),
            Semantics(
              button: true,
              label: 'Envoyer le message vocal',
              child: Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _send,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lecteur d'un message vocal dans une bulle : lecture / pause, barre de
/// progression déplaçable et durée. Un seul message joue à la fois.
class VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final Duration duration;

  /// Couleur du texte et des icônes, selon la bulle (envoyée / reçue).
  final Color color;

  const VoiceMessagePlayer({
    super.key,
    required this.url,
    required this.duration,
    required this.color,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  static _VoiceMessagePlayerState? _playing;

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;

  Duration get _total => _player?.duration ?? widget.duration;

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    _stateSub = player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        player.pause();
        player.seek(Duration.zero);
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
        return;
      }
      setState(() {
        _isPlaying = state.playing;
        _isLoading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
      });
    });
    _positionSub = player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    await player.setUrl(widget.url);
    return player;
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _player?.pause();
        return;
      }
      if (_playing != null && _playing != this) await _playing!._player?.pause();
      _playing = this;
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
      final player = await _ensurePlayer();
      unawaited(player.play());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    if (_playing == this) _playing = null;
    _stateSub?.cancel();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total.inMilliseconds > 0 ? _total : widget.duration;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final shown = _isPlaying || _position > Duration.zero ? _position : total;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: _isPlaying ? 'Pause' : 'Écouter le message vocal',
            child: InkResponse(
              onTap: _isLoading ? null : _toggle,
              radius: 24,
              child: SizedBox(
                width: 36,
                height: 36,
                child: _isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: widget.color),
                      )
                    : Icon(
                        _hasError
                            ? Icons.error_outline_rounded
                            : (_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        size: 32,
                        color: widget.color,
                      ),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: widget.color,
                inactiveTrackColor: widget.color.withValues(alpha: 0.3),
                thumbColor: widget.color,
              ),
              child: Slider(
                value: progress,
                onChanged: _player == null
                    ? null
                    : (v) => _player!.seek(Duration(milliseconds: (v * total.inMilliseconds).round())),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatVoiceDuration(shown),
            style: AppTextStyles.caption.copyWith(
              color: widget.color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

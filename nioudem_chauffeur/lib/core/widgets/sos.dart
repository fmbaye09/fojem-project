import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Appels réseau du SOS, implémentés par chaque app (clients API différents).
abstract class SosApi {
  /// Déclenche l'alerte (ou réutilise celle en cours) et renvoie son id.
  Future<String> trigger({required double lat, required double lng, String? tripId, String? bookingId, required String role});
  Future<void> sendLocation(String alertId, double lat, double lng);
  Future<void> uploadRecording(String alertId, String filePath, Duration duration);
  Future<void> end(String alertId);
}

/// Bouton SOS rouge : il faut **appuyer 2 secondes** pour déclencher, afin
/// d'éviter les fausses alertes (anneau de progression + vibration).
class SosButton extends StatefulWidget {
  final VoidCallback onTriggered;

  const SosButton({super.key, required this.onTriggered});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _hold.reset();
        widget.onTriggered();
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _start() {
    HapticFeedback.mediumImpact();
    _hold.forward(from: 0);
  }

  void _cancel() {
    if (_hold.isAnimating) _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'SOS : maintenir appuyé 2 secondes pour alerter FOJËM',
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _cancel(),
        onTapCancel: _cancel,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          decoration: BoxDecoration(
            color: AppColors.dangerSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: AnimatedBuilder(
                  animation: _hold,
                  builder: (context, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _hold.value,
                          strokeWidth: 4,
                          color: AppColors.danger,
                          backgroundColor: AppColors.danger.withValues(alpha: 0.15),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          'SOS',
                          style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Urgence pendant le trajet ?',
                        style: AppTextStyles.bodySemibold.copyWith(color: AppColors.danger)),
                    Text('Maintenez le bouton 2 secondes pour alerter FOJËM.', style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ouvre l'écran SOS plein écran (alerte, enregistrement, position, appels).
Future<void> openSosScreen(
  BuildContext context, {
  required SosApi api,
  required String role,
  String? tripId,
  String? bookingId,
  ({double lat, double lng})? fallbackPosition,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SosScreen(
        api: api,
        role: role,
        tripId: tripId,
        bookingId: bookingId,
        fallbackPosition: fallbackPosition,
      ),
    ),
  );
}

/// Alerte en cours : l'alerte part tout de suite, puis la position est
/// envoyée toutes les 15 s et le son enregistré par morceaux de 30 s
/// (envoyés au fil de l'eau : rien n'est perdu si le téléphone disparaît).
/// S'arrête sur « Je suis en sécurité » ou au bout de 10 minutes.
class SosScreen extends StatefulWidget {
  final SosApi api;
  final String role;
  final String? tripId;
  final String? bookingId;
  final ({double lat, double lng})? fallbackPosition;

  const SosScreen({
    super.key,
    required this.api,
    required this.role,
    this.tripId,
    this.bookingId,
    this.fallbackPosition,
  });

  static const chunkDuration = Duration(seconds: 30);
  static const locationInterval = Duration(seconds: 15);
  static const maxDuration = Duration(minutes: 10);

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _SosState { sending, active, failed, ended }

class _SosScreenState extends State<SosScreen> {
  final _recorder = AudioRecorder();
  final _stopwatch = Stopwatch();
  final List<Future<void>> _uploads = [];
  Timer? _ticker;
  Timer? _locationTimer;
  Timer? _chunkTimer;
  String? _alertId;
  _SosState _state = _SosState.sending;
  bool _recording = false;
  bool _closing = false;
  String? _chunkPath;
  DateTime? _chunkStartedAt;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<Position?> _position() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return Geolocator.getLastKnownPosition().catchError((_) => null);
    }
  }

  Future<void> _start() async {
    setState(() => _state = _SosState.sending);
    final position = await _position();
    final lat = position?.latitude ?? widget.fallbackPosition?.lat;
    final lng = position?.longitude ?? widget.fallbackPosition?.lng;
    try {
      _alertId = await widget.api.trigger(
        lat: lat ?? 0,
        lng: lng ?? 0,
        tripId: widget.tripId,
        bookingId: widget.bookingId,
        role: widget.role,
      );
    } catch (_) {
      if (mounted) setState(() => _state = _SosState.failed);
      return;
    }
    if (!mounted) return;
    setState(() => _state = _SosState.active);
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_stopwatch.elapsed >= SosScreen.maxDuration) _finish();
    });
    _locationTimer = Timer.periodic(SosScreen.locationInterval, (_) => _sendLocation());
    await _startChunk();
  }

  Future<void> _sendLocation() async {
    final id = _alertId;
    if (id == null) return;
    final position = await _position();
    if (position == null) return;
    try {
      await widget.api.sendLocation(id, position.latitude, position.longitude);
    } catch (_) {
      // Réessayé au prochain tour.
    }
  }

  Future<void> _startChunk() async {
    try {
      if (!await _recorder.hasPermission()) return;
      final dir = await getTemporaryDirectory();
      _chunkPath = '${dir.path}/sos_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _chunkStartedAt = DateTime.now();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 44100, numChannels: 1),
        path: _chunkPath!,
      );
      if (mounted) setState(() => _recording = true);
      _chunkTimer = Timer(SosScreen.chunkDuration, _rotateChunk);
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  /// Termine le morceau en cours, l'envoie, et en démarre un nouveau.
  Future<void> _rotateChunk() async {
    await _flushChunk();
    if (!_closing && mounted) await _startChunk();
  }

  Future<void> _flushChunk() async {
    _chunkTimer?.cancel();
    final startedAt = _chunkStartedAt;
    final path = await _recorder.stop().catchError((_) => null);
    _chunkStartedAt = null;
    final id = _alertId;
    if (path == null || id == null || startedAt == null) return;
    final duration = DateTime.now().difference(startedAt);
    _uploads.add(
      widget.api
          .uploadRecording(id, path, duration)
          .then((_) => File(path).delete())
          .then((_) {}, onError: (_) {}),
    );
  }

  Future<void> _finish() async {
    if (_closing) return;
    _closing = true;
    _ticker?.cancel();
    _locationTimer?.cancel();
    _stopwatch.stop();
    if (mounted) setState(() => _recording = false);
    await _flushChunk();
    await Future.wait(_uploads);
    final id = _alertId;
    if (id != null) await widget.api.end(id).catchError((_) {});
    if (mounted) setState(() => _state = _SosState.ended);
  }

  Future<void> _call(String number) => launchUrl(Uri(scheme: 'tel', path: number));

  @override
  void dispose() {
    _ticker?.cancel();
    _locationTimer?.cancel();
    _chunkTimer?.cancel();
    if (!_closing) _recorder.stop().catchError((_) => null);
    _recorder.dispose();
    super.dispose();
  }

  String get _elapsed {
    final d = _stopwatch.elapsed;
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ended = _state == _SosState.ended;
    return PopScope(
      canPop: ended || _state == _SosState.failed,
      child: Scaffold(
        backgroundColor: ended ? AppColors.background : const Color(0xFF7A0F14),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                const Spacer(),
                Icon(
                  ended ? Icons.verified_user_rounded : Icons.sos_rounded,
                  size: 88,
                  color: ended ? AppColors.success : Colors.white,
                ),
                const SizedBox(height: 20),
                Text(
                  switch (_state) {
                    _SosState.sending => 'Envoi de l’alerte…',
                    _SosState.active => 'Alerte envoyée à FOJËM',
                    _SosState.failed => 'Alerte non envoyée',
                    _SosState.ended => 'Vous êtes en sécurité',
                  },
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title1.copyWith(color: ended ? AppColors.textPrimary : Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  switch (_state) {
                    _SosState.sending => 'Récupération de votre position.',
                    _SosState.active =>
                      'L’équipe FOJËM suit votre position en direct. L’enregistrement audio est envoyé automatiquement.',
                    _SosState.failed => 'Vérifiez votre connexion et réessayez, ou appelez directement les secours.',
                    _SosState.ended => 'L’équipe FOJËM a reçu l’alerte et l’enregistrement. Elle pourra vous recontacter.',
                  },
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: ended ? AppColors.textSecondary : Colors.white70),
                ),
                if (_state == _SosState.active) ...[
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_recording ? Icons.fiber_manual_record_rounded : Icons.mic_off_rounded,
                          color: _recording ? Colors.redAccent.shade100 : Colors.white54, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _recording ? 'Enregistrement en cours · $_elapsed' : 'Micro non autorisé · $_elapsed',
                        style: AppTextStyles.bodySemibold.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (!ended) ...[
                  Row(
                    children: [
                      Expanded(child: _CallButton(label: 'Police', number: '17', onTap: () => _call('17'))),
                      const SizedBox(width: 12),
                      Expanded(child: _CallButton(label: 'Pompiers', number: '18', onTap: () => _call('18'))),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ended ? AppColors.primary : Colors.white,
                      foregroundColor: ended ? Colors.white : const Color(0xFF7A0F14),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: switch (_state) {
                      _SosState.sending => null,
                      _SosState.active => _finish,
                      _SosState.failed => _start,
                      _SosState.ended => () => Navigator.of(context).pop(),
                    },
                    child: Text(
                      switch (_state) {
                        _SosState.sending => 'Envoi…',
                        _SosState.active => 'Je suis en sécurité',
                        _SosState.failed => 'Réessayer',
                        _SosState.ended => 'Fermer',
                      },
                      style: AppTextStyles.bodyLargeSemibold.copyWith(color: ended ? Colors.white : const Color(0xFF7A0F14)),
                    ),
                  ),
                ),
                if (_state == _SosState.failed) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final String label;
  final String number;
  final VoidCallback onTap;

  const _CallButton({required this.label, required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.call_rounded, size: 18),
              const SizedBox(width: 6),
              Text(number, style: AppTextStyles.title2.copyWith(color: Colors.white)),
            ],
          ),
          Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}

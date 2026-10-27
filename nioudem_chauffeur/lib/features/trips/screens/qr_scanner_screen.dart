import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../services/booking_repository.dart';

/// Écran de scan de QR code — le chauffeur scanne le code QR du passager
/// pour confirmer sa présence (boarding) avant le départ.
///
/// Le QR code contient soit `FOJEM:{booking_id}:{confirmation_code}`,
/// soit le `departure_code` brut.
class QrScannerScreen extends StatefulWidget {
  final String tripId;

  const QrScannerScreen({super.key, required this.tripId});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;

  bool _isProcessing = false;
  _ScanResult? _lastResult;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      autoStart: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't interact with the controller if it's not ready.
    if (!_controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller.stop();
        break;
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || _lastResult != null) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _isProcessing = true);

    // Pause la caméra pendant le traitement
    _controller.stop();

    // Le backend sait interpréter "FOJEM:{booking_id}:{code}", l'id brut ou
    // le code de départ seul : on lui transmet la valeur scannée telle quelle.
    final String code = rawValue.trim();

    try {
      final result = await BookingRepository().boardPassenger(
        tripId: widget.tripId,
        code: code,
      );

      final isAlreadyBoarded = result['already_boarded'] == true;
      final passengerName = result['booking']?['passenger']?['full_name'] ??
          result['booking']?['passenger']?['name'] ??
          'Passager';

      final message = isAlreadyBoarded
          ? (result['message'] as String? ?? '$passengerName a déjà été scanné et est déjà à bord.')
          : '$passengerName est maintenant à bord !';

      if (!mounted) return;
      setState(() {
        _lastResult = _ScanResult(
          success: !isAlreadyBoarded,
          alreadyBoarded: isAlreadyBoarded,
          message: message,
          passengerName: passengerName,
        );
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      String message = 'Erreur de connexion. Réessayez.';
      bool isAlready = false;
      if (e is ApiException && !e.isNetworkError && e.message.isNotEmpty) {
        message = e.message;
        if (message.toLowerCase().contains('déjà') || message.toLowerCase().contains('deja')) {
          isAlready = true;
        }
      }
      setState(() {
        _lastResult = _ScanResult(
          success: false,
          alreadyBoarded: isAlready,
          message: message,
          passengerName: null,
        );
        _isProcessing = false;
      });
    }
  }

  void _resetScan() {
    setState(() {
      _lastResult = null;
      _cameraError = null;
    });
    // Relance la caméra
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner un passager'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close),
        ),
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return _CameraErrorWidget(
                error: error,
                onRetry: _resetScan,
              );
            },
          ),

          // Scanner overlay
          if (_cameraError == null)
            _ScannerOverlay(isProcessing: _isProcessing),

          // Result sheet
          if (_lastResult != null)
            _ResultSheet(
              result: _lastResult!,
              onScanAgain: _resetScan,
              onDone: () => context.pop(true),
            ),

          // Instructions at bottom
          if (_lastResult == null && !_isProcessing && _cameraError == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 32,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Scannez le QR code du passager',
                      style: AppTextStyles.title2.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Le passager peut afficher son code depuis\nson écran de suivi de trajet',
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white60,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Vérification en cours…',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget d'erreur caméra
class _CameraErrorWidget extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;

  const _CameraErrorWidget({required this.error, required this.onRetry});

  String _getErrorMessage() {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Permission caméra refusée.\nActivez la permission dans les paramètres de l\'app.';
      case MobileScannerErrorCode.unsupported:
        return 'Caméra non supportée sur cet appareil.';
      default:
        return 'Erreur de la caméra.\nEssayez de redémarrer l\'application.';
    }
  }

  IconData _getErrorIcon() {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return Icons.no_photography_rounded;
      case MobileScannerErrorCode.unsupported:
        return Icons.videocam_off_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getErrorIcon(),
                size: 64,
                color: AppColors.danger,
              ),
              const SizedBox(height: 20),
              Text(
                _getErrorMessage(),
                style: AppTextStyles.body.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FojemButton.primary(
                label: 'Réessayer',
                prefixIcon: Icons.refresh_rounded,
                onPressed: onRetry,
                size: FojemButtonSize.medium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  final bool isProcessing;

  const _ScannerOverlay({required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _OverlayPainter(isProcessing: isProcessing),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final bool isProcessing;

  _OverlayPainter({required this.isProcessing});

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2 - 40;
    final right = left + scanAreaSize;
    final bottom = top + scanAreaSize;

    // Dim background
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.5);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(left, top, right, bottom),
            const Radius.circular(16),
          )),
      ),
      bgPaint,
    );

    // Scanner frame corners
    final cornerPaint = Paint()
      ..color = isProcessing ? Colors.amber : AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 16.0;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top + radius)
        ..arcToPoint(Offset(left + radius, top), radius: const Radius.circular(radius))
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, top)
        ..lineTo(right - radius, top)
        ..arcToPoint(Offset(right, top + radius), radius: const Radius.circular(radius))
        ..lineTo(right, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - cornerLength)
        ..lineTo(left, bottom - radius)
        ..arcToPoint(Offset(left + radius, bottom), radius: const Radius.circular(radius))
        ..lineTo(left + cornerLength, bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, bottom)
        ..lineTo(right - radius, bottom)
        ..arcToPoint(Offset(right, bottom - radius), radius: const Radius.circular(radius))
        ..lineTo(right, bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.isProcessing != isProcessing;
}

class _ScanResult {
  final bool success;
  final bool alreadyBoarded;
  final String message;
  final String? passengerName;

  const _ScanResult({
    required this.success,
    this.alreadyBoarded = false,
    required this.message,
    this.passengerName,
  });
}

class _ResultSheet extends StatelessWidget {
  final _ScanResult result;
  final VoidCallback onScanAgain;
  final VoidCallback onDone;

  const _ResultSheet({
    required this.result,
    required this.onScanAgain,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final isAlready = result.alreadyBoarded;
    final isSuccess = result.success && !isAlready;

    final Color badgeColor = isAlready
        ? Colors.amber.shade800
        : isSuccess
            ? AppColors.primary
            : AppColors.danger;

    final IconData icon = isAlready
        ? Icons.verified_user_rounded
        : isSuccess
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded;

    final String title = isAlready
        ? 'Passager déjà embarqué'
        : isSuccess
            ? 'Passager embarqué !'
            : 'Échec du scan';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeColor.withValues(alpha: 0.12),
              ),
              child: Icon(
                icon,
                size: 36,
                color: badgeColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.title1.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              result.message,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FojemButton.secondary(
                    label: 'Scanner un autre',
                    prefixIcon: Icons.qr_code_scanner_rounded,
                    onPressed: onScanAgain,
                    size: FojemButtonSize.medium,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FojemButton.primary(
                    label: 'Terminé',
                    onPressed: onDone,
                    size: FojemButtonSize.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

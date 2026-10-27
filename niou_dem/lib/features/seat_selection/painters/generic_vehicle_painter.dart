import 'package:flutter/material.dart';

/// Silhouette top-down générique pour berline / 7 places / SUV / minibus —
/// même langage visuel que [SprinterPainter] (carrosserie claire, sièges
/// beiges) mais géométrie simple, sans art bespoke par véhicule : "aussi peu
/// de design que possible" plutôt que 4 illustrations sur-mesure.
class GenericVehiclePainter extends CustomPainter {
  const GenericVehiclePainter();

  static const double _bL = 0.06;
  static const double _bR = 0.94;
  static const double _bT = 0.02;
  static const double _bB = 0.98;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBody(canvas, size);
    _paintWindshield(canvas, size);
    _paintWheelArches(canvas, size);
    _paintFloor(canvas, size);
  }

  void _paintBody(Canvas canvas, Size s) {
    final rect = Rect.fromLTRB(_x(s, _bL), _y(s, _bT), _x(s, _bR), _y(s, _bB));
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(28),
      topRight: const Radius.circular(28),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFC0BEBA), Color(0xFFDDDBD7), Color(0xFFC4C2BE)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF878582)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _paintWindshield(Canvas canvas, Size s) {
    final rect = Rect.fromLTRB(_x(s, _bL + 0.06), _y(s, _bT + 0.02), _x(s, _bR - 0.06), _y(s, _bT + 0.12));
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9CB8C8), Color(0xFFA8C0CE)],
        ).createShader(rect),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF607888)..style = PaintingStyle.stroke..strokeWidth = 1.0);
  }

  void _paintWheelArches(Canvas canvas, Size s) {
    final wW = s.width * 0.05;
    final wH = s.height * 0.07;
    final positions = [
      (_bL, 0.16), (_bR, 0.16),
      (_bL, 0.84), (_bR, 0.84),
    ];
    for (final (rx, ry) in positions) {
      final isLeft = rx == _bL;
      final rect = Rect.fromCenter(
        center: Offset(_x(s, rx) + (isLeft ? -wW * 0.15 : wW * 0.15), _y(s, ry)),
        width: wW,
        height: wH,
      );
      canvas.drawOval(rect, Paint()..color = const Color(0xFF2E2E2E));
      canvas.drawOval(rect.deflate(rect.width * 0.22), Paint()..color = const Color(0xFF585654));
    }
  }

  void _paintFloor(Canvas canvas, Size s) {
    final rect = Rect.fromLTRB(_x(s, _bL + 0.08), _y(s, _bT + 0.15), _x(s, _bR - 0.08), _y(s, _bB - 0.06));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xFFC8C2B8),
    );
  }

  double _x(Size s, double fraction) => fraction * s.width;
  double _y(Size s, double fraction) => fraction * s.height;

  @override
  bool shouldRepaint(covariant GenericVehiclePainter oldDelegate) => false;
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Peint une vue top-down réaliste d'un Mercedes Sprinter 9 places.
///
/// Toutes les coordonnées sont en fraction [0,1] de la taille du canvas.
/// Les silhouettes de sièges sont dessinées en état neutre (beige).
/// Les indicateurs interactifs (numéros, cadenas, lueur) sont superposés
/// par `SeatLayoutWidget` via des widgets [Positioned].
class SprinterPainter extends CustomPainter {
  const SprinterPainter();

  // ── Limites de la carrosserie ──────────────────────────────────────────────
  static const double _bL = 0.088; // body left
  static const double _bR = 0.912; // body right
  static const double _bT = 0.018; // body top
  static const double _bB = 0.972; // body bottom
  static const double _fL = 0.112; // front taper left
  static const double _fR = 0.888; // front taper right
  static const double _iL = 0.128; // interior left
  static const double _iR = 0.872; // interior right
  static const double _iT = 0.090; // interior top (sous pare-brise)
  static const double _iB = 0.945; // interior bottom
  // ── Séparation cabine / carrosserie ───────────────────────────────────────
  static const double _divT = 0.488; // divider top
  static const double _divB = 0.528; // divider bottom

  @override
  void paint(Canvas canvas, Size size) {
    _paintBodyExterior(canvas, size);
    _paintWindshield(canvas, size);
    _paintWheelArches(canvas, size);
    _paintInteriorFloor(canvas, size);
    _paintSeatSilhouettes(canvas, size);
    _paintCabinDivider(canvas, size);
    _paintBodyDetails(canvas, size);
  }

  // ── 1. Carrosserie extérieure ─────────────────────────────────────────────
  void _paintBodyExterior(Canvas canvas, Size s) {
    final path = Path();
    path.moveTo(_x(s, _fL + 0.030), _y(s, _bT));
    path.lineTo(_x(s, _fR - 0.030), _y(s, _bT));
    path.quadraticBezierTo(_x(s, _fR), _y(s, _bT), _x(s, _fR), _y(s, _bT + 0.015));
    path.lineTo(_x(s, _bR), _y(s, _bT + 0.065));
    path.lineTo(_x(s, _bR), _y(s, _bB - 0.025));
    path.quadraticBezierTo(_x(s, _bR), _y(s, _bB), _x(s, _bR - 0.040), _y(s, _bB));
    path.lineTo(_x(s, _bL + 0.040), _y(s, _bB));
    path.quadraticBezierTo(_x(s, _bL), _y(s, _bB), _x(s, _bL), _y(s, _bB - 0.025));
    path.lineTo(_x(s, _bL), _y(s, _bT + 0.065));
    path.lineTo(_x(s, _fL), _y(s, _bT + 0.015));
    path.quadraticBezierTo(_x(s, _fL), _y(s, _bT), _x(s, _fL + 0.030), _y(s, _bT));
    path.close();

    // Dégradé latéral pour simuler la brillance de la carrosserie métallique
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFB0AEAB),
            Color(0xFFC8C6C2),
            Color(0xFFD8D6D2),
            Color(0xFFDDDBD7),
            Color(0xFFD2D0CC),
            Color(0xFFC0BEBA),
            Color(0xFFB2B0AC),
          ],
          stops: [0.0, 0.10, 0.28, 0.50, 0.72, 0.90, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)),
    );

    // Contour carrosserie
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF878582)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  // ── 2. Pare-brise ─────────────────────────────────────────────────────────
  void _paintWindshield(Canvas canvas, Size s) {
    final wsL = _x(s, _fL + 0.040);
    final wsR = _x(s, _fR - 0.040);
    final wsT = _y(s, _bT + 0.020);
    final wsB = _y(s, _iT - 0.002);

    final path = Path()
      ..moveTo(wsL + 12, wsT)
      ..lineTo(wsR - 12, wsT)
      ..quadraticBezierTo(wsR, wsT, wsR, wsT + 8)
      ..lineTo(wsR + 4, wsB)
      ..lineTo(wsL - 4, wsB)
      ..quadraticBezierTo(wsL, wsT, wsL + 12, wsT)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9CB8C8), Color(0xFFA8C0CE)],
        ).createShader(Rect.fromLTWH(0, wsT, s.width, wsB - wsT)),
    );

    // Reflet de vitre (ligne blanche oblique)
    canvas.drawLine(
      Offset(_x(s, 0.195), wsT + 6),
      Offset(_x(s, 0.245), wsB - 4),
      Paint()
        ..color = Colors.white.withOpacity(0.30)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF607888)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  // ── 3. Arches de roues ────────────────────────────────────────────────────
  void _paintWheelArches(Canvas canvas, Size s) {
    final wW = s.width * 0.052;
    final wH = s.height * 0.090;

    // Positions (cx, cy) relatives
    final positions = [
      (_bL, 0.200), (_bR, 0.200), // avant G / D
      (_bL, 0.730), (_bR, 0.730), // arrière G / D
    ];

    for (final (rx, ry) in positions) {
      final cx = _x(s, rx);
      final cy = _y(s, ry);
      final isLeft = rx == _bL;

      final rect = Rect.fromCenter(
        center: Offset(isLeft ? cx - wW * 0.1 : cx + wW * 0.1, cy),
        width: wW,
        height: wH,
      );

      // Pneu
      canvas.drawOval(rect, Paint()..color = const Color(0xFF2E2E2E));
      // Jante
      canvas.drawOval(
        rect.deflate(rect.width * 0.22),
        Paint()..color = const Color(0xFF585654),
      );
      // Moyeu central
      canvas.drawCircle(
        rect.center,
        rect.width * 0.10,
        Paint()..color = const Color(0xFF888684),
      );
      // Reflet jante
      canvas.drawArc(
        rect.deflate(rect.width * 0.24),
        isLeft ? -math.pi * 0.75 : -math.pi * 0.05,
        math.pi * 0.45,
        false,
        Paint()
          ..color = Colors.white.withOpacity(0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  // ── 4. Plancher intérieur ─────────────────────────────────────────────────
  void _paintInteriorFloor(Canvas canvas, Size s) {
    final floorPaint = Paint()..color = const Color(0xFFC8C2B8);
    const radius = Radius.circular(3);

    // Section cabine
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(_x(s, _iL), _y(s, _iT), _x(s, _iR), _y(s, _divT)),
        radius,
      ),
      floorPaint,
    );
    // Section carrosserie
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(_x(s, _iL), _y(s, _divB), _x(s, _iR), _y(s, _iB)),
        radius,
      ),
      floorPaint,
    );
  }

  // ── 5. Silhouettes de sièges ──────────────────────────────────────────────
  void _paintSeatSilhouettes(Canvas canvas, Size s) {
    // (centerX, centerY, halfW, halfH) en fractions
    const seats = [
      (0.245, 0.210, 0.078, 0.068), // Chauffeur
      (0.722, 0.210, 0.078, 0.068), // Place 2
      (0.245, 0.385, 0.078, 0.065), // Place 1
      (0.614, 0.385, 0.068, 0.065), // Place 3
      (0.790, 0.385, 0.068, 0.065), // Place 4
      (0.245, 0.650, 0.078, 0.065), // Place 6
      (0.614, 0.630, 0.068, 0.065), // Place 5
      (0.790, 0.630, 0.068, 0.065), // Place 7
      (0.340, 0.842, 0.095, 0.060), // Place 8
      (0.658, 0.842, 0.095, 0.060), // Place 9
    ];

    for (final (cx, cy, hw, hh) in seats) {
      final rect = Rect.fromCenter(
        center: Offset(_x(s, cx), _y(s, cy)),
        width: hw * 2 * s.width,
        height: hh * 2 * s.height,
      );
      final rRect = RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.14));

      // Base siège
      canvas.drawRRect(rRect, Paint()..color = const Color(0xFFDED8CE));

      // Coussin (zone centrale légèrement plus claire)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(rect.width * 0.08),
          Radius.circular(rect.width * 0.10),
        ),
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.3),
            radius: 0.9,
            colors: [Color(0xFFEDE6DB), Color(0xFFD5CEC4)],
          ).createShader(rect),
      );

      // Ligne de couture centrale (horizontale)
      final stitchY = rect.center.dy - rect.height * 0.04;
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.18, stitchY),
        Offset(rect.right - rect.width * 0.18, stitchY),
        Paint()
          ..color = const Color(0xFFBEB8AE)
          ..strokeWidth = 0.8,
      );

      // Contour
      canvas.drawRRect(
        rRect,
        Paint()
          ..color = const Color(0xFFB0A89E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );
    }
  }

  // ── 6. Séparateur cabine ──────────────────────────────────────────────────
  void _paintCabinDivider(Canvas canvas, Size s) {
    final divRect = Rect.fromLTRB(
      _x(s, _iL), _y(s, _divT), _x(s, _iR), _y(s, _divB),
    );

    // Paroi métal
    canvas.drawRect(divRect, Paint()..color = const Color(0xFFB8B4AE));

    // Rivets (petits cercles aux extrémités)
    final rivetPaint = Paint()..color = const Color(0xFF8A8882);
    final rivetY = _y(s, (_divT + _divB) / 2);
    for (final rx in [_iL + 0.015, _iR - 0.015]) {
      canvas.drawCircle(Offset(_x(s, rx), rivetY), 2.5, rivetPaint);
    }

    // Lignes de bordure
    final borderPaint = Paint()
      ..color = const Color(0xFF9A9890)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(_x(s, _iL), _y(s, _divT)),
      Offset(_x(s, _iR), _y(s, _divT)),
      borderPaint,
    );
    canvas.drawLine(
      Offset(_x(s, _iL), _y(s, _divB)),
      Offset(_x(s, _iR), _y(s, _divB)),
      borderPaint,
    );
  }

  // ── 7. Détails de carrosserie ─────────────────────────────────────────────
  void _paintBodyDetails(Canvas canvas, Size s) {
    final linePaint = Paint()
      ..color = const Color(0xFF909090)
      ..strokeWidth = 0.7;

    // Joints de portières (côté gauche)
    canvas.drawLine(Offset(_x(s, _bL + 0.001), _y(s, 0.530)),
        Offset(_x(s, _bL + 0.001), _y(s, 0.870)), linePaint);
    // Joints de portières (côté droit)
    canvas.drawLine(Offset(_x(s, _bR - 0.001), _y(s, 0.530)),
        Offset(_x(s, _bR - 0.001), _y(s, 0.870)), linePaint);

    // Pare-choc arrière
    canvas.drawLine(
      Offset(_x(s, _bL + 0.048), _y(s, _bB - 0.008)),
      Offset(_x(s, _bR - 0.048), _y(s, _bB - 0.008)),
      Paint()
        ..color = const Color(0xFF787674)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );

    // Antenne de toit (petit point central en haut)
    canvas.drawCircle(
      Offset(s.width * 0.50, _y(s, _bT + 0.012)),
      3.0,
      Paint()..color = const Color(0xFF707070),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  double _x(Size s, double fraction) => fraction * s.width;
  double _y(Size s, double fraction) => fraction * s.height;

  @override
  bool shouldRepaint(covariant SprinterPainter oldDelegate) => false;
}

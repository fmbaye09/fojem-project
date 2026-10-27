import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/seat.dart';

/// Indicateur interactif superposé sur le siège.
///
/// - Driver   → badge vert avec icône volant + label "Chauffeur"
/// - Available → cercle vert numéroté
/// - Selected  → cercle vert numéroté avec aura lumineuse verte animée
/// - Occupied  → cercle gris avec cadenas
class SeatIndicator extends StatelessWidget {
  final SeatState seat;
  final double radius; // rayon de base du cercle interactif (px)
  final VoidCallback? onTap;

  const SeatIndicator({
    super.key,
    required this.seat,
    required this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return switch (seat.status) {
      SeatStatus.driver   => _DriverBadge(radius: radius),
      SeatStatus.available => _AvailableDot(seat: seat, radius: radius, onTap: onTap),
      SeatStatus.selected  => _SelectedDot(seat: seat, radius: radius, onTap: onTap),
      SeatStatus.occupied  => _OccupiedDot(radius: radius),
    };
  }
}

// ── Chauffeur ──────────────────────────────────────────────────────────────
class _DriverBadge extends StatelessWidget {
  final double radius;
  const _DriverBadge({required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: radius * 0.5, vertical: radius * 0.28),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(radius * 0.45),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: radius * 1.1,
            height: radius * 1.1,
            child: const CustomPaint(painter: _SteeringWheelPainter(color: Colors.white)),
          ),
          SizedBox(height: radius * 0.12),
          Text(
            'Chauffeur',
            style: GoogleFonts.inter(
              fontSize: radius * 0.42,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Siège disponible ──────────────────────────────────────────────────────
class _AvailableDot extends StatelessWidget {
  final SeatState seat;
  final double radius;
  final VoidCallback? onTap;
  const _AvailableDot({required this.seat, required this.radius, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.2),
        ),
        child: Center(
          child: Text(
            seat.config.label,
            style: GoogleFonts.inter(
              fontSize: radius * 0.82,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Siège sélectionné ─────────────────────────────────────────────────────
class _SelectedDot extends StatelessWidget {
  final SeatState seat;
  final double radius;
  final VoidCallback? onTap;
  const _SelectedDot({required this.seat, required this.radius, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.elasticOut,
        width: radius * 2.3,
        height: radius * 2.3,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withOpacity(0.75),
              blurRadius: 10,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: AppColors.accent.withOpacity(0.45),
              blurRadius: 20,
              spreadRadius: 5,
            ),
            BoxShadow(
              color: AppColors.accent.withOpacity(0.22),
              blurRadius: 36,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: Text(
            seat.config.label,
            style: GoogleFonts.inter(
              fontSize: radius * 0.90,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Siège occupé ─────────────────────────────────────────────────────────
class _OccupiedDot extends StatelessWidget {
  final double radius;
  const _OccupiedDot({required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: const Color(0xFF7A7A7A),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.8),
      ),
      child: Center(
        child: Icon(
          Icons.lock_rounded,
          color: Colors.white.withOpacity(0.85),
          size: radius * 0.92,
        ),
      ),
    );
  }
}

// ── Volant (Custom Painter) ───────────────────────────────────────────────
class _SteeringWheelPainter extends CustomPainter {
  final Color color;
  const _SteeringWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 0.5;
    final innerR = outerR * 0.32;
    final spokeR = outerR * 0.82;

    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;

    // Jante
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(center, outerR, paint);

    // Rayons (3 × 120°)
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = size.width * 0.10;
    for (int i = 0; i < 3; i++) {
      final angle = (i * 120 - 90) * (math.pi / 180);
      canvas.drawLine(
        center,
        Offset(center.dx + math.cos(angle) * spokeR,
               center.dy + math.sin(angle) * spokeR),
        paint,
      );
    }

    // Moyeu
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(center, innerR, paint);
  }

  @override
  bool shouldRepaint(covariant _SteeringWheelPainter old) => old.color != color;
}

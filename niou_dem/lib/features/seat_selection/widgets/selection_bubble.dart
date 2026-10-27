import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bulle de tooltip "Place #X - Sélectionnée" avec triangle pointant vers le bas.
/// Apparaît au-dessus du siège sélectionné avec un fondu animé.
class SelectionBubble extends StatelessWidget {
  final String seatLabel;

  const SelectionBubble({super.key, required this.seatLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            'Place #$seatLabel - Sélectionnée',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A18),
              letterSpacing: -0.1,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(12, 6),
          painter: _DownTrianglePainter(),
        ),
      ],
    );
  }
}

class _DownTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

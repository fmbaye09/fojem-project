import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Photo ronde d'un utilisateur, ou ses initiales sur une teinte douce
/// (déterminée par le nom, donc stable d'un écran à l'autre) tant qu'il n'a
/// pas de photo.
class DriverAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool isOnline;
  final double size;

  const DriverAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.isOnline = false,
    this.size = 48,
  });

  // (fond, texte) — tons clairs tirés de la charte, jamais saturés.
  static const _palettes = [
    (Color(0xFFFDE6D2), Color(0xFF9A4A12)),
    (Color(0xFFDDE6EF), Color(0xFF0B2A47)),
    (Color(0xFFE2EEDF), Color(0xFF2D6A35)),
    (Color(0xFFEFE6DA), Color(0xFF6B4E2E)),
  ];

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  (Color, Color) get _palette {
    final code = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _palettes[code % _palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final circle = _buildCircle();
    if (!isOnline) return circle;

    final dot = size * 0.26;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          circle,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircle() {
    final (bg, _) = _palette;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildInitials(),
            )
          : _buildInitials(),
    );
  }

  Widget _buildInitials() {
    final (_, fg) = _palette;
    return Center(
      child: Text(
        _initials,
        style: AppTextStyles.bodySemibold.copyWith(
          color: fg,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

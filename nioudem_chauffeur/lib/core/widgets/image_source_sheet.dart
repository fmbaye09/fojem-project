import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Photo choisie par l'utilisateur, déjà lue en mémoire (prête pour un
/// upload multipart et pour un aperçu via `Image.memory`).
class PickedImage {
  final Uint8List bytes;
  final String filename;

  const PickedImage({required this.bytes, required this.filename});
}

/// Feuille du bas "Prendre une photo / Choisir dans la galerie", puis
/// sélection via `image_picker`. Retourne null si l'utilisateur annule.
///
/// L'image est redimensionnée/compressée à la source ([maxDimension],
/// [imageQuality]) pour rester très en dessous des limites backend
/// (4 Mo photo de profil, 8 Mo document) même avec un appareil récent.
Future<PickedImage?> pickImageWithSourceSheet(
  BuildContext context, {
  required String title,
  double maxDimension = 2000,
  int imageQuality = 85,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: AppTextStyles.title2),
            ),
            _SourceTile(
              icon: Icons.photo_camera_outlined,
              label: 'Prendre une photo',
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            _SourceTile(
              icon: Icons.photo_library_outlined,
              label: 'Choisir dans la galerie',
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;

  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: imageQuality,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedImage(bytes: bytes, filename: _filenameFor(file));
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(source == ImageSource.camera
              ? 'Impossible d’accéder à l’appareil photo. Vérifiez les autorisations de l’application.'
              : 'Impossible d’accéder à la galerie. Vérifiez les autorisations de l’application.'),
        ),
      );
    }
    return null;
  }
}

/// Le backend valide l'extension (jpg/jpeg/png) : on garantit un nom de
/// fichier qui en porte une, même si le sélecteur renvoie un nom brut.
String _filenameFor(XFile file) {
  final name = file.name.trim();
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
    return name;
  }
  return 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
            ],
          ),
        ),
      ),
    );
  }
}

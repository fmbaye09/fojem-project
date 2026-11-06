import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Pièces jointes du chat, communes aux deux apps : choix de la source,
/// sélection du fichier et affichage dans les bulles. Le fichier part au
/// backend (`POST /api/chat/attachments`) ; le message Firestore n'en garde
/// que l'URL, le nom et la taille.

/// Documents acceptés par le backend.
const kChatDocumentExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];

/// Taille maximale acceptée par le backend (10 Mo).
const kChatAttachmentMaxBytes = 10 * 1024 * 1024;

enum AttachmentSource { camera, gallery, document }

/// Fichier choisi, prêt à être envoyé.
class PickedAttachment {
  final String path;
  final String name;
  final int size;

  const PickedAttachment({required this.path, required this.name, required this.size});
}

/// Feuille « Joindre » : appareil photo, galerie ou document.
Future<AttachmentSource?> showAttachmentSheet(BuildContext context) {
  return showModalBottomSheet<AttachmentSource>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      Widget option(AttachmentSource source, IconData icon, String label) => ListTile(
            leading: Icon(icon, color: AppColors.primary),
            title: Text(label, style: AppTextStyles.bodyLarge),
            onTap: () => Navigator.of(sheetContext).pop(source),
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(AttachmentSource.camera, Icons.photo_camera_outlined, 'Prendre une photo'),
            option(AttachmentSource.gallery, Icons.photo_library_outlined, 'Choisir une photo'),
            option(AttachmentSource.document, Icons.description_outlined, 'Document (PDF, Word…)'),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Ouvre l'appareil photo, la galerie ou le sélecteur de documents ; `null`
/// si l'utilisateur annule. Les photos sont réduites (1920 px, JPEG 80 %)
/// pour partir vite sur un réseau mobile. Lève une `PlatformException` si
/// l'accès à l'appareil photo est refusé.
Future<PickedAttachment?> pickAttachment(AttachmentSource source) async {
  if (source == AttachmentSource.document) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kChatDocumentExtensions,
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return null;
    return PickedAttachment(path: path, name: file.name, size: file.size);
  }

  final photo = await ImagePicker().pickImage(
    source: source == AttachmentSource.camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1920,
    maxHeight: 1920,
    imageQuality: 80,
  );
  if (photo == null) return null;
  return PickedAttachment(path: photo.path, name: photo.name, size: await photo.length());
}

/// « 850 Ko », « 2,4 Mo ».
String formatFileSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < mb) return '${(bytes / 1024).ceil()} Ko';
  return '${(bytes / mb).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// Photo dans une bulle : vignette arrondie, plein écran au toucher.
class ChatImageAttachment extends StatelessWidget {
  final String url;

  const ChatImageAttachment({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.resolveMediaUrl(url) ?? url;
    return Semantics(
      button: true,
      label: 'Photo, toucher pour agrandir',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _PhotoViewer(url: resolved),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: CachedNetworkImage(
              imageUrl: resolved,
              fit: BoxFit.cover,
              // Vignette : inutile de décoder la photo en 1920 px.
              memCacheWidth: 720,
              placeholder: (_, __) => const SizedBox(
                width: 220,
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              ),
              errorWidget: (_, __, ___) => const SizedBox(
                width: 220,
                height: 140,
                child: Center(
                  child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final String url;

  const _PhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// Document dans une bulle : icône, nom et taille ; s'ouvre au toucher dans
/// l'app adaptée (lecteur PDF, Word…).
class ChatFileAttachment extends StatelessWidget {
  final String url;
  final String name;
  final int? size;
  final Color color;

  const ChatFileAttachment({
    super.key,
    required this.url,
    required this.name,
    required this.size,
    required this.color,
  });

  static IconData _iconFor(String extension) {
    switch (extension) {
      case 'PDF':
        return Icons.picture_as_pdf_outlined;
      case 'XLS':
      case 'XLSX':
        return Icons.table_chart_outlined;
      case 'PPT':
      case 'PPTX':
        return Icons.slideshow_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(ApiConfig.resolveMediaUrl(url) ?? url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Aucune app pour ce type de fichier : message ci-dessous.
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final extension = name.contains('.') ? name.split('.').last.toUpperCase() : 'FICHIER';
    final details = [extension, if (size != null && size! > 0) formatFileSize(size!)].join(' · ');
    return Semantics(
      button: true,
      label: 'Document $name, toucher pour ouvrir',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconFor(extension), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySemibold.copyWith(color: color, height: 1.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: AppTextStyles.caption.copyWith(color: color.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

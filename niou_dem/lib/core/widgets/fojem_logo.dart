import 'package:flutter/material.dart';

/// Logo FOJËM (asset fourni par le design : voiture orange + wordmark bleu
/// marine). `FojemLogo` affiche le logo complet, `FojemLogo.icon` n'affiche
/// que la voiture (recadrage sans le texte), pour les en-têtes compacts.
class FojemLogo extends StatelessWidget {
  final double width;
  final bool _iconOnly;

  const FojemLogo({super.key, this.width = 160}) : _iconOnly = false;

  const FojemLogo.icon({super.key, double size = 40})
      : width = size,
        _iconOnly = true;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _iconOnly
          ? 'assets/images/fojem_logo_icon.png'
          : 'assets/images/fojem_logo.png',
      width: width,
      fit: BoxFit.contain,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'glow.dart';

/// Onglets principaux côté voyageur, dans l'ordre de la barre.
enum ClientTab { home, bookings, messages, profile }

extension on ClientTab {
  String get route {
    switch (this) {
      case ClientTab.home:
        return '/home';
      case ClientTab.bookings:
        return '/my-trips';
      case ClientTab.messages:
        return '/chat';
      case ClientTab.profile:
        return '/profile/settings';
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}

/// Barre de navigation voyageur — fidèle aux maquettes : icônes pleines,
/// onglet actif en orange (icône + libellé), les autres en gris, pas de
/// pastille. Changer d'onglet remplace l'écran (`go`) au lieu d'empiler.
class TravelerBottomNavBar extends StatelessWidget {
  final ClientTab current;

  const TravelerBottomNavBar({super.key, required this.current});

  static const _items = {
    ClientTab.home: _NavItem(Icons.home_rounded, 'Accueil'),
    ClientTab.bookings: _NavItem(Icons.confirmation_number_rounded, 'Réservations'),
    ClientTab.messages: _NavItem(Icons.forum_rounded, 'Messages'),
    ClientTab.profile: _NavItem(Icons.person_rounded, 'Profil'),
  };

  /// Barre fixe pleine largeur, collée en bas de l'écran ; l'onglet actif
  /// passe « en creux ».
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Color(0x1407232F), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          // Hauteur fixe : le Scaffold laisse toute la hauteur de l'écran à
          // la barre du bas, que les onglets centrés occuperaient sinon.
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                for (final entry in _items.entries)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _NavBarItem(
                        item: entry.value,
                        isActive: entry.key == current,
                        onTap: () {
                          if (entry.key != current) context.go(entry.key.route);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.navActive : AppColors.navInactive;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.icon, size: 22, color: color),
        const SizedBox(height: 3),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: isActive,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isActive
              ? NeuInset(
                  key: const ValueKey('on'),
                  radius: 18,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: content),
                )
              : Padding(
                  key: const ValueKey('off'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: content),
                ),
        ),
      ),
    );
  }
}

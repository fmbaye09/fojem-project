import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
  final IconData activeIcon;
  final String label;

  const _NavItem(this.icon, this.activeIcon, this.label);
}

/// Barre de navigation voyageur : quatre onglets, icône pleine et libellé
/// gras pour l'onglet actif (posé sur une pastille), icône au trait pour les
/// autres. Changer d'onglet remplace l'écran (`go`) au lieu d'empiler.
class TravelerBottomNavBar extends StatelessWidget {
  final ClientTab current;

  const TravelerBottomNavBar({super.key, required this.current});

  static const _items = {
    ClientTab.home: _NavItem(Icons.search_rounded, Icons.search_rounded, 'Rechercher'),
    ClientTab.bookings: _NavItem(Icons.confirmation_number_outlined, Icons.confirmation_number_rounded, 'Réservations'),
    ClientTab.messages: _NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages'),
    ClientTab.profile: _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  };

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final entry in _items.entries)
                Expanded(
                  child: _NavBarItem(
                    item: entry.value,
                    isActive: entry.key == current,
                    onTap: () {
                      if (entry.key != current) context.go(entry.key.route);
                    },
                  ),
                ),
            ],
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
    return Semantics(
      button: true,
      selected: isActive,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: isActive ? AppColors.brandSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(isActive ? item.activeIcon : item.icon, size: 22, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

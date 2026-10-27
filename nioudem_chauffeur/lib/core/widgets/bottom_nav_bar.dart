import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Onglets principaux côté chauffeur, dans l'ordre de la barre.
enum DriverTab { home, trips, messages, profile }

extension on DriverTab {
  String get route {
    switch (this) {
      case DriverTab.home:
        return '/home';
      case DriverTab.trips:
        return '/trips';
      case DriverTab.messages:
        return '/chat';
      case DriverTab.profile:
        return '/profile/settings';
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}

/// Barre de navigation chauffeur — fidèle aux maquettes : icônes pleines,
/// onglet actif en orange (icône + libellé), les autres en gris, pas de
/// pastille. Changer d'onglet remplace l'écran (`go`) au lieu d'empiler.
class DriverBottomNavBar extends StatelessWidget {
  final DriverTab current;

  const DriverBottomNavBar({super.key, required this.current});

  static const _items = {
    DriverTab.home: _NavItem(Icons.home_rounded, 'Accueil'),
    DriverTab.trips: _NavItem(Icons.directions_car_filled_rounded, 'Mes trajets'),
    DriverTab.messages: _NavItem(Icons.forum_rounded, 'Messages'),
    DriverTab.profile: _NavItem(Icons.person_rounded, 'Profil'),
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
          height: 60,
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
    final color = isActive ? AppColors.primary : AppColors.navInactive;

    return Semantics(
      button: true,
      selected: isActive,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

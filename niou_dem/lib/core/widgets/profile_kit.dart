import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'glow.dart';

/// Statistique de la carte de profil (« ★ 4,9 · Note »).
class ProfileStat {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const ProfileStat({required this.icon, required this.color, required this.value, required this.label});
}

/// Ligne d'information de la carte de profil (« STATUT · Identité vérifiée »).
class ProfileInfo {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const ProfileInfo({required this.icon, required this.color, required this.label, required this.value});
}

/// Carte de profil qui chevauche l'en-tête : avatar avec pastille de
/// modification, nom, sous-titre, tuiles de statistiques, infos de statut.
class ProfileHeroCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? photoUrl;
  final VoidCallback? onEditPhoto;
  final bool isUploadingPhoto;
  final List<ProfileStat> stats;
  final List<ProfileInfo> infos;

  const ProfileHeroCard({
    super.key,
    required this.name,
    this.subtitle,
    this.photoUrl,
    this.onEditPhoto,
    this.isUploadingPhoto = false,
    this.stats = const [],
    this.infos = const [],
  });

  @override
  Widget build(BuildContext context) {
    return NeuBox(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: isUploadingPhoto ? null : onEditPhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                    border: Border.all(color: AppColors.surface, width: 4),
                    boxShadow: const [BoxShadow(color: Color(0x3307232F), blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null && photoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _Initials(name: name),
                        )
                      : _Initials(name: name),
                ),
                if (isUploadingPhoto)
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      ),
                    ),
                  ),
                if (onEditPhoto != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 3),
                      ),
                      child: const Icon(Icons.edit_rounded, size: 14, color: AppColors.onPrimary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(name, textAlign: TextAlign.center, style: AppTextStyles.title1.copyWith(fontSize: 22)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _StatTile(stat: stats[i])),
                ],
              ],
            ),
          ],
          if (infos.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < infos.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _InfoTile(info: infos[i])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;

  const _Initials({required this.name});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first[0].toUpperCase()
            : (parts.first[0] + parts.last[0]).toUpperCase();
    return Center(
      child: Text(
        initials,
        style: AppTextStyles.title1.copyWith(color: AppColors.onPrimary, fontSize: 28),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final ProfileStat stat;

  const _StatTile({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat.icon, size: 17, color: stat.color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(stat.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title2.copyWith(fontSize: 17)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(stat.label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final ProfileInfo info;

  const _InfoTile({required this.info});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: info.color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(info.icon, size: 20, color: info.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.label.toUpperCase(),
                  style: AppTextStyles.label.copyWith(color: AppColors.textMuted, fontSize: 10.5, letterSpacing: 0.6)),
              Text(info.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entrée de menu : icône teintée, titre, sous-titre, chevron.
class ProfileMenuItem {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color = AppColors.primary,
  });
}

/// Groupe de menus dans une carte en relief, titre de section au-dessus.
class ProfileMenuCard extends StatelessWidget {
  final String? title;
  final List<ProfileMenuItem> items;

  const ProfileMenuCard({super.key, this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text(title!.toUpperCase(),
                style: AppTextStyles.label.copyWith(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1)),
          ),
        NeuBox(
          radius: 26,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 76, endIndent: 18, color: AppColors.border),
                _MenuRow(item: items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final ProfileMenuItem item;

  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(item.icon, size: 21, color: item.color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w700)),
                  if (item.subtitle != null)
                    Text(item.subtitle!,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Déconnexion : bouton en relief, texte rouge.
class ProfileLogoutButton extends StatelessWidget {
  final VoidCallback onTap;

  const ProfileLogoutButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NeuButton(label: 'Se déconnecter', icon: Icons.logout_rounded, color: AppColors.danger, onPressed: onTap);
  }
}

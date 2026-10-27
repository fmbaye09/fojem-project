import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/language_preference.dart';

/// Sélection de la langue de l'application. Le choix est enregistré
/// localement (voir `LanguagePreference`) mais l'interface reste en
/// français pour l'instant : aucune traduction n'est câblée derrière ce
/// réglage aujourd'hui, on ne prétend pas le contraire.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selected = LanguagePreference.defaultCode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = await LanguagePreference.load();
    if (!mounted) return;
    setState(() {
      _selected = code;
      _isLoading = false;
    });
  }

  Future<void> _select(String code) async {
    if (code == _selected) return;
    setState(() => _selected = code);
    await LanguagePreference.save(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Langue enregistrée : ${LanguagePreference.labelFor(code)}'),
        backgroundColor: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(title: 'Langue', onBack: () => context.pop()),
      body: _isLoading
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: AppSpacing.cardPadding,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Seul le français est disponible dans l\'application pour le moment. Votre choix sera appliqué dès que les autres langues seront prêtes.',
                            style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    color: AppColors.surface,
                    child: Column(
                      children: LanguagePreference.labels.entries.map((entry) {
                        final isLast = entry.key == LanguagePreference.labels.keys.last;
                        return Column(
                          children: [
                            _LanguageTile(
                              code: entry.key,
                              label: entry.value,
                              isSelected: entry.key == _selected,
                              onTap: () => _select(entry.key),
                            ),
                            if (!isLast)
                              const Divider(height: 1, color: AppColors.border, indent: 52),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String code;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.code,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.language, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

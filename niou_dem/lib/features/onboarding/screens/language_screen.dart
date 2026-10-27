import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/services/language_preference.dart';

class _Language {
  final String code;
  final String nativeName;
  final String localName;
  final String flag;

  const _Language({
    required this.code,
    required this.nativeName,
    required this.localName,
    required this.flag,
  });
}

const _languages = [
  _Language(
    code: 'fr',
    nativeName: 'Français',
    localName: 'French',
    flag: '🇫🇷',
  ),
  _Language(
    code: 'wo',
    nativeName: 'Wolof',
    localName: 'Wolof',
    flag: '🇸🇳',
  ),
  _Language(
    code: 'en',
    nativeName: 'English',
    localName: 'Anglais',
    flag: '🇬🇧',
  ),
];

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selectedCode = LanguagePreference.defaultCode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final code = await LanguagePreference.getLanguageCode();
    if (mounted) setState(() => _selectedCode = code);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await LanguagePreference.setLanguageCode(_selectedCode);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/profile/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Langue'),
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/profile/settings'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Choisir la\nlangue',
                style: AppTextStyles.display,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Sélectionnez votre langue préférée',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Expanded(
                child: Column(
                  children: _languages.map((lang) {
                    final isSelected = lang.code == _selectedCode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _LanguageCard(
                        language: lang,
                        isSelected: isSelected,
                        onTap: () =>
                            setState(() => _selectedCode = lang.code),
                      ),
                    );
                  }).toList(),
                ),
              ),
              _ContinueButton(
                isLoading: _isSaving,
                onTap: _isSaving ? null : _save,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final _Language language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            Text(
              language.flag,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.nativeName,
                    style: AppTextStyles.bodyLargeSemibold,
                  ),
                  Text(
                    language.localName,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isLoading;

  const _ContinueButton({required this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Text('Enregistrer'),
      ),
    );
  }
}

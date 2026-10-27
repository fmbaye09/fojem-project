import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/utils/external_links.dart';

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}

const _faqs = [
  _FaqItem(
    question: 'Comment annuler une réservation ?',
    answer:
        'Vous pouvez annuler votre réservation depuis "Mes trajets" jusqu\'à 2 heures avant le départ. Les annulations tardives peuvent être soumises à des frais. Contactez notre support pour toute situation exceptionnelle.',
  ),
  _FaqItem(
    question: 'Que faire si le chauffeur ne se présente pas ?',
    answer:
        'Contactez immédiatement notre support via le bouton ci-dessous. Nous vous mettrons en contact avec le chauffeur et, en cas d\'absence injustifiée, vous proposerons un remboursement complet ou un trajet alternatif.',
  ),
  _FaqItem(
    question: 'Comment sont vérifiés les chauffeurs ?',
    answer:
        'Tous les chauffeurs passent par une vérification d\'identité, une inspection du véhicule et un contrôle de casier judiciaire. Seuls les conducteurs avec une note supérieure à 4.0 peuvent continuer à opérer sur la plateforme.',
  ),
  _FaqItem(
    question: 'Puis-je voyager avec des bagages ?',
    answer:
        'Chaque passager a droit à un bagage de cabine et un bagage enregistré. Pour les bagages volumineux ou excédentaires, discutez directement avec le chauffeur lors de la réservation.',
  ),
  _FaqItem(
    question: 'Comment fonctionne le paiement ?',
    answer:
        'Actuellement, le paiement s\'effectue en espèces directement au chauffeur. Nous travaillons à l\'intégration de Wave, Orange Money et la carte bancaire prochainement.',
  ),
  _FaqItem(
    question: 'Comment modifier ou annuler un trajet (chauffeur) ?',
    answer:
        'Accédez à "Mes trajets publiés" depuis votre tableau de bord. Vous pouvez modifier l\'heure, le prix ou les notes jusqu\'à 1 heure avant le départ. Si des passagers ont déjà réservé, ils seront notifiés automatiquement.',
  ),
];

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(title: 'Aide et support', onBack: () => context.pop()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ContactBanner(),
            const SizedBox(height: AppSpacing.xl),
            Text('Questions fréquentes', style: AppTextStyles.title2),
            const SizedBox(height: AppSpacing.md),
            ..._faqs.map((faq) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _FaqCard(faq: faq),
                )),
            const SizedBox(height: AppSpacing.lg),
            _ContactSection(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _ContactBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.support_agent_outlined,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support disponible',
                  style: AppTextStyles.bodySemibold.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  'Lun - Sam · 7h00 - 22h00',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqCard extends StatefulWidget {
  final _FaqItem faq;

  const _FaqCard({required this.faq});

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.cardDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.faq.question,
                        style: AppTextStyles.bodySemibold,
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      widget.faq.answer,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nous contacter', style: AppTextStyles.title2),
        const SizedBox(height: AppSpacing.md),
        FojemButton.primary(
          label: 'Chat en direct',
          onPressed: () => ExternalLinks.chatComingSoon(context),
          prefixIcon: Icons.chat_bubble_outline,
        ),
        const SizedBox(height: AppSpacing.sm),
        FojemButton.secondary(
          label: 'Appeler le support',
          onPressed: () => ExternalLinks.call(context),
          prefixIcon: Icons.phone_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        FojemButton.ghost(
          label: 'Envoyer un email',
          onPressed: () => ExternalLinks.email(context),
          prefixIcon: Icons.email_outlined,
        ),
      ],
    );
  }
}

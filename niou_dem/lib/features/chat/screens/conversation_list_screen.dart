import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../models/app_user.dart';
import '../../../models/conversation.dart';
import '../../../providers/app_provider.dart';
import '../../../services/chat_repository.dart';
import '../../../services/user_repository.dart';

/// Onglet Messages : une ligne par conversation — photo, nom, aperçu du
/// dernier message, heure, pastille de non-lus. Toucher une ligne ouvre la
/// conversation.
class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  Stream<List<Conversation>>? _stream;
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<AppProvider>().user?.id;
    if (userId != _userId) {
      _userId = userId;
      _stream = userId == null ? null : ChatRepository().watchForUser(userId);
    }
  }

  void _retry() {
    final userId = context.read<AppProvider>().user?.id;
    if (userId != null) {
      context.read<AppProvider>().refreshUser();
      setState(() {
        _stream = ChatRepository().watchForUser(userId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BrandAppBar(title: 'Messages', subtitle: 'Vos échanges avec les chauffeurs'),
      body: SafeArea(
        bottom: false,
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: _stream == null
                  ? const _Empty()
                  : StreamBuilder<List<Conversation>>(
                      stream: _stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          if (kDebugMode) {
                            debugPrint('[Chat Firestore Error] ${snapshot.error}');
                          }
                          return _Notice(
                            'Impossible de charger vos messages pour le moment.',
                            onRetry: _retry,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2.5),
                          );
                        }
                        final conversations = snapshot.data!;
                        if (conversations.isEmpty) return const _Empty();
                        return ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: conversations.length,
                          separatorBuilder: (_, __) => const Padding(
                            padding:
                                EdgeInsets.only(left: 20 + 50 + 14, right: 20),
                            child: Divider(height: 1, color: Color(0xFFECEAE5)),
                          ),
                          itemBuilder: (context, index) => _ConversationTile(
                            conversation: conversations[index],
                            currentUserId: _userId!,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          const TravelerBottomNavBar(current: ClientTab.messages),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  final Conversation conversation;
  final String currentUserId;

  const _ConversationTile(
      {required this.conversation, required this.currentUserId});

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  late final Future<AppUser?> _other;

  String get _otherId =>
      widget.conversation.otherParticipant(widget.currentUserId);

  @override
  void initState() {
    super.initState();
    _other = UserRepository().fetch(_otherId).catchError((_) => null);
  }

  String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(t);
    if (diff == 1) return 'Hier';
    if (diff < 7) return DateFormat('EEEE', 'fr_FR').format(t);
    return DateFormat('dd/MM/yy').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final hasUnread = c.unreadCount > 0;
    final isMine = c.lastSenderId == widget.currentUserId;
    final preview = c.lastMessageText.isEmpty
        ? 'Nouvelle conversation'
        : (isMine ? 'Vous : ${c.lastMessageText}' : c.lastMessageText);

    return FutureBuilder<AppUser?>(
      future: _other,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = user?.name.isNotEmpty == true ? user!.name : 'Utilisateur';

        return InkWell(
          onTap: () => context.push(
            '/chat/${c.id}?name=${Uri.encodeComponent(name)}&otherId=$_otherId',
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                DriverAvatar(name: name, photoUrl: user?.photoUrl, size: 50),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyLargeSemibold
                                  .copyWith(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _timeLabel(c.lastMessageAt),
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 13,
                              color: hasUnread
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              fontWeight:
                                  hasUnread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 14,
                                color: hasUnread
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: hasUnread
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 10),
                            Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              height: 22,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                '${c.unreadCount}',
                                style: AppTextStyles.label.copyWith(
                                  color: Colors.white,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined,
                size: 44, color: AppColors.borderStrong),
            const SizedBox(height: 16),
            Text('Aucune conversation', style: AppTextStyles.bodyLargeSemibold),
            const SizedBox(height: 6),
            Text(
              'Contactez un chauffeur depuis le détail d’un trajet pour poser vos questions.',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Notice(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réessayer'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

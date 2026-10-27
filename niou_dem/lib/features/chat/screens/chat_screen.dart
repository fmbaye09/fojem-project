import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/voice_message.dart';
import '../../../models/app_user.dart';
import '../../../models/conversation.dart';
import '../../../providers/app_provider.dart';
import '../../../services/chat_media_repository.dart';
import '../../../services/chat_repository.dart';
import '../../../services/notification_repository.dart';
import '../../../services/user_repository.dart';

/// Conversation — fidèle à la maquette : en-tête (retour, photo, nom,
/// statut, menu), séparateurs de jour, bulles marine (envoyées) et pêche
/// (reçues) avec heure et accusé de lecture, champ de saisie avec trombone
/// et bouton rond : micro (message vocal) quand le champ est vide, envoi sinon. Temps réel via Firestore `snapshots()` ; la
/// notification push à la réception nécessite une Cloud Function côté
/// serveur.
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _repository = ChatRepository();
  final _media = ChatMediaRepository();
  final _textController = TextEditingController();
  late final Stream<List<ChatMessage>> _messages;
  AppUser? _otherUser;
  bool _canSend = false;
  bool _isRecording = false;
  bool _isSendingVoice = false;

  @override
  void initState() {
    super.initState();
    _messages = _repository.watchMessages(widget.conversationId);
    _textController.addListener(() {
      final canSend = _textController.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
    _loadOtherUser();
    _markRead();
  }

  Future<void> _loadOtherUser() async {
    final id = widget.otherUserId;
    if (id == null || id.isEmpty) return;
    try {
      final user = await UserRepository().fetch(id);
      if (mounted) setState(() => _otherUser = user);
    } catch (_) {
      // Le nom passé dans l'URL suffit pour l'en-tête.
    }
  }

  Future<void> _markRead() async {
    final userId = context.read<AppProvider>().user?.id;
    if (userId == null) return;
    try {
      await _repository.markRead(
          conversationId: widget.conversationId, userId: userId);
    } catch (_) {
      // Non bloquant : l'accusé de lecture n'empêche pas de discuter.
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    final userId = context.read<AppProvider>().user?.id;
    if (text.isEmpty || userId == null) return;
    _textController.clear();
    try {
      await _repository.sendMessage(
        conversationId: widget.conversationId,
        senderId: userId,
        text: text,
      );
      if (widget.otherUserId != null && widget.otherUserId!.isNotEmpty) {
        NotificationRepository().sendChatNotification(
          recipientId: widget.otherUserId!,
          message: text,
          conversationId: widget.conversationId,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _textController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Message non envoyé. Vérifiez votre connexion.')),
      );
    }
  }

  Future<void> _startRecording() async {
    if (!await requestMicrophone()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autorisez l’accès au micro pour envoyer un message vocal.')),
      );
      return;
    }
    if (mounted) setState(() => _isRecording = true);
  }

  /// Envoie le fichier au backend puis publie le message dans Firestore.
  Future<void> _sendVoice(VoiceRecording recording) async {
    final userId = context.read<AppProvider>().user?.id;
    setState(() {
      _isRecording = false;
      _isSendingVoice = true;
    });
    try {
      if (userId == null) throw StateError('not signed in');
      final url = await _media.uploadVoice(recording.file.path, recording.duration);
      await _repository.sendVoiceMessage(
        conversationId: widget.conversationId,
        senderId: userId,
        audioUrl: url,
        durationMs: recording.duration.inMilliseconds,
      );
      if (widget.otherUserId != null && widget.otherUserId!.isNotEmpty) {
        NotificationRepository().sendChatNotification(
          recipientId: widget.otherUserId!,
          message: kVoiceMessagePreview,
          conversationId: widget.conversationId,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message vocal non envoyé. Vérifiez votre connexion.')),
        );
      }
    } finally {
      recording.file.delete().ignore();
      if (mounted) setState(() => _isSendingVoice = false);
    }
  }

  void _openMenu() {
    final otherId = widget.otherUserId;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (otherId != null && otherId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded,
                    color: AppColors.textPrimary),
                title: Text('Voir le profil', style: AppTextStyles.bodyLarge),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/profile/driver/$otherId');
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.danger),
              title: Text('Signaler un problème',
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.danger)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/support');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AppProvider>().user?.id;
    final name = _otherUser?.name.isNotEmpty == true
        ? _otherUser!.name
        : widget.otherUserName;
    final photoUrl = _otherUser?.photoUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(
              name: name,
              photoUrl: photoUrl,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/chat'),
              onMenu: _openMenu,
            ),
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _messages,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _CenteredText(
                        'Impossible de charger la conversation.');
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2.5),
                    );
                  }
                  final messages = snapshot.data!;
                  if (messages.isEmpty) {
                    return _CenteredText(
                      'Posez votre question à ${name.split(' ').first} : '
                      'lieu de rendez-vous, bagages, horaire…',
                    );
                  }
                  return _MessageList(
                    messages: messages,
                    currentUserId: currentUserId,
                    otherName: name,
                    otherPhotoUrl: photoUrl,
                  );
                },
              ),
            ),
            if (_isSendingVoice)
              const LinearProgressIndicator(minHeight: 2, color: AppColors.primary, backgroundColor: Colors.transparent),
            if (_isRecording)
              VoiceRecorderBar(
                onSend: _sendVoice,
                onCancel: () => setState(() => _isRecording = false),
              )
            else
              _Composer(
                controller: _textController,
                canSend: _canSend,
                onSend: _send,
                onMic: _isSendingVoice ? null : _startRecording,
                onAttach: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('L’envoi de pièces jointes arrive bientôt.')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  const _ChatHeader({
    required this.name,
    required this.photoUrl,
    required this.onBack,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Retour',
            icon: const Icon(Icons.arrow_back_rounded,
                size: 26, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          DriverAvatar(name: name, photoUrl: photoUrl, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title1.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.seatBadge,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'En ligne',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.seatBadge,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onMenu,
            tooltip: 'Plus d’options',
            icon: const Icon(Icons.more_vert_rounded,
                size: 26, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String? currentUserId;
  final String otherName;
  final String? otherPhotoUrl;

  const _MessageList({
    required this.messages,
    required this.currentUserId,
    required this.otherName,
    required this.otherPhotoUrl,
  });

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    // Liste inversée : le plus récent en bas, et le clavier pousse la
    // conversation vers le haut sans saut.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final index = messages.length - 1 - i;
        final message = messages[index];
        final previous = index > 0 ? messages[index - 1] : null;
        final isMine = message.senderId == currentUserId;
        final startsDay = previous == null ||
            !_sameDay(previous.timestamp, message.timestamp);
        final startsGroup = startsDay || previous.senderId != message.senderId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (startsDay) _DayDivider(date: message.timestamp),
            SizedBox(height: startsDay ? 4 : (startsGroup ? 22 : 8)),
            isMine
                ? _SentBubble(message: message)
                : _ReceivedBubble(
                    message: message,
                    showAvatar: startsGroup,
                    name: otherName,
                    photoUrl: otherPhotoUrl,
                  ),
          ],
        );
      },
    );
  }
}

Widget _voicePlayer(ChatMessage message, Color color) => VoiceMessagePlayer(
      url: message.audioUrl!,
      duration: Duration(milliseconds: message.durationMs ?? 0),
      color: color,
    );

const _bubbleRadius = BorderRadius.all(Radius.circular(14));
const _bubblePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

class _SentBubble extends StatelessWidget {
  final ChatMessage message;

  const _SentBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: _bubbleRadius,
            ),
            child: Padding(
              padding: _bubblePadding,
              child: message.isVoice
                  ? _voicePlayer(message, Colors.white)
                  : Text(
                message.text,
                style: AppTextStyles.bodyLarge
                    .copyWith(fontSize: 15, color: Colors.white, height: 1.45),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('HH:mm').format(message.timestamp),
                style: _timeStyle),
            const SizedBox(width: 6),
            Icon(
              message.read ? Icons.done_all_rounded : Icons.done_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceivedBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAvatar;
  final String name;
  final String? photoUrl;

  const _ReceivedBubble({
    required this.message,
    required this.showAvatar,
    required this.name,
    required this.photoUrl,
  });

  static const double _avatarSize = 36;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.66;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _avatarSize,
          child: showAvatar
              ? DriverAvatar(name: name, photoUrl: photoUrl, size: _avatarSize)
              : null,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: _bubbleRadius,
                  ),
                  child: Padding(
                    padding: _bubblePadding,
                    child: message.isVoice
                        ? _voicePlayer(message, const Color(0xFF1C1C1A))
                        : Text(
                      message.text,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 15,
                        color: const Color(0xFF1C1C1A),
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(DateFormat('HH:mm').format(message.timestamp),
                  style: _timeStyle),
            ],
          ),
        ),
      ],
    );
  }
}

final TextStyle _timeStyle = AppTextStyles.caption.copyWith(
  fontSize: 13,
  color: AppColors.textMuted,
  height: 1,
);

class _DayDivider extends StatelessWidget {
  final DateTime date;

  const _DayDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'Aujourd’hui'
        : diff == 1
            ? 'Hier'
            : DateFormat('EEEE d MMMM', 'fr_FR').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border, height: 1)),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback? onMic;
  final VoidCallback onAttach;

  const _Composer({
    required this.controller,
    required this.canSend,
    required this.onSend,
    required this.onMic,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: onAttach,
              tooltip: 'Joindre un fichier',
              icon: Transform.rotate(
                angle: 0.6,
                child: const Icon(Icons.attach_file_rounded,
                    size: 26, color: AppColors.primary),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  style: AppTextStyles.bodyLarge.copyWith(height: 1.35),
                  decoration: InputDecoration(
                    hintText: 'Écrire un message…',
                    hintStyle: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                    isDense: true,
                    filled: false,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Champ vide : micro (message vocal) ; sinon : envoi du texte.
            Semantics(
              button: true,
              label: canSend ? 'Envoyer' : 'Enregistrer un message vocal',
              child: Material(
                color: canSend || onMic != null
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: canSend ? onSend : onMic,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(canSend ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredText extends StatelessWidget {
  final String text;

  const _CenteredText(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

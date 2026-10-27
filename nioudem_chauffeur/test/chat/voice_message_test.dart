import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/widgets/voice_message.dart';
import 'package:fojem_chauffeur/models/conversation.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('a voice message survives the Firestore round trip', () {
    final message = ChatMessage(
      id: '',
      senderId: 'u1',
      text: '🎤 Message vocal',
      timestamp: DateTime(2026, 10, 27, 22),
      read: false,
      type: 'voice',
      audioUrl: 'https://api.example/storage/chat-voice/a.m4a',
      durationMs: 42000,
    );

    final copy = ChatMessage.fromMap('m1', message.toMap());

    expect(copy.isVoice, isTrue);
    expect(copy.audioUrl, message.audioUrl);
    expect(copy.durationMs, 42000);
  });

  test('older messages without a type are plain text', () {
    final copy = ChatMessage.fromMap('m1', {'senderId': 'u1', 'text': 'Salut', 'read': true});

    expect(copy.isVoice, isFalse);
    expect(copy.type, 'text');
  });

  test('durations read as minutes and seconds', () {
    expect(formatVoiceDuration(const Duration(seconds: 7)), '0:07');
    expect(formatVoiceDuration(const Duration(minutes: 1, seconds: 42)), '1:42');
  });

  testWidgets('the player shows the length before playing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: VoiceMessagePlayer(
            url: 'https://api.example/storage/chat-voice/a.m4a',
            duration: Duration(seconds: 42),
            color: Colors.black,
          ),
        ),
      ),
    ));

    expect(find.text('0:42'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}

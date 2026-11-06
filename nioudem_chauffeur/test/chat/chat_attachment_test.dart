import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_chauffeur/core/widgets/chat_attachment.dart';
import 'package:fojem_chauffeur/models/conversation.dart';
import 'package:fojem_chauffeur/services/chat_repository.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('a photo and a document survive the Firestore round trip', () {
    final photo = ChatMessage.fromMap('m1', ChatMessage(
      id: '',
      senderId: 'u1',
      text: attachmentPreview(isImage: true, name: 'bagages.jpg'),
      timestamp: DateTime(2026, 11, 4, 21),
      read: false,
      type: 'image',
      fileUrl: 'https://api.example/storage/chat-attachments/a.jpg',
      fileName: 'bagages.jpg',
      fileSize: 420000,
    ).toMap());
    expect(photo.isImage, isTrue);
    expect(photo.isFile, isFalse);
    expect(photo.text, '📷 Photo');

    final document = ChatMessage.fromMap('m2', {
      'senderId': 'u1',
      'text': attachmentPreview(isImage: false, name: 'billet.pdf'),
      'type': 'file',
      'fileUrl': 'https://api.example/storage/chat-attachments/b.pdf',
      'fileName': 'billet.pdf',
      'fileSize': 2500000,
    });
    expect(document.isFile, isTrue);
    expect(document.fileName, 'billet.pdf');
    expect(document.fileSize, 2500000);
    expect(document.text, '📎 billet.pdf');
  });

  test('an attachment without its file is shown as text', () {
    final message = ChatMessage.fromMap('m1', {'senderId': 'u1', 'text': '📷 Photo', 'type': 'image'});
    expect(message.isImage, isFalse);
  });

  test('file sizes read in Ko and Mo', () {
    expect(formatFileSize(850 * 1024), '850 Ko');
    expect(formatFileSize(1000), '1 Ko');
    expect(formatFileSize((2.4 * 1024 * 1024).round()), '2,4 Mo');
  });

  testWidgets('a document shows its name, type and size', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            child: ChatFileAttachment(
              url: 'https://api.example/storage/chat-attachments/b.pdf',
              name: 'Billet de train Dakar Thiès du 4 novembre.pdf',
              size: 2500000,
              color: Colors.black,
            ),
          ),
        ),
      ),
    ));

    expect(find.textContaining('Billet de train'), findsOneWidget);
    expect(find.text('PDF · 2,4 Mo'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

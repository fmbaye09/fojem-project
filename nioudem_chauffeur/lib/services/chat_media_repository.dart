import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Fichiers audio des messages vocaux (`POST /api/chat/voice`). Le message
/// lui-même part ensuite dans Firestore avec l'URL renvoyée.
class ChatMediaRepository {
  final ApiClient _client;

  ChatMediaRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<String> uploadVoice(String filePath, Duration duration) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: 'voice.m4a', contentType: DioMediaType('audio', 'mp4')),
      'duration_ms': duration.inMilliseconds,
    });
    final response = await _client.postMultipart('/chat/voice', form);
    return response['url'] as String;
  }
}

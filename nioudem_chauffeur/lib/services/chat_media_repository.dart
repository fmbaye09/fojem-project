import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Fichiers du chat : messages vocaux (`POST /api/chat/voice`), photos et
/// documents (`POST /api/chat/attachments`). Le message lui-même part
/// ensuite dans Firestore avec l'URL renvoyée.
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

  /// Photo ou document (10 Mo au plus) ; le backend dit lequel des deux.
  Future<({String url, bool isImage, String name, int size})> uploadAttachment(String filePath, String name) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: name),
    });
    final response = await _client.postMultipart('/chat/attachments', form);
    return (
      url: response['url'] as String,
      isImage: response['kind'] == 'image',
      name: response['name'] as String? ?? name,
      size: (response['size'] as num?)?.toInt() ?? 0,
    );
  }
}

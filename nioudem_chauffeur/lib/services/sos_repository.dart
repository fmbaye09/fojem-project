import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/widgets/sos.dart';

/// SOS contre l'API Laravel (`/api/sos-alerts`).
class SosRepository implements SosApi {
  final ApiClient _client;

  SosRepository({ApiClient? client}) : _client = client ?? ApiClient();

  @override
  Future<String> trigger({
    required double lat,
    required double lng,
    String? tripId,
    String? bookingId,
    required String role,
  }) async {
    final body = await _client.post('/sos-alerts', data: {
      'lat': lat,
      'lng': lng,
      'role': role,
      if (tripId != null) 'trip_id': tripId,
      if (bookingId != null) 'booking_id': bookingId,
    });
    return '${body['sos_alert']['id']}';
  }

  @override
  Future<void> sendLocation(String alertId, double lat, double lng) =>
      _client.post('/sos-alerts/$alertId/location', data: {'lat': lat, 'lng': lng});

  @override
  Future<void> uploadRecording(String alertId, String filePath, Duration duration) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: 'sos.m4a', contentType: DioMediaType('audio', 'mp4')),
      'duration_ms': duration.inMilliseconds,
    });
    await _client.postMultipart('/sos-alerts/$alertId/recordings', form);
  }

  @override
  Future<void> end(String alertId) => _client.post('/sos-alerts/$alertId/end');
}

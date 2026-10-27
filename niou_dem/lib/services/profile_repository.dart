import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../models/app_user.dart';

/// Repository pour la gestion du profil utilisateur (nom, téléphone, photo).
class ProfileRepository {
  final ApiClient _client;

  ProfileRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  Future<AppUser> updateProfile({String? fullName, String? phoneNumber}) async {
    final response = await _client.patch('/profile', data: {
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
    });
    return AppUser.fromApi(response['user'] as Map<String, dynamic>);
  }

  Future<AppUser> updatePhoto(String filePath) async {
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath),
    });
    final response = await _client.post('/profile/photo', data: formData);
    return AppUser.fromApi(response['user'] as Map<String, dynamic>);
  }
}

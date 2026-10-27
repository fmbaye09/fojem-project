import 'dart:io';
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../models/app_user.dart';

class IdentityStatusData {
  final String status; // 'none', 'pending', 'approved', 'rejected'
  final String? documentType; // 'id_card', 'driver_license'
  final String? documentNumber;
  final String? frontUrl;
  final String? backUrl;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final bool isVerified;

  const IdentityStatusData({
    required this.status,
    this.documentType,
    this.documentNumber,
    this.frontUrl,
    this.backUrl,
    this.rejectionReason,
    this.submittedAt,
    this.isVerified = false,
  });

  factory IdentityStatusData.fromJson(Map<String, dynamic> json) {
    return IdentityStatusData(
      status: json['identity_status'] as String? ?? 'none',
      documentType: json['document_type'] as String?,
      documentNumber: json['document_number'] as String?,
      frontUrl: json['front_url'] as String?,
      backUrl: json['back_url'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      submittedAt: DateTime.tryParse(json['submitted_at'] as String? ?? ''),
      isVerified: json['is_verified'] == true,
    );
  }
}

class IdentityVerificationRepository {
  final ApiClient _api;

  IdentityVerificationRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  Future<IdentityStatusData> fetch() async {
    final response = await _api.get('/profile/identity');
    return IdentityStatusData.fromJson(response);
  }

  Future<AppUser> submit({
    required String documentType, // 'id_card' | 'driver_license'
    String? documentNumber,
    required File frontPhoto,
    File? backPhoto,
  }) async {
    final map = <String, dynamic>{
      'document_type': documentType,
      'front_file': await MultipartFile.fromFile(
        frontPhoto.path,
        filename: 'front_$documentType.jpg',
      ),
    };

    if (documentNumber != null && documentNumber.trim().isNotEmpty) {
      map['document_number'] = documentNumber.trim();
    }

    if (backPhoto != null) {
      map['back_file'] = await MultipartFile.fromFile(
        backPhoto.path,
        filename: 'back_$documentType.jpg',
      );
    }

    final formData = FormData.fromMap(map);
    final response = await _api.post('/profile/identity', data: formData);

    final userJson = response['user'] as Map<String, dynamic>?;
    if (userJson != null) {
      return AppUser.fromApi(userJson);
    }
    throw Exception('Réponse inattendue lors de l’envoi des documents.');
  }
}

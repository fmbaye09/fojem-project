import '../core/network/api_config.dart';

enum UserRole { traveler, driver }

class AppUser {
  final String id;
  final String name;
  final String phoneNumber;
  final String email;
  final String? photoUrl;
  final UserRole role;
  final DateTime createdAt;
  final String? fcmToken;
  final double rating;
  final int ratingCount;
  final bool identityVerified;
  final String identityStatus; // 'none', 'pending', 'approved', 'rejected'
  final String? identityDocumentType; // 'id_card', 'driver_license'
  final String? identityDocumentNumber;
  final String? identityFrontPhotoUrl;
  final String? identityBackPhotoUrl;
  final String? identityRejectionReason;
  final int totalTrips;

  const AppUser({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.email = '',
    this.photoUrl,
    required this.role,
    required this.createdAt,
    this.fcmToken,
    this.rating = 0,
    this.ratingCount = 0,
    this.identityVerified = false,
    this.identityStatus = 'none',
    this.identityDocumentType,
    this.identityDocumentNumber,
    this.identityFrontPhotoUrl,
    this.identityBackPhotoUrl,
    this.identityRejectionReason,
    this.totalTrips = 0,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  bool get isDriver => role == UserRole.driver;

  /// Construit l'utilisateur à partir de la réponse du backend Laravel
  /// (`/api/auth/register`, `/api/auth/login`, `/api/auth/me` — champ
  /// `user`).
  factory AppUser.fromApi(Map<String, dynamic> map) {
    final driver = map['driver'] as Map<String, dynamic>?;
    final status = (map['identity_status'] as String?) ?? 'none';
    final isApproved = status == 'approved' ||
        map['identity_verified'] == true ||
        (driver != null && driver['verification_status'] == 'approved');

    return AppUser(
      id: map['id'] as String? ?? '',
      name: map['full_name'] as String? ?? '',
      phoneNumber: map['phone_number'] as String? ?? '',
      email: map['email'] as String? ?? '',
      photoUrl: ApiConfig.resolveMediaUrl(map['profile_photo_url'] as String?),
      role: map['is_driver'] == true ? UserRole.driver : UserRole.traveler,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      rating: driver != null
          ? double.tryParse('${driver['average_rating'] ?? ''}') ?? 0.0
          : 0.0,
      ratingCount: 0,
      identityVerified: isApproved,
      identityStatus: status,
      identityDocumentType: map['identity_document_type'] as String?,
      identityDocumentNumber: map['identity_document_number'] as String?,
      identityFrontPhotoUrl: ApiConfig.resolveMediaUrl(map['identity_front_url'] as String?),
      identityBackPhotoUrl: ApiConfig.resolveMediaUrl(map['identity_back_url'] as String?),
      identityRejectionReason: map['identity_rejection_reason'] as String?,
      totalTrips: driver != null
          ? int.tryParse('${driver['total_trips_completed'] ?? ''}') ?? 0
          : 0,
    );
  }

  AppUser copyWith({
    String? name,
    String? phoneNumber,
    String? email,
    String? photoUrl,
    UserRole? role,
    String? fcmToken,
    double? rating,
    int? ratingCount,
    bool? identityVerified,
    String? identityStatus,
    String? identityDocumentType,
    String? identityDocumentNumber,
    String? identityFrontPhotoUrl,
    String? identityBackPhotoUrl,
    String? identityRejectionReason,
    int? totalTrips,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      createdAt: createdAt,
      fcmToken: fcmToken ?? this.fcmToken,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      identityVerified: identityVerified ?? this.identityVerified,
      identityStatus: identityStatus ?? this.identityStatus,
      identityDocumentType: identityDocumentType ?? this.identityDocumentType,
      identityDocumentNumber: identityDocumentNumber ?? this.identityDocumentNumber,
      identityFrontPhotoUrl: identityFrontPhotoUrl ?? this.identityFrontPhotoUrl,
      identityBackPhotoUrl: identityBackPhotoUrl ?? this.identityBackPhotoUrl,
      identityRejectionReason: identityRejectionReason ?? this.identityRejectionReason,
      totalTrips: totalTrips ?? this.totalTrips,
    );
  }
}

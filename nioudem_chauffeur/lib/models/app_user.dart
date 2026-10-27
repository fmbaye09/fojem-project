import '../core/network/api_config.dart';

enum UserRole { traveler, driver }

/// Statut de vérification du profil chauffeur (`drivers.verification_status`
/// côté backend). `none` = ce compte n'a pas encore de profil `drivers` du
/// tout (ne devrait pas arriver dans cette app, qui appelle systématiquement
/// `/auth/become-driver` juste après l'inscription).
enum DriverVerificationStatus { none, pending, approved, rejected }

DriverVerificationStatus _driverStatusFromString(String? value) {
  switch (value) {
    case 'approved':
      return DriverVerificationStatus.approved;
    case 'rejected':
      return DriverVerificationStatus.rejected;
    case 'pending':
      return DriverVerificationStatus.pending;
    default:
      return DriverVerificationStatus.none;
  }
}

/// Profil utilisateur — reflète désormais la réponse JSON de l'API Laravel
/// (`users` + relation `driver` chargée par `/auth/me`, `/auth/register`,
/// `/auth/login`), plus le doc `firebase_custom_token` éphémère utilisé une
/// seule fois pour le pont chat (jamais stocké dans ce modèle).
class AppUser {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String? photoUrl;
  final String? gender;
  final UserRole role;

  /// Id du profil `drivers` (distinct de l'id utilisateur) — nécessaire pour
  /// certains appels API scoping côté chauffeur.
  final String? driverId;
  final DriverVerificationStatus driverStatus;
  final bool hasSubmittedDocuments;
  final int documentsCount;
  final double rating;
  final int totalTrips;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.photoUrl,
    this.gender,
    required this.role,
    this.driverId,
    this.driverStatus = DriverVerificationStatus.none,
    this.hasSubmittedDocuments = false,
    this.documentsCount = 0,
    this.rating = 0,
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
  bool get isApprovedDriver => driverStatus == DriverVerificationStatus.approved;
  bool get isRejectedDriver => driverStatus == DriverVerificationStatus.rejected;
  bool get isPendingReview => driverStatus == DriverVerificationStatus.pending && hasSubmittedDocuments;
  bool get hasNotSubmittedYet => driverStatus != DriverVerificationStatus.approved && !hasSubmittedDocuments;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    return AppUser(
      id: json['id'] as String? ?? '',
      name: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? '',
      photoUrl: ApiConfig.resolveMediaUrl(json['profile_photo_url'] as String?),
      gender: json['gender'] as String?,
      role: (json['is_driver'] as bool? ?? driver != null)
          ? UserRole.driver
          : UserRole.traveler,
      driverId: driver?['id'] as String?,
      driverStatus: _driverStatusFromString(driver?['verification_status'] as String?),
      hasSubmittedDocuments: driver?['has_submitted_documents'] as bool? ??
          ((driver?['documents_count'] as int? ?? 0) > 0),
      documentsCount: driver?['documents_count'] as int? ?? 0,
      rating: double.tryParse('${driver?['average_rating'] ?? 0}') ?? 0,
      totalTrips: driver?['total_trips_completed'] as int? ?? 0,
    );
  }

  AppUser copyWith({
    String? name,
    String? photoUrl,
    String? driverId,
    DriverVerificationStatus? driverStatus,
    bool? hasSubmittedDocuments,
    int? documentsCount,
    double? rating,
    int? totalTrips,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email,
      phoneNumber: phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      gender: gender,
      role: role,
      driverId: driverId ?? this.driverId,
      driverStatus: driverStatus ?? this.driverStatus,
      hasSubmittedDocuments: hasSubmittedDocuments ?? this.hasSubmittedDocuments,
      documentsCount: documentsCount ?? this.documentsCount,
      rating: rating ?? this.rating,
      totalTrips: totalTrips ?? this.totalTrips,
    );
  }
}

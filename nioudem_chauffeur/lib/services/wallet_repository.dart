import '../core/network/api_client.dart';

/// Ligne du grand livre `transactions` (append-only, voir
/// `fojem_backend/app/Services/WalletService.php`).
class WalletTransaction {
  final String id;
  final String type;
  final String status;
  final double amount;
  final String? bookingId;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.bookingId,
    required this.createdAt,
  });

  factory WalletTransaction.fromApiJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      amount: double.tryParse('${json['amount'] ?? 0}') ?? 0,
      bookingId: json['booking_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Portefeuille du chauffeur connecté (`/api/wallet*`).
///
/// GAP BACKEND : à ce jour, `app/Services/WalletService.php` n'est appelé
/// que par `PayoutRequestController::process()` (traitement d'un retrait
/// admin) — rien ne crédite le wallet du chauffeur automatiquement quand
/// une réservation passe `completed`. Les "gains" affichés par cet écran
/// reflètent donc fidèlement le grand livre réel, mais ce dernier restera
/// vide tant que le backend n'ajoute pas cette logique de crédit.
class WalletRepository {
  final ApiClient _client;

  WalletRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<double> fetchBalance() async {
    final body = await _client.get('/wallet');
    final wallet = body['wallet'] as Map<String, dynamic>?;
    return double.tryParse('${wallet?['balance'] ?? 0}') ?? 0;
  }

  Future<List<WalletTransaction>> fetchTransactions() async {
    final body = await _client.get('/wallet/transactions');
    final rows = (body['data'] as List?) ?? const [];
    return rows
        .cast<Map<String, dynamic>>()
        .map(WalletTransaction.fromApiJson)
        .toList();
  }
}

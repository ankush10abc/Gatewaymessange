import '../../../core/constants/enums.dart';

class PaymentModel {
  final String id;
  final String bookingId;
  final double amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final String? transactionId;
  final DateTime createdAt;

  PaymentModel({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.method,
    required this.status,
    this.transactionId,
    required this.createdAt,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'],
      bookingId: json['bookingId'],
      amount: json['amount'].toDouble(),
      method: PaymentMethod.values.firstWhere((e) => e.name == json['method']),
      status: PaymentStatus.values.firstWhere((e) => e.name == json['status']),
      transactionId: json['transactionId'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookingId': bookingId,
      'amount': amount,
      'method': method.name,
      'status': status.name,
      'transactionId': transactionId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class CreatePaymentRequest {
  final String bookingId;
  final double amount;
  final PaymentMethod method;

  CreatePaymentRequest({
    required this.bookingId,
    required this.amount,
    required this.method,
  });

  Map<String, dynamic> toJson() {
    return {
      'bookingId': bookingId,
      'amount': amount,
      'method': method.name,
    };
  }
}

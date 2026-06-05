import '../../../core/constants/enums.dart';

class BookingModel {
  final String id;
  final String userId;
  final String agentId;
  final String serviceId;
  final String serviceName;
  final DateTime bookingDate;
  final String timeSlot;
  final double amount;
  final BookingStatus status;
  final PaymentStatus paymentStatus;
  final String? notes;
  final DateTime createdAt;

  BookingModel({
    required this.id,
    required this.userId,
    required this.agentId,
    required this.serviceId,
    required this.serviceName,
    required this.bookingDate,
    required this.timeSlot,
    required this.amount,
    required this.status,
    required this.paymentStatus,
    this.notes,
    required this.createdAt,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    return BookingModel(
      id: json['id'],
      userId: json['userId'],
      agentId: json['agentId'],
      serviceId: json['serviceId'],
      serviceName: json['serviceName'],
      bookingDate: DateTime.parse(json['bookingDate']),
      timeSlot: json['timeSlot'],
      amount: json['amount'].toDouble(),
      status: BookingStatus.values.firstWhere((e) => e.name == json['status']),
      paymentStatus: PaymentStatus.values.firstWhere((e) => e.name == json['paymentStatus']),
      notes: json['notes'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'agentId': agentId,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'bookingDate': bookingDate.toIso8601String(),
      'timeSlot': timeSlot,
      'amount': amount,
      'status': status.name,
      'paymentStatus': paymentStatus.name,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class CreateBookingRequest {
  final String agentId;
  final String serviceId;
  final DateTime bookingDate;
  final String timeSlot;
  final String? notes;

  CreateBookingRequest({
    required this.agentId,
    required this.serviceId,
    required this.bookingDate,
    required this.timeSlot,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'agentId': agentId,
      'serviceId': serviceId,
      'bookingDate': bookingDate.toIso8601String(),
      'timeSlot': timeSlot,
      'notes': notes,
    };
  }
}

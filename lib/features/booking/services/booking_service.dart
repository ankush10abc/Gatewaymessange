import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../models/booking_model.dart';

class BookingService {
  final ApiClient _apiClient;

  BookingService(this._apiClient);

  Future<BookingModel> createBooking(CreateBookingRequest request) async {
    final response = await _apiClient.post(AppConstants.epBookings, data: request.toJson());
    return BookingModel.fromJson(response['data']);
  }

  Future<List<BookingModel>> getBookings({String? status}) async {
    final response = await _apiClient.get(
      AppConstants.epBookings,
      queryParameters: status != null ? {'status': status} : null,
    );
    return (response['data'] as List)
        .map((json) => BookingModel.fromJson(json))
        .toList();
  }

  Future<BookingModel> getBookingById(String id) async {
    final response = await _apiClient.get('${AppConstants.epBookings}/$id');
    return BookingModel.fromJson(response['data']);
  }

  Future<BookingModel> updateBookingStatus(String id, String status) async {
    final response = await _apiClient.put(
      '${AppConstants.epBookings}/$id/status',
      data: {'status': status},
    );
    return BookingModel.fromJson(response['data']);
  }

  Future<void> cancelBooking(String id) async {
    await _apiClient.delete('${AppConstants.epBookings}/$id');
  }
}

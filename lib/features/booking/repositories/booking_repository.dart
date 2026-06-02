import '../../../core/storage/storage_service.dart';
import '../services/booking_service.dart';
import '../models/booking_model.dart';

class BookingRepository {
  final BookingService _bookingService;
  final StorageService _storageService;

  BookingRepository(this._bookingService, this._storageService);

  Future<BookingModel> createBooking(CreateBookingRequest request) async {
    final booking = await _bookingService.createBooking(request);
    // Cache booking
    final box = _storageService.getBookingsBox();
    await box.put(booking.id, booking.toJson());
    return booking;
  }

  Future<List<BookingModel>> getBookings({String? status}) async {
    try {
      final bookings = await _bookingService.getBookings(status: status);
      // Update cache
      final box = _storageService.getBookingsBox();
      for (var booking in bookings) {
        await box.put(booking.id, booking.toJson());
      }
      return bookings;
    } catch (e) {
      // Return cached data on error
      final box = _storageService.getBookingsBox();
      return box.values
          .map((json) => BookingModel.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    }
  }

  Future<BookingModel> getBookingById(String id) async {
    return await _bookingService.getBookingById(id);
  }

  Future<BookingModel> updateBookingStatus(String id, String status) async {
    return await _bookingService.updateBookingStatus(id, status);
  }

  Future<void> cancelBooking(String id) async {
    await _bookingService.cancelBooking(id);
    final box = _storageService.getBookingsBox();
    await box.delete(id);
  }
}

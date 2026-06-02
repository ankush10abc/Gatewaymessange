import 'package:flutter/material.dart';
import '../../../core/constants/enums.dart';
import '../repositories/booking_repository.dart';
import '../models/booking_model.dart';

class BookingViewModel extends ChangeNotifier {
  final BookingRepository _repository;

  BookingViewModel(this._repository);

  LoadingState _state = LoadingState.idle;
  LoadingState get state => _state;

  List<BookingModel> _bookings = [];
  List<BookingModel> get bookings => _bookings;

  BookingModel? _selectedBooking;
  BookingModel? get selectedBooking => _selectedBooking;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<bool> createBooking(CreateBookingRequest request) async {
    _state = LoadingState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final booking = await _repository.createBooking(request);
      _bookings.insert(0, booking);
      _state = LoadingState.success;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _state = LoadingState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadBookings({String? status}) async {
    _state = LoadingState.loading;
    notifyListeners();

    try {
      _bookings = await _repository.getBookings(status: status);
      _state = LoadingState.success;
    } catch (e) {
      _errorMessage = e.toString();
      _state = LoadingState.error;
    }
    notifyListeners();
  }

  Future<void> loadBookingById(String id) async {
    try {
      _selectedBooking = await _repository.getBookingById(id);
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    }
  }

  Future<bool> updateBookingStatus(String id, BookingStatus status) async {
    try {
      final updated = await _repository.updateBookingStatus(id, status.name);
      final index = _bookings.indexWhere((b) => b.id == id);
      if (index != -1) {
        _bookings[index] = updated;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  Future<bool> cancelBooking(String id) async {
    try {
      await _repository.cancelBooking(id);
      _bookings.removeWhere((b) => b.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }
}

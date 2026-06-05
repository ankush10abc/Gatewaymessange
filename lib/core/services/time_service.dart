import 'package:dio/dio.dart';

class TimeService {
  static DateTime? _cachedTime;
  static DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 5);

  static Future<DateTime> getCurrentTime() async {
    if (_cachedTime != null && _lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed < _cacheDuration) {
        return _cachedTime!.add(elapsed);
      }
    }

    try {
      final dio = Dio();
      final response = await dio.get(
        'https://timeapi.io/api/Time/current/zone',
        queryParameters: {'timeZone': 'Asia/Kolkata'},
      );

      final dateTimeStr = response.data['dateTime'] as String;
      _cachedTime = DateTime.parse(dateTimeStr);
      _lastFetchTime = DateTime.now();
      return _cachedTime!;
    } catch (e) {
      return DateTime.now();
    }
  }

  static void clearCache() {
    _cachedTime = null;
    _lastFetchTime = null;
  }
}

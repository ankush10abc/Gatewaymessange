import 'package:firebase_database/firebase_database.dart';
import 'package:hive/hive.dart';

class DatabaseOptimizer {
  static const String _cacheBoxName = 'firebase_cache';
  static const Duration _cacheExpiry = Duration(minutes: 5);
  
  static late Box _cacheBox;

  static Future<void> initialize() async {
    _cacheBox = await Hive.openBox(_cacheBoxName);
    
    // Configure Firebase for offline persistence
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(10 * 1024 * 1024); // 10MB
  }

  // Optimized query with caching
  static Stream<T> optimizedQuery<T>({
    required String path,
    required T Function(Map<String, dynamic>) fromJson,
    String? cacheKey,
    Duration? cacheDuration,
  }) {
    final key = cacheKey ?? path;
    final duration = cacheDuration ?? _cacheExpiry;
    
    return FirebaseDatabase.instance
        .ref(path)
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return null;
      
      final jsonData = Map<String, dynamic>.from(data);
      
      // Cache the result
      _cacheBox.put(key, {
        'data': jsonData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      return fromJson(jsonData);
    })
        .where((data) => data != null)
        .cast<T>();
  }

  // Get cached data if available and not expired
  static T? getCachedData<T>({
    required String cacheKey,
    required T Function(Map<String, dynamic>) fromJson,
    Duration? cacheDuration,
  }) {
    final duration = cacheDuration ?? _cacheExpiry;
    final cached = _cacheBox.get(cacheKey);
    
    if (cached != null) {
      final timestamp = cached['timestamp'] as int;
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      
      if (DateTime.now().difference(cacheTime) < duration) {
        return fromJson(Map<String, dynamic>.from(cached['data']));
      }
    }
    
    return null;
  }

  // Batch write operations for better performance
  static Future<void> batchWrite(Map<String, dynamic> updates) async {
    final ref = FirebaseDatabase.instance.ref();
    await ref.update(updates);
  }

  // Optimized pagination for large datasets
  static Query paginatedQuery({
    required String path,
    required String orderBy,
    int limit = 20,
    dynamic startAfter,
  }) {
    Query query = FirebaseDatabase.instance
        .ref(path)
        .orderByChild(orderBy)
        .limitToFirst(limit);
    
    if (startAfter != null) {
      query = query.startAfter(startAfter);
    }
    
    return query;
  }

  // Clear expired cache entries
  static Future<void> clearExpiredCache() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keysToDelete = <String>[];
    
    for (final key in _cacheBox.keys) {
      final cached = _cacheBox.get(key);
      if (cached != null) {
        final timestamp = cached['timestamp'] as int;
        if (now - timestamp > _cacheExpiry.inMilliseconds) {
          keysToDelete.add(key);
        }
      }
    }
    
    for (final key in keysToDelete) {
      await _cacheBox.delete(key);
    }
  }

  // Optimize Firebase connection
  static void optimizeConnection() {
    // Keep connection alive for better performance
    FirebaseDatabase.instance.goOnline();
    
    // Set up connection state monitoring
    FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      print('Firebase connection status: $connected');
    });
  }

  // Preload critical data
  static Future<void> preloadCriticalData(String userId) async {
    try {
      // Preload user data
      await FirebaseDatabase.instance
          .ref('users/$userId')
          .once()
          .then((snapshot) {
        if (snapshot.snapshot.exists) {
          _cacheBox.put('user_$userId', {
            'data': snapshot.snapshot.value,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });

      // Preload recent chats
      await FirebaseDatabase.instance
          .ref('chats')
          .orderByChild('updatedAt')
          .limitToLast(10)
          .once()
          .then((snapshot) {
        if (snapshot.snapshot.exists) {
          _cacheBox.put('recent_chats_$userId', {
            'data': snapshot.snapshot.value,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    } catch (e) {
      print('Preload failed: $e');
    }
  }

  // Database health check
  static Future<bool> checkDatabaseHealth() async {
    try {
      final startTime = DateTime.now();
      await FirebaseDatabase.instance.ref('.info/serverTimeOffset').once();
      final responseTime = DateTime.now().difference(startTime);
      
      return responseTime.inMilliseconds < 1000; // Consider healthy if < 1s
    } catch (e) {
      return false;
    }
  }
}
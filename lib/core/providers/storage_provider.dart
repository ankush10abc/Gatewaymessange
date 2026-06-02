import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final storageInitProvider = FutureProvider<void>((ref) async {
  final storage = ref.read(storageServiceProvider);
  await storage.init();
});
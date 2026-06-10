// import 'package:flutter/material.dart';
// import 'package:dio/dio.dart';
//
// import 'api_service.dart';
// import 'offline_queue_service.dart';
//
//
// /// Test all offline APIs integration
// class OfflineApiTest {
//   final ApiService apiService;
//
//   OfflineApiTest(this.apiService);
//
//   /// Test API 1: Batch Message Send
//   Future<void> testBatchSend() async {
//     debugPrint('🧪 Testing API 1: Batch Send');
//
//     final testMessages = [
//       {
//         'temp_id': 'test_temp_1',
//         'chat_id': '1',
//         'chat_type': 'group',
//         'message': 'Test message 1',
//         'type': 'text',
//         'firebase_key': 'test_fb_key_1',
//         'client_timestamp': DateTime.now().toIso8601String(),
//       },
//       {
//         'temp_id': 'test_temp_2',
//         'chat_id': '1',
//         'chat_type': 'group',
//         'message': 'Test message 2',
//         'type': 'text',
//         'firebase_key': 'test_fb_key_2',
//         'client_timestamp': DateTime.now().toIso8601String(),
//       },
//     ];
//
//     try {
//       final response = await apiService.batchSendMessages(testMessages);
//
//       assert(response['success'] == true, 'Response should be successful');
//       assert(response['data'] != null, 'Response should have data');
//       assert(response['data']['sent'] is List, 'Sent should be a list');
//       assert(response['data']['failed'] is List, 'Failed should be a list');
//
//       debugPrint('✅ API 1 Test Passed');
//       debugPrint('   Sent: ${response['data']['total_sent']}');
//       debugPrint('   Failed: ${response['data']['total_failed']}');
//     } catch (e) {
//       debugPrint('❌ API 1 Test Failed: $e');
//       rethrow;
//     }
//   }
//
//   /// Test API 2: Incremental Message Sync
//   Future<void> testMessageSync() async {
//     debugPrint('🧪 Testing API 2: Message Sync');
//
//     try {
//       final response = await apiService.syncMessages(
//         chatId: '1',
//         chatType: 'group',
//         since: DateTime.now().subtract(const Duration(days: 7)),
//         limit: 50,
//       );
//
//       assert(response['success'] == true, 'Response should be successful');
//       assert(response['data'] != null, 'Response should have data');
//       assert(response['data']['messages'] is List, 'Messages should be a list');
//       assert(response['data']['deleted_message_ids'] is List, 'Deleted IDs should be a list');
//       assert(response['data']['updated_messages'] is List, 'Updated messages should be a list');
//       assert(response['data']['synced_at'] != null, 'Should have synced_at timestamp');
//
//       debugPrint('✅ API 2 Test Passed');
//       debugPrint('   New messages: ${response['data']['messages'].length}');
//       debugPrint('   Deleted: ${response['data']['deleted_message_ids'].length}');
//       debugPrint('   Updated: ${response['data']['updated_messages'].length}');
//     } catch (e) {
//       debugPrint('❌ API 2 Test Failed: $e');
//       rethrow;
//     }
//   }
//
//   /// Test API 3: Incremental Chat List Sync
//   Future<void> testChatSync() async {
//     debugPrint('🧪 Testing API 3: Chat List Sync');
//
//     try {
//       final response = await apiService.syncChats(
//         since: DateTime.now().subtract(const Duration(days: 7)),
//         limit: 20,
//       );
//
//       assert(response['success'] == true, 'Response should be successful');
//       assert(response['data'] != null, 'Response should have data');
//       assert(response['data']['new_chats'] is List, 'New chats should be a list');
//       assert(response['data']['updated_chats'] is List, 'Updated chats should be a list');
//       assert(response['data']['deleted_chat_ids'] is List, 'Deleted IDs should be a list');
//       assert(response['data']['synced_at'] != null, 'Should have synced_at timestamp');
//
//       debugPrint('✅ API 3 Test Passed');
//       debugPrint('   New chats: ${response['data']['new_chats'].length}');
//       debugPrint('   Updated chats: ${response['data']['updated_chats'].length}');
//       debugPrint('   Deleted: ${response['data']['deleted_chat_ids'].length}');
//     } catch (e) {
//       debugPrint('❌ API 3 Test Failed: $e');
//       rethrow;
//     }
//   }
//
//   /// Test API 4: Batch Mark as Read
//   Future<void> testBatchRead() async {
//     debugPrint('🧪 Testing API 4: Batch Mark as Read');
//
//     try {
//       final response = await apiService.batchMarkAsRead(
//         messageIds: [1, 2, 3],
//         chatId: '1',
//         chatType: 'group',
//       );
//
//       assert(response['success'] == true, 'Response should be successful');
//       assert(response['data'] != null, 'Response should have data');
//       assert(response['data']['marked_count'] != null, 'Should have marked_count');
//       assert(response['data']['failed_ids'] is List, 'Failed IDs should be a list');
//       assert(response['data']['marked_at'] != null, 'Should have marked_at timestamp');
//
//       debugPrint('✅ API 4 Test Passed');
//       debugPrint('   Marked: ${response['data']['marked_count']}');
//       debugPrint('   Failed: ${response['data']['failed_ids'].length}');
//     } catch (e) {
//       debugPrint('❌ API 4 Test Failed: $e');
//       rethrow;
//     }
//   }
//
//   /// Test API 5: Queue Status
//   Future<void> testQueueStatus() async {
//     debugPrint('🧪 Testing API 5: Queue Status');
//
//     try {
//       final response = await apiService.getQueueStatus();
//
//       assert(response['success'] == true, 'Response should be successful');
//       assert(response['data'] != null, 'Response should have data');
//       assert(response['data']['pending_messages'] != null, 'Should have pending_messages');
//       assert(response['data']['pending_uploads'] != null, 'Should have pending_uploads');
//       assert(response['data']['failed_messages'] != null, 'Should have failed_messages');
//       assert(response['data']['is_queue_full'] != null, 'Should have is_queue_full');
//
//       debugPrint('✅ API 5 Test Passed');
//       debugPrint('   Pending: ${response['data']['pending_messages']}');
//       debugPrint('   Failed: ${response['data']['failed_messages']}');
//       debugPrint('   Queue full: ${response['data']['is_queue_full']}');
//     } catch (e) {
//       debugPrint('❌ API 5 Test Failed: $e');
//       rethrow;
//     }
//   }
//
//   /// Test API 6: App Version Check
//   Future<void> testVersionCheck() async {
//     debugPrint('🧪 Testing API 6: App Version Check');
//
//     try {
//       final response = await apiService.checkAppVersion(
//         currentVersion: '1.0.23',
//       );
//
//       assert(response['success'] == true, 'Response should be successful');
//       assert(response['data'] != null, 'Response should have data');
//       assert(response['data']['update_available'] != null, 'Should have update_available');
//       assert(response['data']['latest_version'] != null, 'Should have latest_version');
//       assert(response['data']['update_type'] != null, 'Should have update_type');
//
//       debugPrint('✅ API 6 Test Passed');
//       debugPrint('   Update available: ${response['data']['update_available']}');
//       debugPrint('   Latest version: ${response['data']['latest_version']}');
//       debugPrint('   Update type: ${response['data']['update_type']}');
//     } catch (e) {
//       debugPrint('❌ API 6 Test Failed: $e');
//       rethrow;
//     }
//   }
//
//   /// Run all tests
//   Future<void> runAllTests() async {
//     debugPrint('═══════════════════════════════════════');
//     debugPrint('🚀 Starting Offline API Integration Tests');
//     debugPrint('═══════════════════════════════════════');
//
//     int passed = 0;
//     int failed = 0;
//
//     // Test 1: Batch Send
//     try {
//       await testBatchSend();
//       passed++;
//     } catch (e) {
//       failed++;
//     }
//
//     // Test 2: Message Sync
//     try {
//       await testMessageSync();
//       passed++;
//     } catch (e) {
//       failed++;
//     }
//
//     // Test 3: Chat Sync
//     try {
//       await testChatSync();
//       passed++;
//     } catch (e) {
//       failed++;
//     }
//
//     // Test 4: Batch Read
//     try {
//       await testBatchRead();
//       passed++;
//     } catch (e) {
//       failed++;
//     }
//
//     // Test 5: Queue Status
//     try {
//       await testQueueStatus();
//       passed++;
//     } catch (e) {
//       failed++;
//     }
//
//     // Test 6: Version Check (public API)
//     try {
//       await testVersionCheck();
//       passed++;
//     } catch (e) {
//       failed++;
//     }
//
//     debugPrint('═══════════════════════════════════════');
//     debugPrint('📊 Test Results:');
//     debugPrint('   ✅ Passed: $passed/6');
//     debugPrint('   ❌ Failed: $failed/6');
//     debugPrint('═══════════════════════════════════════');
//   }
// }
//
// /// Test offline queue functionality
// Future<void> testOfflineQueue() async {
//   debugPrint('🧪 Testing Offline Queue Service');
//
//   final dio = Dio();
//   final apiService = ApiService(dio);
//   await OfflineQueueService.initialize(apiService);
//
//   // Test queue message
//   final testMessage = PendingMessage(
//     tempId: 'queue_test_1',
//     chatId: '1',
//     chatType: 'group',
//     message: 'Test queued message',
//     type: 'text',
//     firebaseKey: 'queue_fb_key_1',
//     clientTimestamp: DateTime.now(),
//   );
//
//   await OfflineQueueService.queueMessage(testMessage);
//
//   final stats = OfflineQueueService.getQueueStats();
//   debugPrint('✅ Queue Test Passed');
//   debugPrint('   Total in queue: ${stats['total']}');
//   debugPrint('   Pending: ${stats['pending']}');
//
//   await OfflineQueueService.removeFromQueue('queue_test_1');
// }
//
// /// Test sync service functionality
// Future<void> testSyncService() async {
//   debugPrint('🧪 Testing Sync Service');
//
//   final dio = Dio();
//   final apiService = ApiService(dio);
//   final syncService = SyncService(apiService);
//
//   // Test message sync
//   try {
//     final messages = await syncService.syncChatMessages(
//       chatId: '1',
//       chatType: 'group',
//     );
//
//     debugPrint('✅ Sync Service Test Passed');
//     debugPrint('   Messages synced: ${messages.length}');
//   } catch (e) {
//     debugPrint('❌ Sync Service Test Failed: $e');
//   }
// }

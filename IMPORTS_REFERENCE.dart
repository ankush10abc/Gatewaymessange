// /// QUICK IMPORT REFERENCE
// /// Copy these imports based on where you're integrating

// // ============================================================================
// // FOR EXISTING chat_screen.dart (Minimal Integration)
// // ============================================================================
// import '../../core/services/message_sync_service.dart';

// // Add to _ChatScreenState:
// final MessageSyncService _syncService = MessageSyncService();

// // ============================================================================
// // FOR main.dart (Required)
// // ============================================================================
// import 'package:hive_flutter/hive_flutter.dart';
// import 'core/models/chat_hive_model.dart';
// import 'core/models/message_hive_model.dart'; // NEW

// // In main():
// await Hive.initFlutter();
// Hive.registerAdapter(ChatHiveModelAdapter());
// Hive.registerAdapter(MessageHiveModelAdapter()); // NEW

// // ============================================================================
// // FOR Router Configuration (Testing New Screen)
// // ============================================================================
// import 'package:check_setting/features/chat/optimized_chat_screen.dart';

// // Add route:
// GoRoute(
//   path: '/optimized-chat',
//   name: 'optimized-chat',
//   builder: (context, state) {
//     final chatId = state.uri.queryParameters['chatId']!;
//     final chatType = state.uri.queryParameters['chatType']!;
//     final chatName = state.uri.queryParameters['chatName']!;

//     return OptimizedChatScreen(
//       chatId: chatId,
//       chatType: chatType,
//       chatName: chatName,
//     );
//   },
// ),

// // ============================================================================
// // FOR Using Riverpod Provider Directly
// // ============================================================================
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import '../../shared/providers/chat_messages_provider.dart';

// // In widget build:
// final messagesState = ref.watch(chatMessagesProvider(chatId));

// // Access data:
// final messages = messagesState.messages;
// final isLoading = messagesState.isLoading;
// final hasMore = messagesState.hasMoreMessages;

// // ============================================================================
// // COMPLETE IMPORT LIST (All New Files)
// // ============================================================================

// // Data Layer
// import 'package:check_setting/core/data/hive_message_data_source.dart';

// // Models
// import 'package:check_setting/core/models/message_hive_model.dart';

// // Services
// import 'package:check_setting/core/services/message_sync_service.dart';

// // Providers
// import 'package:check_setting/shared/providers/chat_messages_provider.dart';

// // Screens
// import 'package:check_setting/features/chat/optimized_chat_screen.dart';

// // ============================================================================
// // DEPENDENCIES (Already in pubspec.yaml ✅)
// // ============================================================================
// /*
// dependencies:
//   hive: ^2.2.3
//   hive_flutter: ^1.1.0
//   flutter_riverpod: ^2.4.9

// dev_dependencies:
//   build_runner: ^2.4.7
//   hive_generator: ^2.0.1
// */

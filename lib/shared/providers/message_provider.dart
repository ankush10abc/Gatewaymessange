// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:dio/dio.dart';
// import '../../core/models/message_model.dart';
// import '../../core/services/firebase_service.dart';
// import '../../core/services/api_service_simple.dart';
// import '../../core/storage/storage_service.dart';
//
// class MessageState {
//   final List<Message> messages;
//   final bool isLoading;
//   final String? error;
//   final Map<String, dynamic>? chatUser;
//
//   MessageState({
//     this.messages = const [],
//     this.isLoading = false,
//     this.error,
//     this.chatUser,
//   });
//
//   MessageState copyWith({
//     List<Message>? messages,
//     bool? isLoading,
//     String? error,
//     Map<String, dynamic>? chatUser,
//   }) {
//     return MessageState(
//       messages: messages ?? this.messages,
//       isLoading: isLoading ?? this.isLoading,
//       error: error ?? this.error,
//       chatUser: chatUser ?? this.chatUser,
//     );
//   }
// }
//
// class MessageNotifier extends StateNotifier<MessageState> {
//   late final ApiService _apiService;
//   final StorageService _storage = StorageService();
//
//   MessageNotifier() : super(MessageState()) {
//     final dio = Dio();
//     _apiService = ApiService(dio);
//   }
//
//   Future<void> loadMessages(String chatId, String chatType) async {
//     state = state.copyWith(isLoading: true);
//
//     try {
//       // Set auth token
//       final token = await _storage.getToken();
//       if (token != null) {
//         _apiService.setAuthToken(token);
//       }
//
//       final int id = int.parse(chatId);
//
//       if (chatType == 'group') {
//         final response = await _apiService.getGroupMessages(id, 1, 50);
//         debugPrint("Abkush banawade $response");
//         debugPrint("Abkush banawade group ${response.data}");
//         final List<Message> messages = [];
//
//         if (response.data != null) {
//           for (var msgData in response.data) {
//
//             Message m = Message.fromJson(msgData.toJson());
//             debugPrint("Abkush banawade group name ${m.toJson()}");
//             debugPrint("Abkush banawade group name ${m.senderName}");
//             messages.add(Message.fromJson(msgData.toJson()));
//           }
//         }
//
//         state = state.copyWith(messages: messages, isLoading: false);
//       } else {
//         final response = await _apiService.getConversation(id, 1, 50);
//         final List<Message> messages = [];
//
//         if (response.data != null) {
//           for (var msgData in response.data) {
//             debugPrint("Abkush banawade msgData ${msgData.toJson()}");
//             messages.add(Message.fromJson(msgData.toJson()));
//           }
//         }
//
//         state = state.copyWith(
//           messages: messages,
//           isLoading: false,
//           chatUser: response.user != null ? Map<String, dynamic>.from(response.user) : null,
//         );
//       }
//     } catch (e) {
//       state = state.copyWith(
//         error: e.toString(),
//         isLoading: false,
//       );
//     }
//   }
//
//   Future<void> sendMessage(Message message) async {
//     try {
//       await FirebaseService.sendMessage(message);
//     } catch (e) {
//       state = state.copyWith(error: e.toString());
//     }
//   }
//
//   Future<void> updateMessageStatus(
//     String chatId,
//     String messageId,
//     String userId,
//     String status,
//   ) async {
//     try {
//       await FirebaseService.updateMessageStatus(chatId, messageId, userId, status);
//     } catch (e) {
//       state = state.copyWith(error: e.toString());
//     }
//   }
//
//   void addMessage(Message message) {
//     final updatedMessages = [...state.messages, message];
//     state = state.copyWith(messages: updatedMessages);
//   }
//
//   void updateMessage(Message updatedMessage) {
//     final updatedMessages = state.messages.map((msg) {
//       if (msg.id == updatedMessage.id) {
//         return updatedMessage;
//       }
//       return msg;
//     }).toList();
//     state = state.copyWith(messages: updatedMessages);
//   }
//
//   void removeMessage(String messageId) {
//     final updatedMessages = state.messages.where((msg) => msg.id != messageId).toList();
//     state = state.copyWith(messages: updatedMessages);
//   }
//
//   void clearError() {
//     state = state.copyWith();
//   }
//
//   Future<void> markMessageAsRead(String messageId) async {
//     try {
//       final id = int.parse(messageId);
//       await _apiService.markMessageAsRead(id);
//       debugPrint('Message $messageId marked as read');
//     } catch (e) {
//       debugPrint('Failed to mark message as read: $e');
//     }
//   }
// }
//
// final messageProvider = StateNotifierProvider<MessageNotifier, MessageState>((ref) {
//   return MessageNotifier();
// });

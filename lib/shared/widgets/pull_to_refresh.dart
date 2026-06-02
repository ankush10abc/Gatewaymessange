import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PullToRefreshWrapper extends ConsumerWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const PullToRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: const Color(0xFF1dab61),
      backgroundColor: Colors.white,
      child: child,
    );
  }
}

class ChatListRefreshProvider extends StateNotifier<bool> {
  ChatListRefreshProvider() : super(false);

  Future<void> refreshChats() async {
    state = true;

    // Simulate refresh delay
    await Future.delayed(const Duration(seconds: 1));

    // Refresh chat data
    // This would typically reload data from Firebase

    state = false;
  }
}

final chatListRefreshProvider = StateNotifierProvider<ChatListRefreshProvider, bool>((ref) {
  return ChatListRefreshProvider();
});

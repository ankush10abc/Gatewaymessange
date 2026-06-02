import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_model.dart';
import '../../core/services/firebase_service.dart';

class SearchState {
  final List<User> users;
  final bool isLoading;
  final String? error;

  SearchState({
    this.users = const [],
    this.isLoading = false,
    this.error,
  });

  SearchState copyWith({
    List<User>? users,
    bool? isLoading,
    String? error,
  }) {
    return SearchState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(SearchState());

  void searchUsers(String query, String currentUserId) {
    state = state.copyWith(isLoading: true);
    
    FirebaseService.searchUsers(query, currentUserId).listen(
      (users) {
        state = state.copyWith(
          users: users,
          isLoading: false,
        );
      },
      onError: (error) {
        state = state.copyWith(
          error: error.toString(),
          isLoading: false,
        );
      },
    );
  }

  void clearSearch() {
    state = SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier();
});
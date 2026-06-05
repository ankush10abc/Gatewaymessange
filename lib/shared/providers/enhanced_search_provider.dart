import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/user_model.dart';
import '../../core/services/api_service_simple.dart';

class EnhancedSearchState {
  final List<User> searchResults;
  final List<User> teachers;
  final List<User> parents;
  final List<User> chatPermissions;
  final bool isLoading;
  final String? error;
  final String query;

  EnhancedSearchState({
    this.searchResults = const [],
    this.teachers = const [],
    this.parents = const [],
    this.chatPermissions = const [],
    this.isLoading = false,
    this.error,
    this.query = '',
  });

  EnhancedSearchState copyWith({
    List<User>? searchResults,
    List<User>? teachers,
    List<User>? parents,
    List<User>? chatPermissions,
    bool? isLoading,
    String? error,
    String? query,
  }) {
    return EnhancedSearchState(
      searchResults: searchResults ?? this.searchResults,
      teachers: teachers ?? this.teachers,
      parents: parents ?? this.parents,
      chatPermissions: chatPermissions ?? this.chatPermissions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      query: query ?? this.query,
    );
  }
}

class EnhancedSearchNotifier extends StateNotifier<EnhancedSearchState> {
  late final ApiService _apiService;

  EnhancedSearchNotifier() : super(EnhancedSearchState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
    // Defer heavy initialization to prevent main thread blocking
    Future.microtask(() => loadInitialData());
  }

  Future<void> loadInitialData() async {
    state = state.copyWith(isLoading: true);

    try {
      // Load chat permissions (users current user can chat with)
      final permissions = await _apiService.getChatPermissions();

      state = state.copyWith(
        chatPermissions: permissions,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(
        searchResults: [],
        query: query,
      );
      return;
    }

    state = state.copyWith(isLoading: true, query: query);

    try {
      final results = await _apiService.searchUsers(query.trim());

      state = state.copyWith(
        searchResults: results,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<void> loadTeachers() async {
    if (state.teachers.isNotEmpty) return; // Already loaded

    state = state.copyWith(isLoading: true);

    try {
      final teachers = await _apiService.getTeachers();

      state = state.copyWith(
        teachers: teachers,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<void> loadParents() async {
    if (state.parents.isNotEmpty) return; // Already loaded

    state = state.copyWith(isLoading: true);

    try {
      final parents = await _apiService.getParents();

      state = state.copyWith(
        parents: parents,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  void clearSearch() {
    state = state.copyWith(
      searchResults: [],
      query: '',
    );
  }

  void clearError() {
    state = state.copyWith();
  }

  // Get filtered results based on user role and permissions
  List<User> getFilteredResults() {
    if (state.query.isEmpty) {
      return state.chatPermissions;
    }
    return state.searchResults;
  }

  // Check if user can chat with another user
  bool canChatWith(User user) {
    return state.chatPermissions.any((u) => u.id == user.id);
  }
}

final enhancedSearchProvider = StateNotifierProvider<EnhancedSearchNotifier, EnhancedSearchState>((ref) {
  return EnhancedSearchNotifier();
});

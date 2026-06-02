import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../constants/enums.dart';
import 'api_service_simple.dart';

class SearchService {
  static late final ApiService _apiService;

  static void initialize() {
    final dio = Dio();
    _apiService = ApiService(dio);
  }

  static Future<List<User>> searchUsers(String query, UserRole role) async {
    try {
      return await _apiService.searchUsers(query);
    } catch (e) {
      return [];
    }
  }

  static Future<List<String>> getSearchHistory() async {
    return [];
  }

  static Future<void> saveSearchQuery(String query) async {
  }

  static Future<void> clearSearchHistory() async {
  }
}

class SearchHistoryService {
  static const String _historyKey = 'search_history';
  static const int _maxHistoryItems = 10;

  static Future<List<String>> getHistory() async {
    try {
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<void> addToHistory(String query) async {
    if (query.trim().isEmpty) return;

    try {
      final history = await getHistory();

      history.remove(query);
      history.insert(0, query);

      if (history.length > _maxHistoryItems) {
        history.removeRange(_maxHistoryItems, history.length);
      }
    } catch (e) {
    }
  }

  static Future<void> removeFromHistory(String query) async {
    try {
      final history = await getHistory();
      history.remove(query);
    } catch (e) {
    }
  }

  static Future<void> clearHistory() async {
    try {
    } catch (e) {
    }
  }
}

class RoleBasedSearchProvider extends StateNotifier<SearchState> {
  RoleBasedSearchProvider() : super(SearchState.initial());

  Future<void> searchUsers(String query, UserRole role) async {
    if (query.trim().isEmpty) {
      state = SearchState.initial();
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final users = await SearchService.searchUsers(query, role);
      await SearchHistoryService.addToHistory(query);

      state = state.copyWith(
        isLoading: false,
        users: users,
        query: query,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadSearchHistory() async {
    final history = await SearchHistoryService.getHistory();
    state = state.copyWith(searchHistory: history);
  }

  Future<void> clearHistory() async {
    await SearchHistoryService.clearHistory();
    state = state.copyWith(searchHistory: []);
  }

  void clearSearch() {
    state = SearchState.initial();
  }
}

class SearchState {
  final List<User> users;
  final List<String> searchHistory;
  final bool isLoading;
  final String? error;
  final String query;

  SearchState({
    required this.users,
    required this.searchHistory,
    required this.isLoading,
    this.error,
    required this.query,
  });

  factory SearchState.initial() {
    return SearchState(
      users: [],
      searchHistory: [],
      isLoading: false,
      query: '',
    );
  }

  SearchState copyWith({
    List<User>? users,
    List<String>? searchHistory,
    bool? isLoading,
    String? error,
    String? query,
  }) {
    return SearchState(
      users: users ?? this.users,
      searchHistory: searchHistory ?? this.searchHistory,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      query: query ?? this.query,
    );
  }
}

final roleBasedSearchProvider =
    StateNotifierProvider<RoleBasedSearchProvider, SearchState>((ref) {
  return RoleBasedSearchProvider();
});

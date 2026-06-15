import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/providers/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/storage/storage_service.dart';
import '../../shared/widgets/profile_image_widget.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ApiService _apiService;
  final StorageService _storage = StorageService();
  List<User> _searchResults = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  String _currentQuery = '';
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    final dio = Dio();
    _apiService = ApiService(dio);
    _initializeAuth();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Scroll listener for pagination
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMoreData && !_isLoading) {
        _loadMoreUsers();
      }
    }
  }

  Future<void> _initializeAuth() async {
    final token = await _storage.getToken();
    if (token != null) {
      _apiService.setAuthToken(token);
      _searchUsers('');
    }
  }

  Future<void> _searchUsers(String query) async {
    // Reset pagination when new search
    _currentPage = 1;
    _hasMoreData = true;
    
    setState(() {
      _isLoading = true;
      _currentQuery = query;
      _searchResults = []; // Clear previous results
    });

    try {
      final users = await _apiService.searchUsers(query, page: _currentPage);
      setState(() {
        _searchResults = users;
        _isLoading = false;
        _hasMoreData = users.isNotEmpty && users.length >= 20;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
        _hasMoreData = false;
      });
      debugPrint("Ankush catch $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e', maxLines: 2,),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Load more users for pagination
  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      _currentPage++;
      final moreUsers = await _apiService.searchUsers(_currentQuery, page: _currentPage);
      
      setState(() {
        _searchResults.addAll(moreUsers);
        _isLoadingMore = false;
        _hasMoreData = moreUsers.length >= 20; // Assume 20 items per page
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
        _currentPage--; // Revert page increment on error
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load more: $e', maxLines: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user!;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search users...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (query) {
            _searchUsers(query);
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchResults.isEmpty && _currentQuery.isEmpty
              ? _buildEmptyState()
              : _searchResults.isEmpty
                  ? _buildNoResults()
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _searchResults.length) {
                          // Loading indicator at bottom
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final user = _searchResults[index];
                        return _buildUserTile(user, currentUser);
                      },
                    ),
    );
  }

  Widget _buildUserTile(User user, User currentUser) {
    return ListTile(
      leading: ProfileImageWidget(
        imageUrl: user.profilePicture,
        userName: user.name,
        role: user.role,
      ),
      title: Text(user.name),
      subtitle: Text(_getRoleDisplayName(user.role)),
      trailing:  Icon(Icons.chat, color: AppTheme.whatsAppGreen),
      onTap: () {
        // Navigate to chat with user
        if (user.actual_role == 'parent' || user.actual_role.toLowerCase() == 'admin' || user.actual_role.toLowerCase() == 'teacher') {
          context.push('/chat/${user.id}?type=user&name=${Uri.encodeComponent(user.name)}');
        }else{
          context.push('/chat/${user.id}?type=group&name=${Uri.encodeComponent(user.name)}');
        }

      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Search for users',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'teacher':
        return 'Teacher';
      case 'parent':
        return 'Parent';
      default:
        return role.toUpperCase();
    }
  }
}
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/permissions/notification_permission_helper.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/widgets/chat_tile.dart';
import '../../shared/widgets/warning_slider.dart';
import '../../shared/widgets/pull_to_refresh.dart';
import '../../core/models/chat_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/deep_link_service.dart';
import '../../core/utils/internet_checker.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  void initDeepLinks() {

    final appLinks = AppLinks();

    appLinks.uriLinkStream.listen((uri) {
      debugPrint('Deep link received: $uri');
      if (uri.path.contains('/send/app')) {
        final message = uri.queryParameters['message'];
        if (message != null) {
          DeepLinkService.setPendingMessage(message);
        }
      }
    });

    // Handle initial link when app is opened from deep link
    appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('Initial deep link: $uri');
        if (uri.path.contains('/send/app')) {
          final message = uri.queryParameters['message'];
          if (message != null) {
            DeepLinkService.setPendingMessage(message);
          }
        }
      }
    });
  }

   initUI() async {
     await InternetChecker.checkAndRedirect(context);
     initDeepLinks();
    _checkPendingDeepLink();
     try {
       NotificationPermissionHelper.request();
     } catch (e) {
       print(e);
     }
  }
  @override
  void initState() {
    super.initState();
    // Load chat list when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_)  {
      ApiService.setContext(context);
      ref.read(chatProvider.notifier).loadChatList();
      initUI();
    });
    
    // Listen for foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Received foreground notification: ${message.data}');
      _refreshChatList();
    });
    
    // Listen for notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification opened app: ${message.data}');
      _refreshChatList();
    });
  }

  void _checkPendingDeepLink() {
    debugPrint('Deep link received:_checkPendingDeepLink ${DeepLinkService.getPendingMessage()}');
    debugPrint('Deep link received:_checkPendingDeepLink ${DeepLinkService.hasPendingMessage()}');
    if (DeepLinkService.hasPendingMessage()) {
      final message = DeepLinkService.getPendingMessage();
      // DeepLinkService.setPendingMessage(null);
      debugPrint('Deep link received:_checkPendingDeepLink $message');
      if (message != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          context.push('/chat-selection?message=${Uri.encodeComponent(message)}');
        });
      }
    }
  }

  void _refreshChatList() {
    if (mounted) {
      ref.read(chatProvider.notifier).loadChatList();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final chatState = ref.watch(chatProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  // Implement search functionality
                },
              )
            : const Text('Gateway Messenger'),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () async {
                await context.push('/search');
                _refreshChatList();
              },
            ),
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'profile':
                  await context.push('/profile');
                  _refreshChatList();
                  break;
                case 'logout':
                  ref.read(authProvider.notifier).logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: authState.user?.profilePicture != null
                          ? NetworkImage(authState.user!.profilePicture.toString().contains('https://gatewayreports.in/storage') ? authState.user!.profilePicture.toString(): 'https://gatewayreports.in/storage/${authState.user!.profilePicture}')
                          : null,
                      child: authState.user?.profilePicture == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Text('Profile'),
                  ],
                ),
              ),
            if(kDebugMode)
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          // image: DecorationImage(
          //   image: AssetImage('assets/images/chat_bg.jpg'),
          //   fit: BoxFit.cover,
          //   opacity: 0.1,
          // ),
        ),
        child: Column(
          children: [
            // Warning Slider
            WarningSlider(),

            // Chat List
            Expanded(
              child: _buildChatsList(chatState),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showNewChatDialog(context, authState.user!.role);
        },
        child: const Icon(Icons.chat),
      ),
    );
  }

  Widget _buildChatsList(dynamic chatState) {
    if (chatState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chatState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 80,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 24),
            Text(
              chatState.error.toString().contains('host lookup') ?  'Connection Issue' : 'Error Loading chats',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                chatState.error.toString().contains('host lookup') ?  'Unable to load chats. Please check your internet connection and try again.' : chatState.error.toString(),
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(chatProvider.notifier).loadChatList();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    if (chatState.chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No chats yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation by tapping the + button',
              style: TextStyle(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // Separate regular chats
    final List<Chat> allChats = List<Chat>.from(chatState.chats);

    return PullToRefreshWrapper(
      onRefresh: () async {
        await ref.read(chatProvider.notifier).loadChatList();
      },
      child: ListView(
        children: [
          // Regular Chats
          ...allChats.map((chat) => ChatTile(
            chat: chat,
            currentUserId: ref.read(authProvider).user!.id,
            onTap: () async {
              final chatName = chat.getDisplayName(ref.read(authProvider).user!.id, []);
              if (chat.type == 'group') {
                 await context.push('/chat/${chat.id}?type=group&name=${Uri.encodeComponent(chatName)}');
              } else {
                await context.push('/chat/${chat.id}?type=user&name=${Uri.encodeComponent(chatName)}');
              }
              await Future.delayed(const Duration(milliseconds: 300));
              _refreshChatList();
            },
          )),
        ],
      ),
    );
  }

  void _showNewChatDialog(BuildContext context, String userRole) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Start New Chat',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('New Chat'),
              subtitle: const Text('Start a conversation'),
              onTap: () async {
                Navigator.pop(context);
                await context.push('/search');
                _refreshChatList();
              },
            ),
          ],
        ),
      ),
    );
  }
}

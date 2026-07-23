import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/models/chat_hive_model.dart';
import '../../core/permissions/notification_permission_helper.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/chat_list_manager.dart';
import '../../core/services/chat_list_update_service.dart';
import '../../core/services/deep_link_service.dart';
import '../../core/services/firebase_message_listener.dart';
import '../../core/utils/app_debouncer.dart';
import '../../core/utils/internet_checker.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/optimized_chat_provider.dart';
import '../../shared/widgets/cached_profile_image.dart';
import '../../shared/widgets/pull_to_refresh.dart';
import '../../shared/widgets/update_dialog.dart';
import '../../shared/widgets/warning_slider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  // Throttle resume refresh — avoid duplicate syncs if user switches apps quickly
  DateTime? _lastResumeSync;
  // Cache queue total so _buildQueueStatusBanner doesn’t call getQueueStats() on every build
  int _queueTotal = 0;

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
    _checkForUpdate();
    try {
      NotificationPermissionHelper.request();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = ref.read(authProvider).user;
      if (user != null) {
        ChatListUpdateService.initialize(ref, userId: user.id);
        await ChatListManager.init(user.id);
        await ref
            .read(optimizedChatProvider.notifier)
            .initialize(userId: user.id);
        // Real-time listeners in ChatListSyncService handle all updates — no polling needed.
      }
      // FirebaseMessageListener handles both onMessage and onMessageOpenedApp
      FirebaseMessageListener.init(ref);
      initUI();
    });
  }


  void _checkPendingDeepLink() {
    debugPrint(
        'Deep link received:_checkPendingDeepLink ${DeepLinkService.getPendingMessage()}');
    debugPrint(
        'Deep link received:_checkPendingDeepLink ${DeepLinkService.hasPendingMessage()}');
    if (DeepLinkService.hasPendingMessage()) {
      final message = DeepLinkService.getPendingMessage();
      debugPrint('Deep link received:_checkPendingDeepLink $message');
      if (message != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            context.push(
                '/chat-selection?message=${Uri.encodeComponent(message)}');
          }
        });
      }
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final apiService = ApiService(Dio());
      final response =
          await apiService.checkAppVersion(currentVersion: currentVersion);

      if (response['success'] == true) {
        final data = response['data'];
        final updateAvailable = data['update_available'] ?? false;

        if (updateAvailable && mounted) {
          showDialog(
            context: context,
            barrierDismissible: data['can_skip'] ?? true,
            builder: (context) => UpdateDialog(
              currentVersion: data['current_version'] ?? currentVersion,
              latestVersion: data['latest_version'] ?? currentVersion,
              updateType: data['update_type'] ?? 'optional',
              releaseNotes: data['release_notes'],
              downloadUrl: data['download_url'],
              directApkUrl: data['direct_apk_url'],
              apkSizeMb: data['apk_size_mb']?.toDouble(),
              canSkip: data['can_skip'] ?? true,
              forceUpdateMessage: data['force_update_message'],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Update check failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  /// Called when app comes back to foreground from recent apps or background.
  /// Refreshes chat list so unread counts and new messages are reflected immediately.
  void _onAppResumed() {
    final now = DateTime.now();
    // Throttle: skip if resumed within last 30 seconds to avoid redundant API calls
    if (_lastResumeSync != null &&
        now.difference(_lastResumeSync!).inSeconds < 30) {
      debugPrint('⏭️ [HomeScreen] Resume sync throttled');
      return;
    }
    _lastResumeSync = now;
    debugPrint('🔄 [HomeScreen] App resumed — refreshing chat list');
    ref.read(optimizedChatProvider.notifier).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final chatState = ref.watch(optimizedChatProvider);
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
              onPressed: () => AppDebouncer.run(() async {
                await context.push('/search');
                ref.read(optimizedChatProvider.notifier).refresh();
              }, tag: 'home_search'),
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
            onSelected: (value) => AppDebouncer.run(() async {
              switch (value) {
                case 'profile':
                  await context.push('/profile');
                  ref.read(optimizedChatProvider.notifier).refresh();
                  break;
                case 'logout':
                  ref.read(authProvider.notifier).logout();
                  break;
              }
            }, tag: 'home_menu_$value'),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: authState.user?.profilePicture != null
                          ? NetworkImage(authState.user!.profilePicture
                                  .toString()
                                  .contains('https://gatewayreports.in/storage')
                              ? authState.user!.profilePicture.toString()
                              : 'https://gatewayreports.in/storage/${authState.user!.profilePicture}')
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
              if (kDebugMode)
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
        decoration: const BoxDecoration(),
        child: Column(
          children: [
            _buildQueueStatusBanner(),
            const WarningSlider(),
            Expanded(
              child: _buildChatsList(chatState),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AppDebouncer.run(
          () => _showNewChatDialog(context, authState.user!.role),
          tag: 'home_fab',
        ),
        child: const Icon(Icons.chat),
      ),
    );
  }

  Widget _buildQueueStatusBanner() {
    // Uses cached _queueTotal — updated on resume/init, not on every build
    if (_queueTotal == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          const Icon(Icons.cloud_upload, size: 20, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_queueTotal message${_queueTotal > 1 ? 's' : ''} syncing in background',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(
            width: 16,
            height: 16,
            child: Icon(Icons.sync, size: 16, color: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList(OptimizedChatState chatState) {
    if (chatState.isInitialLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading chats...',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (chatState.error != null && chatState.chats.isEmpty) {
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
              chatState.error.toString().contains('host lookup')
                  ? 'Connection Issue'
                  : 'Error Loading chats',
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
                chatState.error.toString().contains('host lookup')
                    ? 'Unable to load chats. Please check your internet connection and try again.'
                    : chatState.error.toString(),
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => AppDebouncer.run(
                () => ref.read(optimizedChatProvider.notifier).refresh(),
                tag: 'home_retry',
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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

    return PullToRefreshWrapper(
      onRefresh: () async {
        await ref.read(optimizedChatProvider.notifier).refresh();
      },
      child: ListView.builder(
        itemCount: chatState.chats.length,
        // AlwaysScrollableScrollPhysics ensures pull-to-refresh works
        // even when the list is short and doesn't fill the screen
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) {
          final chat = chatState.chats[index];
          return _buildChatTile(chat);
        },
      ),
    );
  }

  Widget _buildChatTile(ChatHiveModel chat) {
    return chat.id == '' || chat.name == 'Unknown'
        ? const SizedBox.shrink()
        : ListTile(
            key: ValueKey(chat.getUniqueKey()),
            onTap: () => AppDebouncer.run(() async {
              // Mark as read immediately — clears badge before entering chat
              // so the home screen badge is 0 when user returns.
              // Do NOT call refresh() after returning: it races with markAsRead
              // and can restore a stale unread count from the API response.
              if (chat.unreadCount > 0) {
                ref
                    .read(optimizedChatProvider.notifier)
                    .markAsRead(chat.id, chat.type, chat.attendanceGroup ?? false);
              }

              debugPrint("Groupchat.attendanceGroup ${chat.type.toString()}");
              debugPrint("Groupchat.attendanceGroup ${chat.attendanceGroup}");

              if (chat.type == 'group') {
                await context.push(
                    '/chat/${chat.id}?attendance_group=${chat.attendanceGroup}&type=group&name=${Uri.encodeComponent(chat.name)}');
              } else {
                await context.push(
                    '/chat/${chat.id}?attendance_group=${chat.attendanceGroup}&type=user&name=${Uri.encodeComponent(chat.name)}');
              }
              // No refresh() here — markAsRead already zeroed the badge in Hive
              // and Firebase listeners keep the list live in real time.
            }, tag: 'chat_tile_${chat.id}'),
            onLongPress: () => _showChatOptions(chat),
            leading: Stack(
              children: [
                CachedProfileImage(
                  imagePath: chat.imagePath,
                  size: 50,
                  fallbackText: chat.name,
                ),
                if (chat.isPinned)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.push_pin,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    chat.name,
                    style: TextStyle(
                      fontWeight: chat.unreadCount > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (chat.lastMessageTime != null)
                  Text(
                    _formatTime(chat.lastMessageTime ?? DateTime.now()),
                    style: TextStyle(
                      fontSize: 12,
                      color: chat.unreadCount > 0
                          ? Theme.of(context).primaryColor
                          : Colors.grey[600],
                      fontWeight: chat.unreadCount > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: Text(
                    // chat.lastMessage ?? 'Tap to start chatting',
                    'Tap to start chatting',
                    style: TextStyle(
                      color:
                          chat.unreadCount > 0 ? Colors.grey : Colors.grey[600],
                      fontWeight: chat.unreadCount > 0
                          ? FontWeight.w500
                          : FontWeight.normal,
                      fontStyle: chat.lastMessage == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: chat.unreadCount > 0
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      // Show 9+ when count exceeds 9, otherwise show actual count
                      chat.unreadCount > 9
                          ? '9+'
                          : chat.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return DateFormat('hh:mm a').format(timestamp);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(timestamp);
    } else {
      return DateFormat('dd/MM/yy').format(timestamp);
    }
  }

  void _showChatOptions(chat) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                  chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(chat.isPinned ? 'Unpin Chat' : 'Pin Chat'),
              onTap: () => AppDebouncer.run(() {
                ref.read(optimizedChatProvider.notifier).togglePin(
                      chat.id,
                      chat.type,
                      !chat.isPinned,
                      attendanceGroup: chat.attendanceGroup == true,
                    );
                Navigator.pop(context);
              }, tag: 'pin_${chat.id}'),
            ),
            if (chat.unreadCount > 0)
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('Mark as Read'),
                onTap: () => AppDebouncer.run(() {
                  ref
                      .read(optimizedChatProvider.notifier)
                      .markAsRead(chat.id, chat.type, chat.attendanceGroup);
                  Navigator.pop(context);
                }, tag: 'mark_read_${chat.id}'),
              ),
          ],
        ),
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
              onTap: () => AppDebouncer.run(() async {
                Navigator.pop(context);
                await context.push('/search');
                ref.read(optimizedChatProvider.notifier).refresh();
              }, tag: 'new_chat_search'),
            ),
          ],
        ),
      ),
    );
  }
}

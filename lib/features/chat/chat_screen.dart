import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../core/models/chat_hive_model.dart';
import '../../core/models/message_model.dart';
import '../../core/services/active_chat_tracker.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/chat_list_update_service.dart';
import '../../core/services/chat_metadata_service.dart';
import '../../core/services/firebase_realtime_service.dart';
import '../../core/utils/chat_utils.dart';
import '../../core/services/image_cache_service.dart';
import '../../core/services/media_compression_service.dart';
import '../../core/services/message_sync_service.dart';
import '../../core/services/whatsapp_text_parser.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/internet_checker.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/optimized_chat_provider.dart';
import '../../shared/widgets/document_preview_screen.dart';
import '../../shared/widgets/enhanced_message_input.dart';
import '../../shared/widgets/forward_message_dialog.dart';
import '../../shared/widgets/image_preview_screen.dart';
import '../../shared/widgets/multi_image_preview_screen.dart';
import '../../shared/widgets/video_player_screen.dart';
import '../../shared/widgets/video_preview_screen.dart';
import '../../shared/widgets/video_thumbnail.dart';
import 'mark_attendance_screen.dart';
import 'user_detail_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatType;
  final String chatName;
  final String? initialMessage;
  final bool? attendance_group;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatType,
    required this.chatName,
    this.initialMessage,
    this.attendance_group,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  // final ScrollController _scrollController = ScrollController();
  final _scrollController = AutoScrollController();
  int pageCount = 1;
  bool isFirstTime =
      true; // Shows 3-sec loader for attendance group on first open
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final ApiService _apiService;
  final StorageService _storage = StorageService();

  // NEW: Message sync service for instant loading
  final MessageSyncService _syncService = MessageSyncService();
  final ChatMetadataService _metadataService = ChatMetadataService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  // Guards against duplicate background image downloads per message
  final Set<String> _cachingImages = {};
  StreamSubscription<List<Message>>? _cacheSubscription;

  // Real-time state
  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;

  List<Message> _messages = [];
  Map<String, dynamic>? _user;
  bool? _isAttendanceGroup; // Track attendance group status
  Map<String, bool> _typingUsers = {};
  final Map<String, dynamic> _onlineUsers = {};
  Message? _replyToMessage;
  bool _isAtBottom = true;
  Timer? _typingTimer;
  String? _currentUserId;
  final bool _isLoadingPermissions =
      false; // Start false — input renders immediately, no layout jump
  String? _highlightedMessageId;
  bool _initialMessageSent = false;
  // Track recently sent message IDs to prevent duplicates from Firebase listener
  bool _isSearching = false;
  String _searchQuery = '';
  List<Message> _searchResults = [];
  int _currentSearchIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingOldMessages = false;
  bool _hasMoreMessages = true;
  static const int _messagesPerPage = 11;
  final Set<String> _markedAsReadMessages = {}; // Track already marked messages
  int _markAsReadApiCallCount = 0; // Limit API calls to 2
  int _loadedBatchCount = 0; // Tracks total batches of 25 messages loaded in UI
  bool _isOnline =
      true; // Cached internet status, updated on connectivity checks
  // tempId → upload progress (0.0–1.0); removed when upload completes/fails
  final Map<String, double> _uploadProgress = {};
  // Guards against showing attendance messages before fresh API data is ready
  final bool _attendanceApiSyncDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Track this chat as active
    ActiveChatTracker.setActiveChat(widget.chatId);

    final dio = Dio();
    _apiService = ApiService(dio);
    _initializeFirebase();
    _initializeAuth();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ApiService.setContext(context);
      _isAttendanceGroup =
          ChatHiveModel.parseAttendanceGroup(widget.attendance_group);
      getUserRole();

      // For attendance groups: isFirstTime stays true until fresh API data
      // arrives (_syncAttendanceGroupFromApi sets it false). This prevents
      // stale cached messages from flashing before fresh data is ready.
      // For non-attendance: no loader needed.
      if (_isAttendanceGroup != true) {
        isFirstTime = false;
      }

      _initializeChat();
      _handleInitialMessage();
    });
  }

  @override
  void didChangeDependencies() {
    // _refreshAfterAttendance is only called explicitly after marking attendance
    // (from the Mark Attendance button result handler). Calling it here on every
    // didChangeDependencies causes new→old→new flicker because it fires on first
    // navigation push as well, racing with _syncAttendanceGroupFromApi.
    super.didChangeDependencies();
  }

  var userRole;
  String? _userRoleCache; // Cache user role to avoid repeated lookups

  void getUserRole() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    debugPrint("AnkushuserRole two ${user.toJson()}");
    // Ankush revert
    userRole = user.actual_role.toLowerCase();
    if (userRole == 'no user') {
      userRole = user.role.toLowerCase();
    }
    _userRoleCache = userRole; // Cache the role
  }

  void initUI() {
    _initializeFirebase();
    _initializeAuth();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ApiService.setContext(context);
      _initializeChat();
      _handleInitialMessage();
    });
  }

  void _handleInitialMessage() {
    debugPrint(
        "Ankush Banawade Messahes debugError Five ${widget.initialMessage}");
    if (widget.initialMessage != null &&
        widget.initialMessage!.isNotEmpty &&
        !_initialMessageSent) {
      _initialMessageSent = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _currentUserId != null) {
          final decodedMessage = Uri.decodeFull(widget.initialMessage!);
          _sendMessage(text: decodedMessage);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Clear active chat tracking
    ActiveChatTracker.clearActiveChat();

    // Stop background sync
    _syncService.stopBackgroundSync(
      widget.chatId,
      widget.chatType,
      currentUserId: _currentUserId,
      userRole: _userRoleCache,
      isAttendanceGroup: _isAttendanceGroup,
    );

    // Cancel message sync service listeners
    _syncService.cancelFirebaseListener(
      widget.chatId,
      widget.chatType,
      currentUserId: _currentUserId,
      userRole: _userRoleCache,
      isAttendanceGroup: _isAttendanceGroup,
    );

    _cacheSubscription?.cancel();
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    _presenceSubscription?.cancel();
    _typingTimer?.cancel();
    // Clear upload progress map to prevent stale callbacks after dispose
    _uploadProgress.clear();
    _scrollController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _focusNode.dispose();

    if (_currentUserId != null) {
      try {
        FirebaseRealtimeService.setUserOffline(_currentUserId!);
        FirebaseRealtimeService.setTyping(
            widget.chatType, widget.chatId, _currentUserId!, false,
            attendanceGroup: _isAttendanceGroup);
      } catch (e) {
        // Ignore Firebase errors during disposal
      }
    }
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_currentUserId == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // await FirebaseRealtimeService.initialize();
        FirebaseRealtimeService.setUserOnline(_currentUserId!);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        FirebaseRealtimeService.setUserOffline(_currentUserId!);
        FirebaseRealtimeService.setTyping(
            widget.chatType, widget.chatId, _currentUserId!, false,
            attendanceGroup: _isAttendanceGroup);
        break;
      default:
        break;
    }
  }

  Future<void> _initializeAuth() async {
    final token = await _storage.getToken();
    if (token != null) {
      _apiService.setAuthToken(token);
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Firebase already initialized
    }
  }

  /// Writes 'delivered' status to Firebase for all messages from other users
  /// that are still in 'sent' state. Called on chat open so the sender sees
  /// double grey tick even if the receiver was offline when the message arrived.
  void _markPendingMessagesAsDelivered() {
    if (_currentUserId == null || widget.chatType == 'group') return;
    // Resolve the other user's ID: prefer _user['id'] if loaded, else widget.chatId
    final resolvedOtherUserId = _user?['id']?.toString().isNotEmpty == true
        ? _user!['id'].toString()
        : widget.chatId;
    final firebaseChatId = ChatUtils.generateChatId(
      widget.chatId,
      chatType: widget.chatType,
      currentUserId: _currentUserId,
      otherUserId: resolvedOtherUserId,
      attendanceGroup: _isAttendanceGroup,
    );
    // Run in background — never blocks UI
    unawaited(() async {
      try {
        debugPrint("_markPendingMessagesAsDelivered $firebaseChatId");
        final snapshot = await FirebaseRealtimeService.database
            .ref('chats/$firebaseChatId/messages')
            .get();

        if (!snapshot.exists || snapshot.value == null) return;
        final messagesMap = snapshot.value as Map?;
        if (messagesMap == null) return;
        for (final entry in messagesMap.entries) {
          // debugPrint('✅ [Delivered] Marked pending messages as delivered in ${entry}');
          final msgData = entry.value;
          if (msgData is! Map) continue;
          debugPrint('✅ [Delivered] Marked pending messages as delivered in ${msgData}');
          final senderId = msgData['senderId']?.toString() ??
              msgData['sender_id']?.toString() ?? '';
          // Only process messages from other users

          if (senderId.isEmpty || senderId == _currentUserId) continue;
          final statusMap = msgData['status'];
          debugPrint('✅ [Delivered] Marked pending messages as delivered infff ${statusMap}');
          // Cast to Map<String, dynamic> so String key lookup works correctly.
          // Firebase returns Map<dynamic, dynamic> — direct lookup with a String key returns null.
          final statusStrMap = statusMap is Map
              ? Map<String, dynamic>.from(statusMap)
              : null;
          // Check both prefixed and raw key for backward compatibility
          final currentStatus = (statusStrMap?[statusKey(_currentUserId!)] ??
              statusStrMap?[_currentUserId])?.toString();
          debugPrint('✅ [Delivered] Marked pending messages as delivered intttt ${currentStatus}');
          // Only upgrade sent → delivered, never downgrade read → delivered
          if (currentStatus == null || currentStatus == 'sent') {
            unawaited(FirebaseRealtimeService.database
                .ref('chats/$firebaseChatId/messages/${entry.key}/status/${statusKey(_currentUserId!)}')
                .set('delivered'));
            if (msgData['msgId'] != null) {
              unawaited(FirebaseRealtimeService.database
                  .ref('chats/$firebaseChatId/messages/${msgData['msgId']}/status/${statusKey(_currentUserId!)}')
                  .set('delivered'));
            }
          }
        }
        debugPrint('✅ [Delivered] Marked pending messages as delivered in $firebaseChatId');
      } catch (e) {
        debugPrint('❌ [Delivered] Error marking delivered: $e');
      }
    }());
  }

  Future<void> _makeAsRead() async {
    final user = ref.read(authProvider).user;
    final hasInternet = await InternetChecker.hasInternet();
    if (hasInternet) {
      try {
        if (mounted) {
                FirebaseRealtimeService.markMessagesAsRead(
                    widget.chatType, widget.chatId, user!.id,
                    currentUserId: _currentUserId,
                    otherUserId: _firebaseOtherUserId,
                    attendanceGroup: widget.attendance_group ?? false,
                    groupMembers: widget.chatType == 'group' && _user != null
                        ? _user!['member_list']
                        : null);

                // Reset unread count again after Firebase marks messages read
                ref.read(optimizedChatProvider.notifier).markAsRead(
                      widget.chatId,
                      widget.chatType,
                      widget.attendance_group ?? false,
                    );
              }
      } catch (e) {
        print("Error $e");
      }
    }
    // Reset unread count again after Firebase marks messages read
    try {
      ref.read(optimizedChatProvider.notifier).markAsRead(
                widget.chatId,
                widget.chatType,
                widget.attendance_group ?? false,
              );
    } catch (e) {
      print("Error $e");
    }
  }

  Future<void> _initializeChat() async {
    debugPrint('📴 Offline - skipping Firebase presence update');
    final user = ref.read(authProvider).user;
    debugPrint('📴 Offline - skipping Firebase presence update$user');
    if (user == null) return;

    _currentUserId = user.id;
    await _initializeAuth();
    debugPrint('AnkushuserRole three $user');
    try {
      // Check internet before Firebase operations
      final hasInternet = await InternetChecker.hasInternet();
      // Cache connectivity state for synchronous use in build (video thumbnails)
      if (mounted) setState(() => _isOnline = hasInternet);
      debugPrint('AnkushuserRole five $hasInternet');
      try {
        if (hasInternet) {
          await _loadInitialMessages();
          await FirebaseRealtimeService.setUserOnline(user.id);
        } else {
          await _loadInitialMessages();
          debugPrint('📴 Offline - skipping Firebase presence update');
        }
      } catch (e) {
        print(e);
      }
      debugPrint('AnkushuserRole four $user');

      debugPrint(
          "🔥 _setupRealtimeListeners check: attendance_group=$_isAttendanceGroup");

      // Setup Firebase listeners ONLY if online and not attendance group
      if (hasInternet && _isAttendanceGroup != true) {
        debugPrint("✅ Setting up Firebase listeners for regular chat");
        _setupRealtimeListeners();
      } else if (!hasInternet) {
        debugPrint("📴 Offline - skipping Firebase listeners");
      } else {
        debugPrint("⏭️ Skipping Firebase listeners for attendance group");
      }

      // Start background sync ONLY if online
      if (hasInternet) {
        _syncService.startBackgroundSync(
          chatId: widget.chatId,
          chatType: widget.chatType,
          apiService: _apiService,
          currentUserId: _currentUserId,
          userRole: _userRoleCache,
          isAttendanceGroup: _isAttendanceGroup,
          otherUserId: _firebaseOtherUserId,
        );
      } else {
        debugPrint('📴 Offline - skipping background sync');
      }

      // Reset unread count via optimizedChatProvider so Hive + UI badge both update
      final attendanceFlag = _isAttendanceGroup == true;
      ref.read(optimizedChatProvider.notifier).markAsRead(
            widget.chatId,
            widget.chatType,
            attendanceFlag,
          );

      // Mark messages as read ONLY if online
      if (hasInternet) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            FirebaseRealtimeService.markMessagesAsRead(
                widget.chatType, widget.chatId, user.id,
                currentUserId: _currentUserId,
                otherUserId: _firebaseOtherUserId,
                attendanceGroup: _isAttendanceGroup,
                groupMembers: widget.chatType == 'group' && _user != null
                    ? _user!['member_list']
                    : null);

            // Reset unread count again after Firebase marks messages read
            ref.read(optimizedChatProvider.notifier).markAsRead(
                  widget.chatId,
                  widget.chatType,
                  attendanceFlag,
                );
          }
        });
      }
    } catch (e) {
      // if (mounted) {
      //   setState(() {
      //     _isLoadingOldMessages = false;
      //   });
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(content: Text('Failed to initialize chat: $e')),
      //   );
      // }
      // debugPrint('Error in _initializeChat: $e');
    }

    // Only scroll to bottom on initial load — not on every re-init
    if (_messages.isEmpty) {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  /// Called after attendance is marked — fetch page 1, show instantly, sync in background.
  Future<void> _refreshAfterAttendance() async {
    if (!mounted) return;
    final hasInternet = await InternetChecker.hasInternet();
    if (!hasInternet) return;

    pageCount = 1;

    try {
      final id = int.parse(widget.chatId);
      final response =
          await _apiService.getGroupMessages(id, 1, ApiService.messageCount);
      final freshMessages = response.data;
      if (freshMessages.isEmpty || !mounted) return;

      // Show in UI immediately — do NOT wait for Firebase/SQLite sync
      setState(() {
        _messages = freshMessages;
        _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });

      // Sync to Firebase + SQLite in background (non-blocking)
      unawaited(_syncService.syncOldMessagesToFirebaseAndDb(
        chatId: widget.chatId,
        chatType: widget.chatType,
        messages: freshMessages,
        currentUserId: _currentUserId,
        isAttendanceGroup: true,
      ));

      debugPrint(
          '✅ _refreshAfterAttendance: shown=${freshMessages.length} (sync in bg)');
    } catch (e) {
      debugPrint('❌ _refreshAfterAttendance error: $e');
    }
  }

  Future<void> _syncOldMessages() async {
    if (_isLoadingOldMessages) return;
    setState(() => _isLoadingOldMessages = true);

    try {
      final nextPage = pageCount + 1;

      if (_isAttendanceGroup == true) {
        final id = int.parse(widget.chatId);
        debugPrint('API Call: GET Group _syncOldMessages page=$nextPage');

        // Fetch from API
        final response = await _apiService.getGroupMessages(
            id, nextPage, ApiService.messageCount);
        final apiMessages = response.data;

        if (mounted) {
          setState(() {
            if (apiMessages.isNotEmpty) {
              // Dedup against current UI messages by all known id fields
              final existingIds = <String>{
                for (final m in _messages) ...[
                  if ((m.firebaseId ?? '').isNotEmpty) m.firebaseId!,
                  if ((m.msgId ?? '').isNotEmpty && m.msgId != '0') m.msgId!,
                  if (m.id.isNotEmpty && m.id != '0') m.id,
                ],
              };
              final deduped = apiMessages.where((m) {
                final fbId = m.firebaseId ?? '';
                final mId = m.msgId ?? '';
                return !existingIds.contains(fbId) &&
                    !(mId.isNotEmpty &&
                        mId != '0' &&
                        existingIds.contains(mId)) &&
                    !existingIds.contains(m.id);
              }).toList();
              _messages.addAll(deduped);
              _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            }
            pageCount = nextPage;
            _loadedBatchCount++;
            _isLoadingOldMessages = false;
          });

          // Sync to Firebase + SQLite fully in background — never blocks UI
          if (apiMessages.isNotEmpty) {
            unawaited(_syncService.syncOldMessagesToFirebaseAndDb(
              chatId: widget.chatId,
              chatType: widget.chatType,
              messages: apiMessages,
              currentUserId: _currentUserId,
              isAttendanceGroup: true,
            ));
          }

          debugPrint('✅ _syncOldMessages(attendance) page=$nextPage '
              'shown=${apiMessages.length} total=${_messages.length}');
        }
      } else {
        // Non-attendance: load from Firebase/cache
        final apiMessages = await _syncService.loadMoreMessages(
          chatId: widget.chatId,
          chatType: widget.chatType,
          apiService: _apiService,
          currentUserId: _currentUserId,
          userRole: _userRoleCache,
          isAttendanceGroup: _isAttendanceGroup,
          page: nextPage,
          limit: ApiService.messageCount,
        );

        // Save to local DB in background
        if (apiMessages.isNotEmpty) {
          unawaited(_syncService.addMessageToLocaldatabasefromApi(
            widget.chatId,
            widget.chatType,
            apiMessages,
          ));
        }

        if (mounted) {
          setState(() {
            final existingIds = <String>{
              for (final m in _messages) ...[
                if ((m.firebaseId ?? '').isNotEmpty) m.firebaseId!,
                if ((m.msgId ?? '').isNotEmpty) m.msgId!,
                if (m.id.isNotEmpty) m.id,
              ],
            };
            final deduped = apiMessages
                .where((m) =>
                    !existingIds.contains(m.firebaseId ?? '') &&
                    !existingIds.contains(m.msgId ?? '') &&
                    !existingIds.contains(m.id))
                .toList();
            _messages.addAll(deduped);
            _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            pageCount = nextPage;
            _loadedBatchCount++;
            _isLoadingOldMessages = false;
          });
          debugPrint(
              '✅ _syncOldMessages page=$nextPage loaded=${apiMessages.length}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingOldMessages = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Failed to load old messages: Check Internet Connection')),
        );
      }
    }
  }

  String? get _firebaseOtherUserId {
    if (widget.chatType == 'group') return '0';

    final userId = _user?['id']?.toString();
    if (userId != null && userId.isNotEmpty && userId != 'null') {
      return userId;
    }

    return widget.chatId;
  }

  void _hydrateChatMetadataFromRoute() {
    _isAttendanceGroup ??=
        ChatHiveModel.parseAttendanceGroup(widget.attendance_group);
    _user ??= {
      'id': widget.chatId,
      'name': widget.chatName,
      'attendance_group': _isAttendanceGroup,
      if (widget.chatType == 'group') 'member_list': <dynamic>[],
    };
  }

  Future<void> _loadCachedConversationMetadata() async {
    Map<String, dynamic>? cachedMetadata =
        await _syncService.getCachedChatMetadata(
      widget.chatId,
      widget.chatType,
      isAttendanceGroup: _isAttendanceGroup,
    );

    if (cachedMetadata == null &&
        widget.chatType == 'group' &&
        _isAttendanceGroup != true) {
      cachedMetadata = await _syncService.getCachedChatMetadata(
        widget.chatId,
        widget.chatType,
        isAttendanceGroup: true,
      );
    }

    if (cachedMetadata == null || !mounted) {
      debugPrint('⚠️ No cached metadata found for chat ${widget.chatId}');
      return;
    }

    // Apply metadata to local state WITHOUT setState — caller will batch
    // it with the messages setState to avoid a separate rebuild.
    _user = cachedMetadata;
    _isAttendanceGroup = ChatHiveModel.parseAttendanceGroup(
      cachedMetadata['attendance_group'] ?? _isAttendanceGroup,
    );

    debugPrint(
        '✅ Loaded cached metadata: name=${_user?['name']}, attendance=$_isAttendanceGroup');
  }

  void _setupCacheWatcher() {
    _cacheSubscription?.cancel();
    // Attendance groups use the API as authoritative source — the cache watcher
    // must not merge stale Hive data on top of fresh API results.
    // For attendance groups we skip the watcher entirely; _syncAttendanceGroupFromApi
    // always replaces _messages directly via setState.
    if (_isAttendanceGroup == true) return;

    // Skip the first emission — it always mirrors what _loadInitialMessages
    // already rendered via setState, so acting on it causes a duplicate rebuild.
    bool isFirstEmission = true;
    _cacheSubscription = _syncService
        .watchMessages(
      widget.chatId,
      widget.chatType,
      currentUserId: _currentUserId,
      userRole: _userRoleCache,
      isAttendanceGroup: _isAttendanceGroup,
    )
        .listen((cachedMessages) {
      // Skip first emission — already shown by _loadInitialMessages setState
      if (isFirstEmission) {
        isFirstEmission = false;
        return;
      }
      if (!mounted) return;
      // Skip if cache is empty and we already have messages — background
      // writes (e.g. status updates) should not clear the UI.
      if (cachedMessages.isEmpty && _messages.isNotEmpty) return;

      // Compute the merged list first WITHOUT touching setState.
      final merged = _messages.isEmpty
          ? cachedMessages
          : _mergeMessages(_messages, cachedMessages);

      // Skip rebuild entirely if the visible message set hasn't changed.
      // Compare by stable IDs so minor metadata changes don't cause re-renders.
      if (!_hasMessageListChanged(_messages, merged)) return;

      final wasAtBottom = _isAtBottom;
      setState(() {
        _messages = merged;
      });

      // Only auto-scroll if user was already at the bottom before the update
      if (wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }, onError: (error) {
      debugPrint('Message cache watch error: $error');
    });
  }

  /// Returns true only when the visible message set has actually changed.
  /// Prevents unnecessary rebuilds triggered by background cache writes
  /// (e.g. read-receipt updates, Firebase sync) that don't affect what the user sees.
  /// Only compares the first 50 messages (visible window) to avoid UI-thread blocking
  /// on large chat histories — this was the source of occasional app freezes.
  bool _hasMessageListChanged(List<Message> current, List<Message> next) {
    if (current.length != next.length) return true;
    // Cap comparison to visible window to keep this O(1) in practice
    final limit = current.length < 50 ? current.length : 50;
    for (var i = 0; i < limit; i++) {
      final a = current[i];
      final b = next[i];
      // Primary key: prefer firebaseId, then msgId, then id
      final aKey = a.firebaseId?.isNotEmpty == true
          ? a.firebaseId!
          : (a.msgId?.isNotEmpty == true ? a.msgId! : a.id);
      final bKey = b.firebaseId?.isNotEmpty == true
          ? b.firebaseId!
          : (b.msgId?.isNotEmpty == true ? b.msgId! : b.id);
      if (aKey != bKey) return true;
      // Detect status tick changes (sending → sent → delivered → read).
      // Compare the full status map — per-user keys like status['userId'] = 'read'
      // are what drive double/blue tick rendering.
      if (a.status.length != b.status.length) return true;
      for (final entry in b.status.entries) {
        if (a.status[entry.key] != entry.value) return true;
      }
      // Also detect when Firebase replaces a 'default'-keyed status with per-user keys
      // (e.g. {'default': 'sent'} → {'1': 'sent', '3': 'delivered'})
      if (a.status.containsKey('default') && !b.status.containsKey('default')) return true;
      // Detect text edits
      if (a.text != b.text) return true;
    }
    return false;
  }

  Future<void> _loadInitialMessages() async {
    try {
      // Step 1: Load metadata from route and cache FIRST
      _hydrateChatMetadataFromRoute();
      await _loadCachedConversationMetadata(); // Sets _isAttendanceGroup

      // Step 2: Setup cache watcher AFTER metadata is loaded
      _setupCacheWatcher();

      // Step 3: Load cached messages IMMEDIATELY (offline-first)
      final cachedMessages = await _syncService.getCachedMessages(
        widget.chatId,
        widget.chatType,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
      );

      // Pre-seed read-tracking set from SQLite so already-read messages are
      // never re-processed as unread after app restart/kill.
      final persistedReadIds = await _syncService.getReadMessageIds(
        widget.chatId,
        widget.chatType,
      );
      _markedAsReadMessages.addAll(persistedReadIds);

      // Step 4: Display cached messages instantly.
      // For attendance groups: skip showing stale cache — the isFirstTime
      // loader hides the list for 2 s while fresh API data loads.
      // This prevents the old→new→old flicker entirely.
      if (mounted && _isAttendanceGroup != true) {
        setState(() {
          _messages = cachedMessages;
          _loadedBatchCount = (cachedMessages.length / 25).ceil();
        });
      } else if (mounted) {
        // Still track batch count for pagination, but don’t render stale data
        _loadedBatchCount = (cachedMessages.length / 25).ceil();
      }

      debugPrint(
          '⚡ Chat opened with ${cachedMessages.length} cached messages (offline-first)');
      if (cachedMessages.isNotEmpty) {
        debugPrint('💬 First message: ${cachedMessages.first.text}');
      }

      // Step 5: Check internet - CRITICAL DECISION POINT
      final hasInternet = await InternetChecker.hasInternet();
      // Keep _isOnline in sync so video thumbnails reflect current state
      if (mounted) setState(() => _isOnline = hasInternet);

      if (!hasInternet) {
        debugPrint(
            '📴 OFFLINE MODE - Using cached data only (${cachedMessages.length} messages)');
        // Don't call any API or Firebase - stay completely offline
        return;
      }

      // Mark pending messages as delivered for private chats when chat opens.
      // This covers the case where the receiver was offline/background when
      // the message arrived — ensures sender sees double grey tick.
      if (hasInternet && widget.chatType != 'group') {
        _markPendingMessagesAsDelivered();
      }

      debugPrint('🌐 ONLINE MODE - Syncing with API and Firebase');

      // Step 6: Online sync in background (non-blocking)
      if (_isAttendanceGroup == true) {
        // For attendance groups: always replace with fresh API data.
        // Never append — the API page-1 response is the authoritative list.
        unawaited(_syncAttendanceGroupFromApi(
          append: false,
        ));
      } else {
        // Sync recent Firebase messages in background
        _warmRecentMessagesInBackground(
          shouldFallbackToApiMessages: cachedMessages.isEmpty,
        );
        // Load metadata from API (non-blocking)
        if (hasInternet) {
          unawaited(_loadConversationMetadataFromApi(
            shouldFallbackToApiMessages: false,
          ));
        }
      }
    } catch (e) {
      debugPrint('❌ Load initial messages error: $e');
    }
  }

  //
  void _warmRecentMessagesInBackground({
    required bool shouldFallbackToApiMessages,
  }) {
    unawaited(() async {
      // Check internet before syncing
      final hasInternet = await InternetChecker.hasInternet();
      if (!hasInternet) {
        debugPrint('📴 Skipping Firebase sync - offline');
        return;
      }

      final firebaseMessages = await _syncService.syncRecentFirebaseMessages(
        chatId: widget.chatId,
        chatType: widget.chatType,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
        otherUserId: _firebaseOtherUserId,
        limit: ApiService.messageCount,
      );

      if (!mounted ||
          !shouldFallbackToApiMessages ||
          firebaseMessages.isNotEmpty) {
        return;
      }
      if (hasInternet) {
        await _loadConversationMetadataFromApi(
          shouldFallbackToApiMessages: true,
        );
      }
    }());
  }

  Future<void> _syncAttendanceGroupFromApi({bool append = true}) async {
    if (widget.chatType != 'group') return;

    // Check internet before API call
    final hasInternet = await InternetChecker.hasInternet();
    if (!hasInternet) {
      debugPrint('📴 Skipping attendance group sync - offline');
      // Show cached messages when offline instead of keeping the loader forever
      if (mounted) setState(() => isFirstTime = false);
      return;
    }

    try {
      // Always load page 1 for initial sync (not pagination)
      final freshMessages = await _syncService.syncAttendanceGroupFromApi(
        chatId: widget.chatId,
        apiService: _apiService,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        page: 1, // Always fetch page 1 for initial/refresh load
        limit: ApiService.messageCount,
        append: append,
      );

      final cachedMetadata = await _syncService.getCachedChatMetadata(
        widget.chatId,
        widget.chatType,
        isAttendanceGroup: true,
      );

      if (!mounted) return;

      setState(() {
        if (cachedMetadata != null) _user = cachedMetadata;
        _isAttendanceGroup = true;
        // Dismiss loader once fresh API data arrives (success or empty)
        isFirstTime = false;

        if (freshMessages.isNotEmpty) {
          if (!append) {
            // Replace entirely — API page-1 is the authoritative fresh list.
            // This prevents old cached messages from being mixed with new ones.
            _messages = freshMessages
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          } else {
            // Paginating: append only genuinely new messages
            final existingIds = <String>{
              for (final m in _messages) ...[
                if ((m.firebaseId ?? '').isNotEmpty) m.firebaseId!,
                if ((m.msgId ?? '').isNotEmpty && m.msgId != '0') m.msgId!,
                if (m.id.isNotEmpty && m.id != '0') m.id,
              ],
            };
            final deduped = freshMessages.where((m) {
              final fbId = m.firebaseId ?? '';
              final mId = m.msgId ?? '';
              return !existingIds.contains(fbId) &&
                  !(mId.isNotEmpty &&
                      mId != '0' &&
                      existingIds.contains(mId)) &&
                  !existingIds.contains(m.id);
            }).toList();
            _messages.addAll(deduped);
            _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          }
        }
      });

      // Re-setup cache watcher only if it wasn’t already active
      if (_cacheSubscription == null) _setupCacheWatcher();
    } catch (e) {
      debugPrint('❌ Attendance group API sync failed: $e');
      // Ensure loader is dismissed even on error so the screen is not stuck
      if (mounted) setState(() => isFirstTime = false);
    }
  }

  Future<void> _loadConversationMetadataFromApi({
    bool shouldLoadAttendanceMessages = false,
    bool shouldFallbackToApiMessages = false,
  }) async {
    // Check internet before API call
    final hasInternet = await InternetChecker.hasInternet();
    if (!hasInternet) {
      debugPrint('📴 Skipping API metadata load - offline');
      return;
    }

    try {
      final id = int.parse(widget.chatId);
      final limit = shouldLoadAttendanceMessages || shouldFallbackToApiMessages
          ? ApiService.messageCount
          : 1;

      Map<String, dynamic>? userData;
      List<Message> messages = [];

      if (widget.chatType == 'group') {
        pageCount = _loadedBatchCount;
        debugPrint(
            'API Call: GET Group _loadConversationMetadataFromApi $pageCount');
        final response =
            await _apiService.getGroupMessages(id, pageCount, limit);
        userData = Map<String, dynamic>.from(response.user);
        messages = response.data;
      } else {
        final response = await _apiService.getConversation(id, 1, limit);
        userData = Map<String, dynamic>.from(response.user);
        messages = response.data;
      }

      if (!mounted) return;

      final isAttendance = ChatHiveModel.parseAttendanceGroup(
        userData['attendance_group'],
      );
      final previousAttendanceGroup = _isAttendanceGroup;
      userData['attendance_group'] = isAttendance;

      // Update metadata fields directly — no setState here to avoid a visible
      // rebuild that flickers the subtitle while messages are already shown.
      // Only setState when attendanceGroup type truly changed (rare path).
      _user = userData;
      _isAttendanceGroup = isAttendance;

      await _syncService.saveChatMetadataToCache(
        chatId: widget.chatId,
        chatType: widget.chatType,
        metadata: userData,
        isAttendanceGroup: _isAttendanceGroup,
      );

      if (previousAttendanceGroup != _isAttendanceGroup) {
        _setupCacheWatcher();
      }

      if (_isAttendanceGroup == true) {
        // Already synced from API via _syncAttendanceGroupFromApi — skip to avoid
        // a second API call that would append old data on top of fresh messages.
        return;
      }

      if ((shouldLoadAttendanceMessages || shouldFallbackToApiMessages) &&
          messages.isNotEmpty) {
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _syncService.saveMessagesToCache(
          chatId: widget.chatId,
          chatType: widget.chatType,
          messages: messages,
          currentUserId: _currentUserId,
          userRole: _userRoleCache,
          isAttendanceGroup: _isAttendanceGroup,
          append: true,
        );

        final cachedMessages = await _syncService.getCachedMessages(
          widget.chatId,
          widget.chatType,
          currentUserId: _currentUserId,
          userRole: _userRoleCache,
          isAttendanceGroup: _isAttendanceGroup,
        );

        if (mounted) {
          setState(() {
            _messages = cachedMessages;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Conversation metadata load failed: $e');
    }
  }

  void _setupRealtimeListeners() {
    if (_currentUserId == null) return;

    _messagesSubscription = _syncService.setupFirebaseListener(
        chatId: widget.chatId,
        chatType: widget.chatType,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
        otherUserId: _firebaseOtherUserId,
        onMessages: (realtimeMessages) {
          debugPrint(
              "🔥 Firebase messages received: ${realtimeMessages.length} messages");

          if (realtimeMessages.isEmpty || !mounted) return;

          // Filter out messages that were just sent by current user
          // to prevent duplicates from optimistic UI updates.
          // NOTE: Do NOT filter messages that have status updates (same firebaseId
          // but different status) — those are needed for double/blue tick rendering.
          final filteredMessages = realtimeMessages.where((msg) {
            // Always keep messages from other users (needed for unread + status)
            if (msg.senderId != _currentUserId) return true;

            debugPrint("Fiver duplicate message from Firebase ${msg.toJson()}");
            final firebaseId = msg.firebaseId ?? msg.id;

            // Check if this is a status update for an existing message
            // (same firebaseId or msgId but status map changed) — must NOT be filtered
            final existingMsg = _messages.firstWhere(
              (m) =>
                  (m.firebaseId ?? m.id) == firebaseId ||
                  (msg.msgId != null &&
                      msg.msgId!.isNotEmpty &&
                      msg.msgId != '0' &&
                      m.msgId == msg.msgId),
              orElse: () => msg,
            );
            // If status changed (deep compare), keep the message so tick updates
            if (existingMsg != msg) {
              final statusChanged = existingMsg.status.length != msg.status.length ||
                  msg.status.entries.any((e) => existingMsg.status[e.key] != e.value);
              if (statusChanged) return true;
            }

            // For own messages: skip only if it's a true duplicate (same content,
            // same status, sent within 10 seconds) — not a status update
            final isDuplicate = _messages.any((existing) {
              final existingFirebaseId = existing.firebaseId ?? existing.id;
              // Same firebaseId AND same status = true duplicate, skip it
              if (firebaseId == existingFirebaseId &&
                  existing.status.toString() == msg.status.toString()) {
                return true;
              }
              // Match by timestamp + sender (for messages sent in last 10 seconds)
              if (existing.senderId == msg.senderId &&
                  existing.text == msg.text &&
                  existing.timestamp.difference(msg.timestamp).abs().inSeconds <
                      10 &&
                  existing.firebaseId == null) {
                return true;
              }
              return false;
            });

            if (isDuplicate) {
              debugPrint(
                  '⏭️ Skipping duplicate message from Firebase: $firebaseId');
              return false;
            }

            return true;
          }).toList();

          if (filteredMessages.isEmpty) {
            debugPrint('🚫 [FIREBASE] All messages filtered out as duplicates');
            return;
          }

          final previousLength = _messages.length;
          debugPrint(
              '🟡 [FIREBASE] Before merge: ${_messages.length} messages, adding ${filteredMessages.length} new');

          setState(() {
            // Merge messages based on chat type
            if (_isAttendanceGroup == true) {
              _messages = filteredMessages;
              _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            } else {
              _messages = _mergeMessages(_messages, filteredMessages);
            }
          });

          debugPrint(
              '🟢 [FIREBASE] After merge: ${_messages.length} messages (was $previousLength)');
          // Handle new incoming messages - auto-mark as read if user is actively viewing this chat
          if (_messages.length > previousLength &&
              filteredMessages.isNotEmpty) {
            // Process all new incoming messages from other users
            for (final newMessage in filteredMessages) {
              if (newMessage.senderId != _currentUserId) {
                // Auto-mark as read immediately since user is actively viewing this chat
                // This prevents unread count from increasing while user is in the chat
                debugPrint("_autoMarkIncomingMessageAsRead $newMessage");
                _autoMarkIncomingMessageAsRead(newMessage);

                // Update chat list with the message but mark as already read
                ref.read(chatProvider.notifier).onMessageReceived(
                      widget.chatId,
                      widget.chatType,
                      newMessage,
                      true, // isRead = true because user is actively viewing
                    );
              }
            }
          }

          // Auto-scroll to bottom if user is at bottom
          if (_isAtBottom && _messages.length > previousLength) {
            Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
          }

          debugPrint('✅ UI updated with ${_messages.length} total messages');
        });

    _typingSubscription = FirebaseRealtimeService.getTypingUsers(
            widget.chatId, widget.chatType,
            currentUserId: _currentUserId,
            attendanceGroup: _isAttendanceGroup,
            otherUserId: _firebaseOtherUserId)
        .listen((typingData) {
      if (mounted) {
        final typingUsers = <String, bool>{};
        typingData.forEach((userId, data) {
          if (data is Map &&
              data['isTyping'] == true &&
              userId != _currentUserId) {
            typingUsers[userId] = true;
          }
        });

        setState(() {
          _typingUsers = typingUsers;
        });
      }
    }, onError: (error) {
      debugPrint('Typing stream error: $error');
    });

    _presenceSubscription = FirebaseDatabase.instance
        .ref('presence/${widget.chatId}')
        .onValue
        .listen((event) {
      if (mounted) {
        final value = event.snapshot.value;
        final presenceData =
            value is Map ? Map<String, dynamic>.from(value) : null;
        setState(() {
          _onlineUsers[widget.chatId] = presenceData;
        });
      }
    }, onError: (error) {
      debugPrint('Presence stream error: $error');
    });
  }

  bool _canSendMessage() {
    if (widget.chatType != 'group' || _user == null) return true;

    final user = ref.read(authProvider).user;
    if (user == null) return false;
    debugPrint("AnkushuserRole one ${user.toJson()}");
    // Ankush revert
    var userRole = user.actual_role.toLowerCase();
    if (userRole == 'no user') {
      userRole = user.role.toLowerCase();
    }
    final isLocked = _user!['is_locked'] == true;
    final messagePermission =
        _user!['message_permission']?.toString().toLowerCase();

    debugPrint(
        "AnkushuserRole _canSendMessage messagePermission $messagePermission isLocked $isLocked  userRole $userRole");
    if (isLocked) {
      return userRole == 'admin';
    }
    debugPrint("AnkushuserRole $userRole");
    switch (messagePermission) {
      case 'admin_only':
        return userRole == 'admin';
      case 'admin_teacher':
        return userRole == 'admin' || userRole == 'teacher';
      case 'admin_teacher_parent':
        return userRole == 'admin' ||
            userRole == 'teacher' ||
            userRole == 'parent';
      default:
        return true;
    }
  }

  bool _canSendAttachments() {
    if (widget.chatType != 'group' || _user == null) return true;
    debugPrint(
        "Ankush banawade Gallery chatType ${_user!['allow_attachments']}");
    return _user!['allow_attachments'] == true;
  }

  /// Status priority: read(2) > delivered(1) > sent(0) > sending(-1)
  static const _statusPriority = {'read': 2, 'delivered': 1, 'sent': 0, 'sending': -1};

  /// Merge two status maps, keeping the highest-priority value per user key.
  /// Prevents the cache watcher from downgrading a live Firebase status update
  /// (e.g. reverting blue tick → grey tick when stale SQLite data arrives).
  Map<String, String> _mergeStatus(
      Map<String, String> current, Map<String, String> incoming) {
    if (current.isEmpty) return incoming;
    if (incoming.isEmpty) return current;
    final merged = Map<String, String>.from(current);
    for (final entry in incoming.entries) {
      final key = entry.key;
      final incomingVal = entry.value;
      final currentVal = merged[key];
      if (currentVal == null) {
        merged[key] = incomingVal;
      } else {
        // Keep whichever status is higher priority — never downgrade
        final currentPriority = _statusPriority[currentVal] ?? 0;
        final incomingPriority = _statusPriority[incomingVal] ?? 0;
        if (incomingPriority > currentPriority) {
          merged[key] = incomingVal;
        }
      }
    }
    return merged;
  }

  List<Message> _mergeMessages(
      List<Message> apiMessages, List<Message> realtimeMessages) {
    // Primary map: keyed by firebaseId (push key) for Firebase messages,
    // or by msgId for API-only messages (no firebaseId).
    // This ensures Firebase status updates always merge into the correct message
    // even when the existing message was loaded from API without a firebaseId.
    final messageMap = <String, Message>{};

    // Build secondary index: msgId → map key, so Firebase messages can find
    // their API-loaded counterpart by server numeric ID.
    final msgIdToKey = <String, String>{};

    for (final message in apiMessages) {
      // Prefer firebaseId as key; fall back to msgId, then id
      final key = (message.firebaseId?.isNotEmpty == true)
          ? message.firebaseId!
          : (message.msgId?.isNotEmpty == true && message.msgId != '0')
              ? 'msgid_${message.msgId}'
              : (message.id.startsWith('temp_') ? message.id : 'api_${message.id}');
      messageMap[key] = message;
      // Index by msgId so incoming Firebase messages can find this entry
      if (message.msgId != null && message.msgId!.isNotEmpty && message.msgId != '0') {
        msgIdToKey[message.msgId!] = key;
      }
    }

    for (final message in realtimeMessages) {
      final firebaseId = message.firebaseId;
      if (firebaseId != null && firebaseId.isNotEmpty) {
        // Remove temp message if exists (optimistic UI replacement)
        final tempKey = messageMap.keys.firstWhere(
          (k) => k.startsWith('temp_') && messageMap[k]?.text == message.text,
          orElse: () => '',
        );
        if (tempKey.isNotEmpty) messageMap.remove(tempKey);

        // Try direct firebaseId match first
        String? existingKey;
        if (messageMap.containsKey(firebaseId)) {
          existingKey = firebaseId;
        } else if (message.msgId != null &&
            message.msgId!.isNotEmpty &&
            message.msgId != '0' &&
            msgIdToKey.containsKey(message.msgId)) {
          // Firebase message matches an API-loaded message by msgId —
          // this is the key fix: status updates now propagate to the sender's UI
          // even when the existing message was loaded from API without a firebaseId.
          existingKey = msgIdToKey[message.msgId];
        }

        if (existingKey != null) {
          final existing = messageMap[existingKey]!;
          final mergedStatus = _mergeStatus(existing.status, message.status);
          // Replace with Firebase version (has firebaseId) but keep merged status
          // and prefer the API id if it's a real server id
          final merged = message.copyWith(
            status: mergedStatus,
            // Keep the real server id from the API-loaded message if available
            id: (existing.id.isNotEmpty &&
                    !existing.id.startsWith('temp_') &&
                    existing.id != '0')
                ? existing.id
                : message.id,
          );
          // Re-key under firebaseId so future updates always find it
          messageMap.remove(existingKey);
          messageMap[firebaseId] = merged;
          // Update msgId index to point to new key
          if (message.msgId != null && message.msgId!.isNotEmpty) {
            msgIdToKey[message.msgId!] = firebaseId;
          }
        } else {
          messageMap[firebaseId] = message;
        }
      } else if (message.id.startsWith('temp_')) {
        messageMap[message.id] = message;
      }
    }

    // Build final deduplicated list
    final firebaseIdToItem = <String, Message>{};
    for (final item in messageMap.values) {
      final firebaseId = item.firebaseId;
      if (firebaseId != null && firebaseId.isNotEmpty) {
        if (item.id != '0' && !item.id.startsWith('temp_')) {
          firebaseIdToItem[firebaseId] = item;
        } else if (!firebaseIdToItem.containsKey(firebaseId)) {
          firebaseIdToItem[firebaseId] = item;
        }
      } else if (item.id.startsWith('temp_')) {
        firebaseIdToItem[item.id] = item;
      } else {
        // API-only messages with no firebaseId — keep under stable key
        final stableKey = (item.msgId?.isNotEmpty == true && item.msgId != '0')
            ? 'msgid_${item.msgId}'
            : 'api_${item.id}';
        firebaseIdToItem[stableKey] = item;
      }
    }

    final mergedList = firebaseIdToItem.values.toList();
    mergedList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return mergedList;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final isAtBottom = position.pixels <= 100;

    // Avoid setState just for scroll tracking — update flag directly to prevent rebuilds
    if (_isAtBottom != isAtBottom) {
      _isAtBottom = isAtBottom;
      // Only rebuild to show/hide the scroll-to-bottom FAB
      setState(() {});
    }

    // Load older messages when user scrolls to the top (reverse list: top = maxScrollExtent)
    final distanceFromTop = position.maxScrollExtent - position.pixels;
    if (distanceFromTop <= 200 &&
        !_isLoadingOldMessages &&
        position.maxScrollExtent > 0) {
      if (_isAttendanceGroup == true) {
        _syncOldMessages();
      } else if (_hasMoreMessages) {
        _loadMoreMessages();
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingOldMessages || !_hasMoreMessages || _messages.isEmpty) return;

    setState(() => _isLoadingOldMessages = true);

    try {
      final oldestMessage = _messages.last;

      // First try to load from Firebase and sync to cache
      final olderMessages = await _syncService.syncOlderFirebaseMessages(
        chatId: widget.chatId,
        chatType: widget.chatType,
        beforeTimestamp: oldestMessage.timestamp,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
        otherUserId: _firebaseOtherUserId,
        limit: _messagesPerPage,
      );

      if (mounted) {
        setState(() {
          debugPrint(
              "ERRORmsgData success olderMessages ${olderMessages.length}");
          if (olderMessages.length < _messagesPerPage) {
            _hasMoreMessages = false;
          }
          _messages.addAll(olderMessages);
          _isLoadingOldMessages = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingOldMessages = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Auto-marks incoming messages as read when user is actively viewing this chat.
  /// Called immediately when a new message arrives via Firebase listener.
  /// Prevents unread count from increasing for messages received while chat is open.
  void _autoMarkIncomingMessageAsRead(Message message) {
    if (_currentUserId == null) return;

    final firebaseId = message.firebaseId ?? message.id;
    final msgId = _isAttendanceGroup == true ? message.id : message.msgId;

    debugPrint('📖 Auto-marking incoming message as read: $firebaseId $msgId');

    // 1. Update Firebase status immediately
    if (firebaseId.isNotEmpty && !firebaseId.startsWith('temp_')) {
      FirebaseRealtimeService.updateMessageStatus(
        widget.chatType,
        widget.chatId,
        firebaseId,
        _currentUserId!,
        'read',
        currentUserId: _currentUserId,
        otherUserId: _firebaseOtherUserId,
        attendanceGroup: _isAttendanceGroup,
        groupMembers: widget.chatType == 'group' && _user != null
            ? _user!['member_list']
            : null,
      );

      // 2. Update message status in local cache
      _syncService.updateMessageInCache(
        widget.chatId,
        widget.chatType,
        firebaseId,
        {
          'status': {
            ...(message.status),
            _currentUserId!: 'read',
          }
        },
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
      );
    }

    // 3. Call API to mark message as read
    if (msgId != null && msgId.isNotEmpty && msgId != '0') {
      try {
        final messageId = int.parse(msgId);
        if (messageId > 0) {
          _apiService.markMessageAsRead(messageId);
          _markAsReadApiCallCount++;
          debugPrint('✅ API mark as read called for message: $messageId');
        }
      } catch (e) {
        debugPrint('❌ Error marking message as read via API: $e');
      }
    }

    // 4. Reset unread badge in chat list immediately — critical for admin users
    // so the home screen badge clears as soon as the message is viewed.
    ref.read(optimizedChatProvider.notifier).markAsRead(
          widget.chatId,
          widget.chatType,
          _isAttendanceGroup == true,
        );

    // 5. Add to local tracking set to prevent re-processing
    _markedAsReadMessages.add(firebaseId);
  }

  // Optimized: Mark message as read only once (used for messages already in list)
  void _markMessageAsRead(Message message) {
    final firebaseId = message.firebaseId ?? message.id;
    // Use cached _isAttendanceGroup flag
    final msgId = _isAttendanceGroup == true ? message.id : message.msgId;
    // Check both prefixed and raw key for backward compatibility
    final currentStatus = (message.status[statusKey(_currentUserId!)] ??
        message.status[_currentUserId])?.toString() ?? 'sent';

    // Update Firebase status
    if (firebaseId.isNotEmpty &&
        !firebaseId.startsWith('temp_') &&
        currentStatus != 'read') {
      FirebaseRealtimeService.updateMessageStatus(
          widget.chatType, widget.chatId, firebaseId, _currentUserId!, 'read',
          currentUserId: _currentUserId,
          otherUserId: _firebaseOtherUserId,
          attendanceGroup: _isAttendanceGroup,
          groupMembers: widget.chatType == 'group' && _user != null
              ? _user!['member_list']
              : null);

      // Update message status in local cache
      _syncService.updateMessageInCache(
        widget.chatId,
        widget.chatType,
        firebaseId,
        {
          'status': {
            ...(message.status),
            _currentUserId!: 'read',
          }
        },
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
      );
    }

    // Call API to mark message as read (limit to 2 calls)
    if (_markAsReadApiCallCount < 2 &&
        msgId != null &&
        msgId.isNotEmpty &&
        msgId != '0') {
      try {
        final messageId = int.parse(msgId);
        if (messageId > 0) {
          _apiService.markMessageAsRead(messageId);
          _markAsReadApiCallCount++;
        }
      } catch (e) {
        debugPrint('Error marking message as read: $e');
      }
    }
  }

  Future<void> _scrollToMessage(Message message) async {
    var index = -1;
    // Use cached _isAttendanceGroup flag
    if (_isAttendanceGroup == true) {
      index =
          _messages.indexWhere((m) => m.id == message.id || m.id == message.id);
    } else {
      index = _messages
          .indexWhere((m) => m.msgId == message.msgId || m.id == message.id);
    }

    if (index == -1) {
      debugPrint('Message not found in current list');
      return;
    }

    if (!_scrollController.hasClients) {
      debugPrint('ScrollController not attached');
      return;
    }

    setState(() {
      _highlightedMessageId = message.id;
      _isAtBottom = false;
    });

    try {
      await _scrollController.scrollToIndex(
        index,
        preferPosition: AutoScrollPosition.middle,
        duration: const Duration(milliseconds: 500),
      );

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _highlightedMessageId == message.id) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    } catch (e) {
      debugPrint('Error scrolling to message: $e');
    }
  }

  void _performSearch() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults.clear();
        _currentSearchIndex = 0;
        _highlightedMessageId = null;
      });
      return;
    }

    final results = _messages.where((msg) {
      return msg.text.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          msg.senderName != null &&
              msg.senderName!
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase());
    }).toList();

    setState(() {
      debugPrint("results $results");
      if (results.isEmpty) {
        // _currentSearchIndex = 0;
        _highlightedMessageId = null;
      }
    });
    if (mounted) {
      setState(() {
        _searchResults = results;
        _currentSearchIndex = 0;
        if (_searchResults.isNotEmpty) {
          _highlightedMessageId = _searchResults[0].id;
          Future.delayed(const Duration(milliseconds: 100), () {
            _scrollToMessage(_searchResults[0]);
          });
        }
      });
    }
  }

  void _navigateToNextSearchResult() {
    if (_searchResults.isEmpty) return;
    if (mounted) {
      setState(() {
        _currentSearchIndex = (_currentSearchIndex + 1) % _searchResults.length;
        _highlightedMessageId = _searchResults[_currentSearchIndex].id;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        // _scrollToMessage(_searchResults[_currentSearchIndex]);

        if (_highlightedMessageId != null &&
            _highlightedMessageId!.isNotEmpty) {
          debugPrint("_highlightedMessageId $_highlightedMessageId ");
          _jumpToMessage(_highlightedMessageId!);
        }
      });
    }
  }

  void _navigateToPreviousSearchResult() {
    if (_searchResults.isEmpty) return;
    if (mounted) {
      setState(() {
        _currentSearchIndex =
            (_currentSearchIndex - 1 + _searchResults.length) %
                _searchResults.length;
        _highlightedMessageId = _searchResults[_currentSearchIndex].id;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        // _scrollToMessage(_searchResults[_currentSearchIndex]);
        if (_highlightedMessageId != null &&
            _highlightedMessageId!.isNotEmpty) {
          debugPrint("_highlightedMessageId $_highlightedMessageId ");
          _jumpToMessage(_highlightedMessageId!);
        }
      });
    }
  }

  Future<void> _jumpToMessage(String messageId) async {
    debugPrint('Jump to message called with ID: $messageId');
    debugPrint('Available message IDs: ${_messages.map((m) => m.id).toList()}');

    Message? targetMessage;
    try {
      targetMessage = _messages.firstWhere(
        (m) => m.id == messageId || m.msgId == messageId,
      );
    } catch (e) {
      debugPrint('Message not found by id, trying msgId');
      try {
        targetMessage = _messages.firstWhere(
          (m) => m.msgId == messageId,
        );
      } catch (e) {
        debugPrint('Message not found in current list');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message not found in current view')),
          );
        }
        return;
      }
    }

    debugPrint(
        'Target message found: ${targetMessage.id}, msgId: ${targetMessage.msgId}');
    await _scrollToMessage(targetMessage);
  }

  Future<bool> _ensureInternetForSend() async {
    final hasInternet = await InternetChecker.hasInternet();
    if (!hasInternet && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Internet connection is required to send messages'),
        ),
      );
    }
    return hasInternet;
  }

  Future<void> _sendMessage({
    String? text,
    String type = 'text',
    String? fileUrl,
    String? fileName,
    int? fileSize,
  }) async {
    print("neewnwnwnwaaaa $text");
    if (_currentUserId == null) return;

    final messageText = text ?? fileName ?? '';
    if (messageText.trim().isEmpty && type == 'text') return;

    if (!await _ensureInternetForSend()) return;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final user = ref.read(authProvider).user!;

    // Extract reply message ID (use msgId or id, but skip temp IDs)
    String? replyToMessageId;
    if (_replyToMessage != null) {
      // Prefer msgId (server ID), fallback to id if it's not a temp ID
      if (_replyToMessage!.msgId != null &&
          _replyToMessage!.msgId!.isNotEmpty) {
        replyToMessageId = _replyToMessage!.msgId;
      } else if (_replyToMessage!.id.isNotEmpty &&
          !_replyToMessage!.id.startsWith('temp_')) {
        replyToMessageId = _replyToMessage!.id;
      } else {
        // Replying to a message that hasn't been sent yet - wait for it to send
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please wait for the previous message to send before replying'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    final message = Message(
      id: tempId,
      chatId: widget.chatId,
      senderId: user.id,
      senderName: user.name,
      text: messageText,
      type: type,
      timestamp: DateTime.now(),
      status: {'default': 'sending'},
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      replyToId: replyToMessageId,
      replyToMessage: _replyToMessage,
    );

    print("neewnwnwnwaaaa ${message.toJson()}");
    // Optimistic UI update - add message immediately
    if (mounted) {
      setState(() {
        _messages.insert(0, message);
        _replyToMessage = null;
        debugPrint(
            '🟢 [SEND] Step 1: Added temp message. Total messages: ${_messages.length}');
      });
    }

    // Cache message immediately with reply data
    // await _syncService.addMessageToCache(
    //   widget.chatId,
    //   widget.chatType,
    //   message,
    //   currentUserId: _currentUserId,
    //   userRole: _userRoleCache,
    //   isAttendanceGroup: _isAttendanceGroup,
    // );

    _messageController.clear();
    FirebaseRealtimeService.setTyping(
        widget.chatType, widget.chatId, _currentUserId!, false,
        attendanceGroup: _isAttendanceGroup);
    _scrollToBottom();

    try {
      final sentMessage = await _sendToAPI(message);

      // Replace temp message with real message in cache
      await _syncService.replaceMessageInCache(
        widget.chatId,
        widget.chatType,
        tempId,
        sentMessage,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
      );

      // Update UI: remove temp message and add real message (single setState)
      if (mounted) {
        setState(() {
          debugPrint(
              '🟡 [SEND] Step 2: Before merge. Messages count: ${_messages.length}');
          debugPrint(
              '🟡 [SEND] Temp ID: $tempId, Real ID: ${sentMessage.id}, Firebase ID: ${sentMessage.firebaseId}');

          _messages = _mergeMessages(
            _messages.where((item) => item.id != tempId).toList(),
            [sentMessage],
          );

          debugPrint(
              '🟢 [SEND] Step 2: After merge. Messages count: ${_messages.length}');
        });
      }

      ref.read(chatProvider.notifier).onMessageSent(
            widget.chatId,
            widget.chatType,
            sentMessage,
          );

      // Update chat list via service
      ChatListUpdateService.updateOnMessageSent(
        chatId: widget.chatId,
        chatType: widget.chatType,
        attendanceGroup: _isAttendanceGroup == true,
        lastMessage: messageText,
        senderId: _currentUserId,
        senderName: user.name,
      );
    } catch (e) {
      _updateMessageStatus(tempId, 'failed');

      // Update failed status in cache
      await _syncService.updateMessageInCache(
        widget.chatId,
        widget.chatType,
        tempId,
        {
          'status': {'default': 'failed'}
        },
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
      );
    }
  }

  Future<Message> _sendToAPI(Message message) async {
    try {
      // First send to Firebase
      debugPrint(
          "Ankush api/message/save - check otherId ${_firebaseOtherUserId ?? '0'}");
      debugPrint('Ankush api/message/save - check currentid $_currentUserId');
      String? firebaseKey;
      try {
        firebaseKey = await FirebaseRealtimeService.sendMessage(message,
            chatType: widget.chatType,
            currentUserId: _currentUserId,
            attendanceGroup: _isAttendanceGroup,
            otherUserId: _firebaseOtherUserId);
      } catch (e) {
        debugPrint('Ankush api/message/save - check  Error$e');
        print(e);
      }

      // Then send to API
      Message? msg;
      if (widget.chatType == 'group') {
        msg = await _apiService.sendMessage(
          message: message.text,
          groupId: widget.chatId,
          messageType: message.type,
          filePath: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          firebaseKey: firebaseKey,
          replyToMessageId: message.replyToMessage?.msgId,
          old_firebase_message_id: message.replyToMessage?.firebaseId,
        );
      } else {
        msg = await _apiService.sendMessage(
          message: message.text,
          receiverId: widget.chatId,
          messageType: message.type,
          filePath: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          firebaseKey: firebaseKey,
          replyToMessageId: message.replyToMessage?.msgId,
          old_firebase_message_id: message.replyToMessage?.firebaseId,
        );
      }

      // Update Firebase with API msgId
      await FirebaseRealtimeService.updateMessage(message,
          chatType: widget.chatType,
          currentUserId: _currentUserId,
          otherUserId: _firebaseOtherUserId,
          attendanceGroup: _isAttendanceGroup,
          chatIdServer: msg.id.toString(),
          key: firebaseKey);

      // Build per-user status map with prefixed keys to prevent Firebase array conversion
      final Map<String, String> sentStatus;
      if (widget.chatType == 'group') {
        sentStatus = _currentUserId != null
            ? {statusKey(_currentUserId!): 'sent'}
            : {'default': 'sent'};
      } else {
        final resolvedOther = (_firebaseOtherUserId != null &&
                _firebaseOtherUserId!.isNotEmpty &&
                _firebaseOtherUserId != '0')
            ? _firebaseOtherUserId!
            : widget.chatId;
        sentStatus = {
          if (_currentUserId != null) statusKey(_currentUserId!): 'sent',
          if (resolvedOther.isNotEmpty && resolvedOther != _currentUserId)
            statusKey(resolvedOther): 'sent',
        };
      }

      return msg.copyWith(
        chatId: widget.chatId,
        firebaseId: firebaseKey,
        status: sentStatus,
        replyToMessage: message.replyToMessage,
      );
    } catch (e) {
      debugPrint('Ankush /save $e ${message.toJson()}');
      rethrow;
    }
  }

  void _updateMessageStatus(String messageId, String status) {
    debugPrint('🔄 [STATUS] Updating message $messageId status to: $status');
    setState(() {
      _messages = _messages.map((msg) {
        if (msg.id == messageId) {
          return msg.copyWith(status: {'default': status});
        }
        return msg;
      }).toList();
      // debugPrint("Ankush Banawade Messahes debugError Five ${_messages.toList()}");
      // _messages.forEach((message) {
      // debugPrint("Ankush Banawade Messahes debugError Five ${message.toJson()}");
      // });
    });
  }

  Future<void> _handleFileSelection(File file, String messageType) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      if (!await _ensureInternetForSend()) return;
      // Add optimistic bubble immediately so user sees it uploading
      final user = ref.read(authProvider).user!;
      final previewMsg = Message(
        id: tempId,
        chatId: widget.chatId,
        senderId: user.id,
        senderName: user.name,
        text: file.path.split('/').last,
        type: messageType,
        timestamp: DateTime.now(),
        status: const {'default': 'sending'},
        fileName: file.path.split('/').last,
        fileSize: file.lengthSync(),
      );
      if (mounted)
        setState(() {
          _messages.insert(0, previewMsg);
          _uploadProgress[tempId] = 0.0;
        });
      final uploadResponse = await _apiService.uploadFile(
        file,
        messageType,
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress[tempId] = sent / total);
          }
        },
      );
      if (mounted) setState(() => _uploadProgress.remove(tempId));
      // Remove optimistic bubble — _sendMessage inserts the real one
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == tempId));
      await _sendMessage(
        type: messageType,
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send file')),
        );
      }
    }
  }

  Future<void> _handleImageSelection(File file) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      if (!await _ensureInternetForSend()) return;
      final user = ref.read(authProvider).user!;
      final previewMsg = Message(
        id: tempId,
        chatId: widget.chatId,
        senderId: user.id,
        senderName: user.name,
        text: '',
        type: 'image',
        timestamp: DateTime.now(),
        status: const {'default': 'sending'},
        fileName: file.path.split('/').last,
        fileSize: file.lengthSync(),
        // store local path in fileUrl so bubble shows local preview
        fileUrl: file.path,
      );
      if (mounted)
        setState(() {
          _messages.insert(0, previewMsg);
          _uploadProgress[tempId] = 0.0;
        });
      // Compress before upload — reduces send time significantly
      final compressed = await MediaCompressionService.compressImage(file);
      final uploadResponse = await _apiService.uploadFile(
        compressed,
        'image',
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress[tempId] = sent / total);
          }
        },
      );
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      await _sendMessage(
        type: 'image',
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send image')),
        );
      }
    }
  }

  void _showImagePreview(File imageFile) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImagePreviewScreen(
          imageFile: imageFile,
          onCancel: () => Navigator.of(context).pop(),
          onSend: (file) {
            Navigator.of(context).pop();
            _handleImageSelection(file);
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _showMultiImagePreview(List<File> imageFiles) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MultiImagePreviewScreen(
          imageFiles: imageFiles,
          onCancel: () => Navigator.of(context).pop(),
          onSend: (files) async {
            Navigator.of(context).pop();
            for (final file in files) {
              await _handleImageSelection(file);
            }
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _showVideoPreview(File videoFile) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VideoPreviewScreen(
          videoFile: videoFile,
          onCancel: () => Navigator.of(context).pop(),
          onSend: (file) {
            Navigator.of(context).pop();
            _handleVideoSelection(file);
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _showDocumentPreview(File documentFile) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            DocumentPreviewScreen(
          documentFile: documentFile,
          onCancel: () => Navigator.of(context).pop(),
          onSend: (file) {
            Navigator.of(context).pop();
            _handleDocumentSelection(file);
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _handleVideoSelection(File file) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      if (!await _ensureInternetForSend()) return;
      final user = ref.read(authProvider).user!;
      final previewMsg = Message(
        id: tempId,
        chatId: widget.chatId,
        senderId: user.id,
        senderName: user.name,
        text: '',
        type: 'video',
        timestamp: DateTime.now(),
        status: const {'default': 'sending'},
        fileName: file.path.split('/').last,
        fileSize: file.lengthSync(),
        fileUrl: file.path,
      );
      if (mounted)
        setState(() {
          _messages.insert(0, previewMsg);
          _uploadProgress[tempId] = 0.0;
        });
      // Compress before upload — reduces send time ~60-70%
      final compressed = await MediaCompressionService.compressVideo(file);
      final uploadResponse = await _apiService.uploadFile(
        compressed,
        'video',
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress[tempId] = sent / total);
          }
        },
      );
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      await _sendMessage(
        type: 'video',
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send video')),
        );
      }
    }
  }

  Future<void> _handleDocumentSelection(File file) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      if (!await _ensureInternetForSend()) return;
      final extension = file.path.split('.').last.toLowerCase();
      final messageType = extension == 'pdf' ? 'pdf' : 'doc';
      final user = ref.read(authProvider).user!;
      final previewMsg = Message(
        id: tempId,
        chatId: widget.chatId,
        senderId: user.id,
        senderName: user.name,
        text: file.path.split('/').last,
        type: messageType,
        timestamp: DateTime.now(),
        status: const {'default': 'sending'},
        fileName: file.path.split('/').last,
        fileSize: file.lengthSync(),
      );
      if (mounted)
        setState(() {
          _messages.insert(0, previewMsg);
          _uploadProgress[tempId] = 0.0;
        });
      final uploadResponse = await _apiService.uploadFile(
        file,
        messageType,
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress[tempId] = sent / total);
          }
        },
      );
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      await _sendMessage(
        type: messageType,
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
      if (mounted)
        setState(() {
          _uploadProgress.remove(tempId);
          _messages.removeWhere((m) => m.id == tempId);
        });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send document')),
        );
      }
    }
  }

  /// Returns true if the required media permission is granted for the current SDK.
  /// - API 34+ (Android 14+) : READ_MEDIA_IMAGES + READ_MEDIA_VIDEOS or partial READ_MEDIA_VISUAL_USER_SELECTED
  /// - API 33  (Android 13)  : READ_MEDIA_IMAGES + READ_MEDIA_VIDEOS
  /// - API 30-32 (Android 11-12): scoped storage — image_picker works without permission
  /// - API 29  (Android 10)  : scoped storage — image_picker works without permission
  /// - API <29 (Android 9-)  : READ_EXTERNAL_STORAGE
  Future<bool> _requestMediaPermission({bool forVideo = false}) async {
    if (!Platform.isAndroid) return true;

    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

    if (sdkInt >= 34) {
      // Android 14+ (API 34, 35, 36...)
      // Request both granular permissions; partial (user-selected) is also acceptable.
      final images = await Permission.photos.request();
      final videos = forVideo ? await Permission.videos.request() : images;

      // Full access granted
      if (images.isGranted && videos.isGranted) return true;

      // Partial / limited access — image_picker can still work with user-selected media
      if (images.isLimited || videos.isLimited) return true;

      if (images.isPermanentlyDenied || videos.isPermanentlyDenied) {
        if (mounted) _showPermissionSettingsDialog('Photos & Videos');
        return false;
      }
      return false;
    } else if (sdkInt == 33) {
      // Android 13 (API 33)
      final images = await Permission.photos.request();
      final videos = forVideo ? await Permission.videos.request() : images;
      if (images.isGranted && videos.isGranted) return true;
      if (images.isPermanentlyDenied || videos.isPermanentlyDenied) {
        if (mounted) _showPermissionSettingsDialog('Photos & Videos');
        return false;
      }
      return false;
    } else if (sdkInt >= 29) {
      // Android 10, 11, 12 (API 29-32): scoped storage, no permission needed for image_picker
      return true;
    } else {
      // Android 9 and below (API < 29)
      final status = await Permission.storage.request();
      if (status.isPermanentlyDenied) {
        if (mounted) _showPermissionSettingsDialog('Storage');
        return false;
      }
      return status.isGranted;
    }
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      if (mounted) _showPermissionSettingsDialog('Camera');
      return false;
    }
    return status.isGranted;
  }

  void _showPermissionSettingsDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(
            '$permissionName permission is permanently denied. Enable it in app settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }

  Future<void> _pickCamera() async {
    final user = ref.read(authProvider).user;
    if (user == null || !user.can_send_attachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'You do not have permission to send attachments in this chat')),
      );
      return;
    }
    // Check internet before sending
    final hasInternet = await InternetChecker.hasInternet();
    debugPrint("hasInternet Role $hasInternet");
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No internet connection. Please check your connection.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final granted = await _requestCameraPermission();
    if (!granted) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      _showImagePreview(File(image.path));
    }
  }

  Future<void> _pickGallery() async {
    final user = ref.read(authProvider).user;
    if (user == null || !user.can_send_attachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'You do not have permission to send attachments in this chat')),
      );
      return;
    }
    // Check internet before sending
    final hasInternet = await InternetChecker.hasInternet();
    debugPrint("hasInternet Role $hasInternet");
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No internet connection. Please check your connection.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select from Gallery',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImageOption(
                  icon: Icons.image,
                  label: 'Image',
                  color: Colors.blue,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final granted =
                        await _requestMediaPermission(forVideo: false);
                    if (!granted) return;
                    final List<XFile> images =
                        await ImagePicker().pickMultiImage();
                    if (images.isNotEmpty) {
                      _showMultiImagePreview(
                          images.map((e) => File(e.path)).toList());
                    }
                  },
                ),
                _buildImageOption(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.orange,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final granted =
                        await _requestMediaPermission(forVideo: true);
                    if (!granted) return;
                    final XFile? video = await ImagePicker()
                        .pickVideo(source: ImageSource.gallery);
                    if (video != null) {
                      _showVideoPreview(File(video.path));
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Media',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _buildImageOption(
                  icon: Icons.photo_camera,
                  label: 'Camera',
                  color: Colors.pink,
                  onTap: () async {
                    Navigator.pop(context);
                    final granted = await _requestCameraPermission();
                    if (!granted) return;
                    final XFile? image =
                        await picker.pickImage(source: ImageSource.camera);
                    if (image != null) {
                      _showImagePreview(File(image.path));
                    }
                  },
                ),
                _buildImageOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: () async {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Container(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Select from Gallery',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildImageOption(
                                  icon: Icons.image,
                                  label: 'Image',
                                  color: Colors.blue,
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final List<XFile> images =
                                        await picker.pickMultiImage();
                                    if (images.isNotEmpty) {
                                      _showMultiImagePreview(images
                                          .map((e) => File(e.path))
                                          .toList());
                                    }
                                  },
                                ),
                                _buildImageOption(
                                  icon: Icons.videocam,
                                  label: 'Video',
                                  color: Colors.orange,
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final XFile? video = await picker.pickVideo(
                                        source: ImageSource.gallery);
                                    if (video != null) {
                                      _showVideoPreview(File(video.path));
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 120,
            height: 50,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _downloadFile(Message message) async {
    debugPrint(
        '📄 Download started for: ${message.fileName}, type: ${message.type}');

    // Guard: no download without internet — show a friendly message instead of a red error.
    final online = await InternetChecker.hasInternet();
    if (!online) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No internet connection. Please connect and try again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Check storage permission for Android
    if (Platform.isAndroid) {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      debugPrint('📱 Android SDK: $sdkInt');

      // Android <29 (Android 9 and below) needs storage permission
      if (sdkInt < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Storage permission is required to download files'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }
      // Android 29+ (10, 11, 12, 13, 14+) uses scoped storage - no permission needed
    }

    final fileUrl = message.fileUrl ?? message.file_path ?? '';
    if (fileUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File URL not available')),
        );
      }
      return;
    }

    final fullUrl = fileUrl.startsWith('http')
        ? fileUrl
        : '${ApiService.baseUrl}/storage/$fileUrl';

    debugPrint('🔗 Full URL: $fullUrl');

    // Get proper filename with correct extension
    String fileName =
        message.fileName ?? 'file_${DateTime.now().millisecondsSinceEpoch}';

    // Ensure correct file extension based on message type
    final lowerFileName = fileName.toLowerCase();
    switch (message.type) {
      case 'pdf':
        if (!lowerFileName.endsWith('.pdf')) {
          fileName = '$fileName.pdf';
        }
        break;
      case 'doc':
        if (!lowerFileName.endsWith('.doc') &&
            !lowerFileName.endsWith('.docx')) {
          fileName = '$fileName.doc';
        }
        break;
      case 'docx':
        if (!lowerFileName.endsWith('.docx')) {
          fileName = '$fileName.docx';
        }
        break;
      case 'image':
        if (!lowerFileName.endsWith('.jpg') &&
            !lowerFileName.endsWith('.jpeg') &&
            !lowerFileName.endsWith('.png') &&
            !lowerFileName.endsWith('.gif')) {
          fileName = '$fileName.jpg';
        }
        break;
      case 'video':
        if (!lowerFileName.endsWith('.mp4') &&
            !lowerFileName.endsWith('.mov') &&
            !lowerFileName.endsWith('.avi')) {
          fileName = '$fileName.mp4';
        }
        break;
    }

    debugPrint('📝 File name: $fileName');

    // Use app-specific external directory (works on ALL Android versions without permission)
    Directory saveDir;
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      saveDir = extDir ?? await getApplicationDocumentsDirectory();
    } else {
      saveDir = await getApplicationDocumentsDirectory();
    }

    final filePath = '${saveDir.path}/$fileName';
    debugPrint('📂 Save path: $filePath');

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Downloading $fileName...'),
          ],
        ),
      ),
    );

    try {
      final dio = Dio();
      final token = await _storage.getToken();
      if (token != null) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }
      dio.options.headers['Accept'] = '*/*';

      debugPrint('⬇️ Starting download...');
      await dio.download(
        fullUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            debugPrint('📈 Download progress: $progress%');
          }
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      debugPrint('✅ Download complete: $filePath');

      // Try to open the file
      final result = await OpenFilex.open(filePath);
      debugPrint('📄 Open result: ${result.type}, message: ${result.message}');

      if (result.type == ResultType.done) {
        // File opened successfully
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: $fileName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (result.type == ResultType.noAppToOpen) {
        // No app to open the file
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Downloaded: $fileName\nNo app found to open this file'),
              action: SnackBarAction(
                label: 'OK',
                onPressed: () {},
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        // File saved but couldn't open
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: $fileName\nSaved to: $filePath'),
              action: SnackBarAction(
                label: 'Try Open',
                onPressed: () => OpenFilex.open(filePath),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Download failed: $e');
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    final user = ref.read(authProvider).user;
    if (user == null || !user.can_send_attachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'You do not have permission to send attachments in this chat')),
      );
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        if (file.path != null) {
          await _handleDocumentSelection(File(file.path!));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Guard: user can be null during logout (e.g. while forwarding messages)
    final user = ref.watch(authProvider).user;
    if (user == null) return const SizedBox.shrink();

    // debugPrint("_messages six $_messages");
    // debugPrint("_messages six ${_messages.length}");

    return SafeArea(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _makeAsRead();
          if (Navigator.canPop(context)) {
            Navigator.pop(context, true);
          } else {
            context.go('/home');
          }
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _makeAsRead();
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, true);
                } else {
                  context.go('/home');
                }
              },
            ),
            title: GestureDetector(
              onTap: () {
                if (_user == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailScreen(
                      userId: widget.chatId,
                      userName: widget.chatName,
                      userImage: _user!['profile_picture'],
                      userDescription: _user!['description'] ?? 'Available',
                      userRole: widget.chatType,
                      imageUrl: _user!['profile_picture'],
                      member_count: widget.chatType == 'group'
                          ? _user!['member_count'] ?? 0
                          : 0,
                      isGroup: widget.chatType == 'group',
                      isOnline:
                          _onlineUsers[widget.chatId]?['isOnline'] ?? false,
                      lastSeen: _onlineUsers[widget.chatId]?['lastSeen'] != null
                          ? DateTime.fromMillisecondsSinceEpoch(
                              _onlineUsers[widget.chatId]['lastSeen'])
                          : null,
                      memberList: widget.chatType == 'group'
                          ? _user!['member_list']
                          : null,
                    ),
                  ),
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                        _user != null && _user?['profile_picture'] != null
                            ?
                            // NetworkImage(_user!['profile_picture'],
                            //  )
                            CachedNetworkImageProvider(
                                _user!['profile_picture'],
                              )
                            : null,
                    child: _user != null && _user?['profile_picture'] == null
                        ? Icon(Icons.person, color: Colors.grey[600])
                        : null,
                  ),
                  // CircleAvatar(
                  //   radius: 18,
                  //   backgroundColor: Colors.grey[300],
                  //   backgroundImage: widget.chatName == 'Reena soni'
                  //       ? const NetworkImage('https://example.com/reena-soni-profile.jpg')
                  //       : null,
                  //   child: widget.chatName == 'Reena soni'
                  //       ? null
                  //       : Icon(Icons.person, color: Colors.grey[600]),
                  // ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.chatName,
                            style: const TextStyle(fontSize: 16)),
                        _buildSubtitle(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (_isSearching) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _searchResults.isEmpty
                      ? null
                      : _navigateToPreviousSearchResult,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: _searchResults.isEmpty
                      ? null
                      : _navigateToNextSearchResult,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchResults.clear();
                      _currentSearchIndex = 0;
                      _searchController.clear();
                      _highlightedMessageId = null;
                    });
                  },
                ),
              ] else
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'search') {
                      setState(() {
                        _isSearching = true;
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                        value: 'search',
                        child: Row(
                          children: [
                            Icon(Icons.search,
                                color: Theme.of(context).iconTheme.color),
                            const SizedBox(width: 8),
                            Text('Search',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color)),
                          ],
                        )),
                  ],
                ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/icons/chat_background.png'),
                fit: BoxFit.cover,
                opacity: 0.1,
              ),
            ),
            child: Column(
              children: [
                if (_isSearching)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey[200],
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(color: Colors.black),
                            decoration: InputDecoration(
                              hintStyle: const TextStyle(color: Colors.black),
                              hintText: 'Search messages...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              suffixStyle: const TextStyle(color: Colors.red),
                              suffixText: _searchResults.isEmpty
                                  ? '0/0'
                                  : '${_currentSearchIndex + 1}/${_searchResults.length}',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                                _performSearch();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                // Sync Old Messages Button - Use cached flag
                if (_isAttendanceGroup == true)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton.icon(
                      onPressed:
                          _isLoadingOldMessages ? null : _syncOldMessages,
                      icon: _isLoadingOldMessages
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync),
                      label: Text(_isLoadingOldMessages
                          ? 'Loading...'
                          : 'Sync Old Messages'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                // Messages List
                Expanded(
                  child: Stack(
                    children: [
                      // Show 3-sec loader for attendance group on first open
                      if (_isAttendanceGroup == true && isFirstTime)
                        const Center(child: CircularProgressIndicator())
                      else
                        ListView.builder(
                          scrollCacheExtent:
                              const ScrollCacheExtent.pixels(500),
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          reverse:
                              true, // Cache more items for smoother scrolling
                          itemCount: _messages.length +
                              (_isLoadingOldMessages ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final message = _messages[index];
                            final isMe = message.senderId == user.id;

                            // Mark messages as read ONCE when they first appear
                            if (!isMe && _currentUserId != null) {
                              final messageKey =
                                  message.firebaseId ?? message.id;
                              if (!_markedAsReadMessages.contains(messageKey)) {
                                _markedAsReadMessages.add(messageKey);
                                _markMessageAsRead(message);
                              }
                            }

                            if (message.type == 'text' &&
                                message.text.isEmpty) {
                              return const SizedBox();
                            }

                            return AutoScrollTag(
                                key: ValueKey(message.id),
                                controller: _scrollController,
                                index: index,
                                child:
                                    _buildMessageBubble(message, isMe, index));
                          },
                        ),

                      // Typing indicator
                      if (_typingUsers.isNotEmpty)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: _buildTypingIndicator(),
                        ),

                      // Scroll to bottom button
                      if (!_isAtBottom)
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: FloatingActionButton.small(
                            onPressed: _scrollToBottom,
                            backgroundColor: Colors.grey,
                            child: const Icon(Icons.keyboard_arrow_down),
                          ),
                        ),
                    ],
                  ),
                ),

                // Message Input
                if (_isLoadingPermissions)
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (widget.attendance_group == true)
                  Padding(
                    padding: const EdgeInsets.only(
                        right: 16.0, left: 16.0, top: 16, bottom: 8),
                    child: SizedBox(
                      width: double.infinity, // 👈 Makes button full width
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (userRole.toString().toLowerCase() != 'teacher') {
                            return;
                          }

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MarkAttendanceScreen(
                                groupId: widget.chatId,
                                apiService: _apiService,
                              ),
                            ),
                          );
                          if (result == true && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Attendance marked successfully. Please wait while the chat is loading')),
                            );
                            // Reset page and refresh attendance data
                            await _refreshAfterAttendance();
                          }
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text(' Mark Attendance '),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 8),
                          backgroundColor:
                              userRole.toString().toLowerCase() != 'teacher'
                                  ? Colors.grey
                                  : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  )
                else if (_canSendMessage())
                  Column(
                    children: [
                      // Reply Preview
                      if (_replyToMessage != null) _buildReplyPreview(),

                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: EnhancedMessageInput(
                          controller: _messageController,
                          onSendMessage: (text) async {
                            // Check internet before sending
                            final hasInternet =
                                await InternetChecker.hasInternet();
                            debugPrint("hasInternet Role $hasInternet");
                            if (!hasInternet) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'No internet connection. Please check your connection.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }
                            _sendMessage(text: text);
                          },
                          onPickCamera:
                              _canSendAttachments() ? _pickCamera : null,
                          onPickImage:
                              _canSendAttachments() ? _pickGallery : null,
                          onPickFile: _canSendAttachments() ? _pickFile : null,
                          onTypingChanged: (isTyping) {
                            if (_currentUserId != null) {
                              FirebaseRealtimeService.setTyping(widget.chatType,
                                  widget.chatId, _currentUserId!, isTyping,
                                  attendanceGroup: _isAttendanceGroup);
                              if (isTyping) {
                                _typingTimer?.cancel();
                                _typingTimer =
                                    Timer(const Duration(seconds: 3), () {
                                  FirebaseRealtimeService.setTyping(
                                      widget.chatType,
                                      widget.chatId,
                                      _currentUserId!,
                                      false,
                                      attendanceGroup: _isAttendanceGroup);
                                });
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'You have not enough permission to send Message',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    if (_typingUsers.isNotEmpty) {
      if (widget.chatType == 'group') {
        return Text(
          '${_typingUsers.length} typing...',
          style: const TextStyle(fontSize: 12, color: Colors.green),
        );
      } else {
        return const Text(
          'typing...',
          style: TextStyle(fontSize: 12, color: Colors.green),
        );
      }
    }

    // Show member count for groups
    if (widget.chatType == 'group' &&
        _user != null &&
        _user!['member_count'] != null) {
      return Text(
        '${_user!['member_count']} Members',
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      );
    }

    // Show online status for users
    if (widget.chatType != 'group' &&
        _onlineUsers[widget.chatId]?['isOnline'] == true) {
      return const Text(
        'Online',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      );
    } else if (widget.chatType != 'group' &&
        _onlineUsers[widget.chatId]?['lastSeen'] != null) {
      final lastSeen = DateTime.fromMillisecondsSinceEpoch(
          _onlineUsers[widget.chatId]['lastSeen']);
      return Text(
        'Last seen ${_formatLastSeen(lastSeen)}',
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      );
    }

    return const Text(
      'Tap here for contact info',
      style: TextStyle(fontSize: 12, color: Colors.white70),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (_shouldShowTime(index)) _buildTimeHeader(message.timestamp),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe && widget.chatType == 'group')
                _buildSenderAvatar(message),
              Flexible(
                child: Dismissible(
                  key: Key(message.id),
                  direction: DismissDirection.startToEnd,
                  confirmDismiss: (direction) async {
                    if (mounted) {
                      setState(() {
                        _replyToMessage = message;
                      });
                    }
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: Icon(
                      Icons.reply,
                      color: Colors.grey[600],
                      size: 24,
                    ),
                  ),
                  child: GestureDetector(
                    onLongPress: () => _showMessageOptions(message),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      margin: EdgeInsets.only(
                        left: isMe ? 50 : 0,
                        right: isMe ? 0 : 50,
                        bottom: 2,
                      ),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _highlightedMessageId == message.id
                            ? (isMe
                                ? const Color(0xFF25B159)
                                : const Color(0xFF25B159))
                            : (isMe
                                ? const Color(0xFFDCF8C6)
                                : const Color(0xFFFCD7EB)),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isMe ? 12 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe && widget.chatType == 'group')
                            _buildSenderName(message),
                          if (message.isForwarded) _buildForwardedLabel(),
                          if (message.replyToMessage != null)
                            _buildReplyPreviewReply(message.replyToMessage!),
                          _buildMessageContent(message),
                          _buildMessageFooter(message, isMe),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeHeader(DateTime timestamp) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDate(timestamp),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _buildSenderAvatar(Message message) {
    // debugPrint("message.senderName${message.toJson()}Q");
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[300],
        child: Text(
          message.senderName != null && message.senderName.toString().isNotEmpty
              ? (message.senderName ?? 'U')[0].toUpperCase()
              : 'U',
          // message.senderName.toString() ,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSenderName(Message message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        message.senderName ?? 'Unknown',
        // "${message.senderName}${message.id}" ?? 'Unknown',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _getSenderColor(message.senderId),
        ),
      ),
    );
  }

  Widget _buildForwardedLabel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.forward, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreviewReply(Message replyMessage) {
    final replyType = replyMessage.type;

    return GestureDetector(
      onTap: () {
        debugPrint('Jump to message called wi ${replyMessage.id}');
        if (replyMessage.id.isNotEmpty) {
          _jumpToMessage(replyMessage.id);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: Colors.green, width: 4)),
        ),
        child: Row(
          children: [
            _buildReplyIcon(replyType),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    replyMessage.senderName ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // FormattedText()
                  Text(
                    _getReplyText(replyMessage),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (replyType == 'image' &&
                _imageSourceForMessage(replyMessage).isNotEmpty)
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(left: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _buildResolvedImage(
                    source: _imageSourceForMessage(replyMessage),
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    memCacheWidth: 80,
                    placeholder: Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.image, size: 16),
                    ),
                    errorWidget: Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.image, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyIcon(String type) {
    IconData icon;
    Color color;

    switch (type) {
      case 'image':
        icon = Icons.image;
        color = Colors.blue;
        break;
      case 'video':
        icon = Icons.videocam;
        color = Colors.orange;
        break;
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.description;
        color = Colors.blue;
        break;
      default:
        icon = Icons.message;
        color = Colors.grey;
    }

    return Icon(icon, size: 16, color: color);
  }

  String _getReplyText(Message message) {
    switch (message.type) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'pdf':
        return '📄 ${message.fileName ?? 'Document'}';
      case 'doc':
      case 'docx':
      case 'document':
        return '📄 ${message.fileName ?? 'Document'}';
      default:
        return message.text.isNotEmpty ? message.text : 'Message';
    }
  }

  Widget _buildReplyPreviewInBubble(Message replyMessage) {
    return GestureDetector(
      onTap: () => _scrollToMessage(replyMessage),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(color: Colors.green, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              replyMessage.senderName?.isNotEmpty == true
                  ? replyMessage.senderName!
                  : 'Unknown',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _getSenderColor(replyMessage.senderId),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _getReplyText(replyMessage),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(Message message) {
    switch (message.type) {
      case 'image':
        return _buildImageContent(message);
      case 'video':
        return _buildVideoContent(message);
      case 'pdf':
      case 'doc':
      case 'docx':
        return _buildDocumentContent(message);
      default:
        return _buildTextContent(message);
    }
  }

  Widget _buildTextContent(Message message) {
    if (message.text.isEmpty) return const SizedBox.shrink();

    return FormattedText(
      message.text,
      style: const TextStyle(fontSize: 16, color: Colors.black),
    );
  }

  String _messageMediaPath(Message message) {
    final fileUrl = message.fileUrl?.trim();
    if (fileUrl != null && fileUrl.isNotEmpty) return fileUrl;

    final filePath = message.file_path?.trim();
    if (filePath != null && filePath.isNotEmpty) return filePath;

    return '';
  }

  bool _isExistingLocalFile(String path) {
    return path.startsWith('/') && File(path).existsSync();
  }

  String? _localCachedImagePath(Message message) {
    final localCachedPath = message.metadata?['local_image_path']?.toString();
    if (localCachedPath != null &&
        localCachedPath.isNotEmpty &&
        _isExistingLocalFile(localCachedPath)) {
      return localCachedPath;
    }

    final mediaPath = _messageMediaPath(message);
    if (mediaPath.isNotEmpty && _isExistingLocalFile(mediaPath)) {
      return mediaPath;
    }

    return null;
  }

  String _remoteMediaUrl(String mediaPath) {
    final path = mediaPath.trim();
    if (path.isEmpty || path.startsWith('http')) return path;
    if (path.startsWith('/storage/')) return '${ApiService.baseUrl}$path';
    if (path.startsWith('storage/')) return '${ApiService.baseUrl}/$path';
    if (path.startsWith('/')) return '${ApiService.baseUrl}$path';
    return '${ApiService.baseUrl}/storage/$path';
  }

  String _imageSourceForMessage(Message message) {
    final localPath = _localCachedImagePath(message);
    if (localPath != null) return localPath;

    final mediaPath = _messageMediaPath(message);
    if (mediaPath.isEmpty) return '';

    return _remoteMediaUrl(mediaPath);
  }

  Widget _buildResolvedImage({
    required String source,
    required BoxFit fit,
    double? width,
    double? height,
    int? memCacheWidth,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    final fallback = errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
          ),
        );

    if (source.isEmpty) return fallback;

    if (_isExistingLocalFile(source)) {
      return Image.file(
        File(source),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    // Offline + no local file = show fallback immediately, no spinner
    if (!_isOnline) return fallback;

    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      maxWidthDiskCache: memCacheWidth,
      placeholder: (context, url) =>
          placeholder ??
          Container(
            width: width,
            height: height,
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          ),
      errorWidget: (context, url, error) => fallback,
    );
  }

  /// Downloads image to local storage in background (Isolate-safe via compute).
  /// Updates in-memory message + persists local_image_path to SQLite and Hive.
  void _cacheImageInBackground(Message message) {
    final msgKey = message.firebaseId ?? message.id;
    if (msgKey.isEmpty || _cachingImages.contains(msgKey)) return;

    // Resolve remote URL — skip if already a local file
    final rawUrl = (message.fileUrl?.isNotEmpty == true
            ? message.fileUrl
            : message.file_path)
        ?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return;
    if (rawUrl.startsWith('/') && File(rawUrl).existsSync()) return;

    final remoteUrl = _remoteMediaUrl(rawUrl.startsWith('http') ? rawUrl : rawUrl);
    if (remoteUrl.isEmpty) return;

    _cachingImages.add(msgKey);

    // Run download in background — does NOT block UI thread
    Future(() async {
      try {
        await _imageCacheService.initialize();
        final localPath = await _imageCacheService.downloadAndCache(remoteUrl);
        if (localPath == null || localPath == remoteUrl) return;
        if (!File(localPath).existsSync()) return;

        // Build updated metadata with local path
        final meta = Map<String, dynamic>.from(message.metadata ?? {});
        meta['local_image_path'] = localPath;
        meta['remote_image_url'] = remoteUrl;
        final updatedMessage = message.copyWith(metadata: meta);

        // Persist to SQLite + Hive so it survives app restart
        await _syncService.addMessageToCache(
          widget.chatId,
          widget.chatType,
          updatedMessage,
          currentUserId: _currentUserId,
          userRole: _userRoleCache,
          isAttendanceGroup: _isAttendanceGroup,
        );

        // Update in-memory list and rebuild only this message's widget
        if (!mounted) return;
        setState(() {
          final idx = _messages.indexWhere((m) =>
              (m.firebaseId ?? m.id) == msgKey);
          if (idx != -1) _messages[idx] = updatedMessage;
        });
        debugPrint('🖼️ Image cached offline: $localPath');
      } catch (e) {
        debugPrint('⚠️ Background image cache failed: $e');
      } finally {
        _cachingImages.remove(msgKey);
      }
    });
  }

  void _showFullScreenImage(String imageSource) {
    final source = imageSource.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: SizedBox.expand(
            child: InteractiveViewer(
              child: Center(
                child: _buildResolvedImage(
                  source: source,
                  fit: BoxFit.contain,
                  // Resize image for faster decoding
                  memCacheWidth: 400,
                  placeholder: Center(
                    child: Container(
                      color: Colors.grey.shade300,
                    ),
                  ),
                  errorWidget: const Center(
                    child: Icon(Icons.error, color: Colors.white, size: 50),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent(Message message) {
    final progress = _uploadProgress[message.id];
    final isUploading = progress != null;
    final imageSource = _imageSourceForMessage(message);

    // If no local cache yet, trigger background download (online or offline queue)
    if (message.metadata?['local_image_path'] == null ||
        !_isExistingLocalFile(message.metadata!['local_image_path'].toString())) {
      _cacheImageInBackground(message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: isUploading || imageSource.isEmpty
                  ? null
                  : () => _showFullScreenImage(imageSource),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 250, maxHeight: 300),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildResolvedImage(
                    source: imageSource,
                    fit: BoxFit.cover,
                    width: 250,
                    height: 200,
                    memCacheWidth: 250,
                  ),
                ),
              ),
            ),
            // WhatsApp-style upload progress overlay
            if (isUploading)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.black45,
                    child: Center(
                      child: _UploadProgressIndicator(progress: progress),
                    ),
                  ),
                ),
              ),
            if (!isUploading)
              Positioned(
                bottom: 4,
                right: 4,
                child: Material(
                  // Dim the button when offline to signal it's unavailable
                  color: _isOnline ? Colors.black54 : Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: _isOnline ? () => _downloadFile(message) : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No internet connection. Connect and try again.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _isOnline ? Icons.download : Icons.download_outlined,
                        color: _isOnline ? Colors.white : Colors.white38,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildVideoContent(Message message) {
    final progress = _uploadProgress[message.id];
    final isUploading = progress != null;
    debugPrint("_buildVideoContent file_path fileUrl ${message.fileUrl}");
    debugPrint("_buildVideoContent file_path ${message.file_path}");
    final videoUrl = message.fileUrl ?? message.file_path ?? '';
    final isLocalFile = videoUrl.startsWith('/');
    final fullVideoUrl = isLocalFile || videoUrl.isEmpty
        ? videoUrl
        : (videoUrl.contains(ApiService.baseUrl)
            ? videoUrl
            : '${ApiService.baseUrl}/storage/$videoUrl');

    // Determine offline state from cached _isOnline (updated in _initializeChat)
    final isOffline = !_isOnline;

    return GestureDetector(
      onTap: isUploading
          ? null
          : () async {
              // Check internet before navigating - show snackbar if offline
              final hasInternet = await InternetChecker.hasInternet();
              if (!mounted) return;
              if (!hasInternet) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white),
                        SizedBox(width: 10),
                        Text('No internet connection'),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF323232),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      VideoPlayerScreen(videoUrl: fullVideoUrl),
                ),
              );
            },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250, maxHeight: 200),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isLocalFile
                  ? Container(
                      width: 250,
                      height: 200,
                      color: Colors.black,
                      child: const Center(
                        child: Icon(Icons.videocam,
                            color: Colors.white54, size: 48),
                      ),
                    )
                  : VideoThumbnail(
                      videoUrl: fullVideoUrl,
                      isOffline: isOffline,
                    ),
            ),
            // Dark gradient overlay (always shown)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3)
                    ],
                  ),
                ),
              ),
            ),
            // Upload progress overlay OR play button
            if (isUploading)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.black45,
                    child: Center(
                      child: _UploadProgressIndicator(progress: progress),
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 40),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentContent(Message message) {
    final progress = _uploadProgress[message.id];
    final isUploading = progress != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getFileColor(message.type),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(_getFileIcon(message.type), color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'Document',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isUploading) ...[
                  const SizedBox(height: 6),
                  // Linear progress bar for documents
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.grey[300],
                      color: const Color(0xFF1dab61),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ] else if (message.fileSize != null)
                  Text(
                    _formatFileSize(message.fileSize!),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          if (!isUploading)
            IconButton(
              icon: Icon(
                Icons.download,
                // Dim icon when offline
                color: _isOnline ? const Color(0xFF1dab61) : Colors.grey[400],
              ),
              onPressed: _isOnline
                  ? () => _downloadFile(message)
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No internet connection. Connect and try again.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
            )
          else
            const SizedBox(width: 48), // keep layout stable
        ],
      ),
    );
  }

  Widget _buildMessageFooter(Message message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(message.timestamp),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            _buildMessageStatusIcon(message),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageStatusIcon(Message message) {
    String statusToCheck;
    debugPrint("AnkuhsRMMMMM Every ${message.toJson()} and  ${message.status.toString()} ");
    if (widget.chatType == 'group') {
      // For group chat, check if all members have read/delivered
      if (_user != null && _user!['member_list'] != null) {
        final members = _user!['member_list'] as List;
        // Exclude sender from the check
        final otherMembers = members
            .map((m) => m['id']?.toString() ?? m.toString())
            .where((id) => id != _currentUserId)
            .toList();

        if (otherMembers.isEmpty) {
          statusToCheck = 'sent';
        } else {
          bool allRead = true;
          bool anyDeliveredOrRead = false;

          for (final memberId in otherMembers) {
            // Check both prefixed and raw key for backward compatibility
            final memberStatus = (message.status[statusKey(memberId)] ??
                message.status[memberId]) ?? 'sent';
            if (memberStatus == 'read') {
              anyDeliveredOrRead = true;
              // allRead stays true only if all are 'read'
            } else if (memberStatus == 'delivered') {
              allRead = false;
              anyDeliveredOrRead = true;
            } else {
              // 'sent' or missing — not yet delivered
              allRead = false;
            }
          }

          if (allRead) {
            statusToCheck = 'read';
          } else if (anyDeliveredOrRead) {
            statusToCheck = 'delivered';
          } else {
            statusToCheck = 'sent';
          }
        }
      } else {
        // No member list yet — fall back to 'default' key or 'sent'
        statusToCheck = message.status['default'] ?? 'sent';
      }
    } else {
      // For private chat: scan all status entries for the other user's status.
      // Keys are stored with 'u' prefix (e.g. 'u1', 'u3') to prevent Firebase
      // array conversion. Also handle legacy unprefixed keys for old messages.
      final otherUserId = _firebaseOtherUserId ?? widget.chatId;

      final candidates = <String>[];

      // 1. Prefixed key (new format)
      final prefixedKey = statusKey(otherUserId);
      final prefixedVal = message.status[prefixedKey];
      if (prefixedVal != null) candidates.add(prefixedVal);

      // 2. Raw key (legacy format, backward compat)
      final rawVal = message.status[otherUserId];
      if (rawVal != null && !candidates.contains(rawVal)) candidates.add(rawVal);

      debugPrint("AnkuhsRMMMMM ${widget.chatId} and  ${message.status.toString()} ");
      debugPrint("AnkuhsRMMMMM $_currentUserId and $candidates");

      // 3. Scan all entries whose key is NOT the current user (handles any key format)
      for (final entry in message.status.entries) {
        final k = entry.key;
        // Skip sender keys (both prefixed and raw)
        if (k == _currentUserId || k == statusKey(_currentUserId ?? '')) continue;
        if (k == 'default') continue;
        if (!candidates.contains(entry.value)) candidates.add(entry.value);
      }
      debugPrint("AnkuhsRMMMMM $_currentUserId and $candidates");

      // 4. Legacy 'default' key
      final defaultStatus = message.status['default'];
      if (defaultStatus != null && !candidates.contains(defaultStatus)) {
        candidates.add(defaultStatus);
      }

      // Priority: read > delivered > sent
      if (candidates.contains('read')) {
        statusToCheck = 'read';
      } else if (candidates.contains('delivered')) {
        statusToCheck = 'delivered';
      } else if (candidates.isNotEmpty) {
        statusToCheck = candidates.first;
      } else {
        statusToCheck = 'sent';
      }
    }

    switch (statusToCheck) {
      case 'sending':
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1),
        );
      case 'sent':
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
      case 'failed':
        return const Icon(Icons.error_outline, size: 16, color: Colors.red);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypingDots(),
          const SizedBox(width: 8),
          Text(
            _getTypingText(),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyToMessage == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        if (_replyToMessage!.msgId != null &&
            _replyToMessage!.msgId!.isNotEmpty) {
          _jumpToMessage(_replyToMessage!.msgId!);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E8),
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(color: Color(0xFF1dab61), width: 4),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Replying to ${_replyToMessage!.senderName?.isNotEmpty == true ? _replyToMessage!.senderName! : _replyToMessage!.senderId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1dab61),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getReplyText(_replyToMessage!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.grey[600],
              onPressed: () {
                setState(() {
                  _replyToMessage = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyToMessage = message;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message copied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                _showForwardDialog(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showForwardDialog(Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ForwardMessageDialog(
        message: message,
        onForward: (message, chatIds) async {
          await _forwardMessage(message, chatIds);
        },
      ),
    );
  }

  Future<void> _forwardMessage(Message message, List<String> chatIds) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    if (!await _ensureInternetForSend() || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      for (final compositeKey in chatIds) {
        // Parse composite key "type::id" set by ForwardMessageDialog
        final parts = compositeKey.split('::');
        final chatType = parts.length == 2 ? parts[0] : widget.chatType;
        final chatId = parts.length == 2 ? parts[1] : compositeKey;

        debugPrint('📤 Forwarding to chatType=$chatType chatId=$chatId');

        final forwardedMessage = Message(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          chatId: chatId,
          senderId: user.id,
          senderName: user.name,
          text: message.text,
          type: message.type,
          timestamp: DateTime.now(),
          status: {'default': 'sending'},
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          isForwarded: true,
        );

        // Send to Firebase
        final firebaseKey = await FirebaseRealtimeService.sendMessage(
          forwardedMessage,
          chatType: chatType,
          currentUserId: user.id,
          attendanceGroup: _isAttendanceGroup,
          otherUserId: chatType != 'group' ? chatId : '0',
        );

        // Send to API
        Message? msg;
        if (chatType == 'group') {
          msg = await _apiService.sendMessage(
            message: message.text,
            groupId: chatId,
            messageType: message.type,
            filePath: message.fileUrl,
            fileName: message.fileName,
            fileSize: message.fileSize,
            firebaseKey: firebaseKey,
          );
        } else {
          msg = await _apiService.sendMessage(
            message: message.text,
            receiverId: chatId,
            messageType: message.type,
            filePath: message.fileUrl,
            fileName: message.fileName,
            fileSize: message.fileSize,
            firebaseKey: firebaseKey,
          );
        }

        // Update Firebase with API msgId
        await FirebaseRealtimeService.updateMessage(
          forwardedMessage,
          chatType: chatType,
          currentUserId: user.id,
          otherUserId: chatType != 'group' ? chatId : '0',
          attendanceGroup: _isAttendanceGroup,
          chatIdServer: msg.id.toString(),
          key: firebaseKey,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Message forwarded to ${chatIds.length} chat(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to forward message')),
        );
      }
    }
  }

  // Helper methods
  Color _getSenderColor(String senderId) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal
    ];
    return colors[senderId.hashCode % colors.length];
  }

  Color _getFileColor(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getFileIcon(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  // String _getReplyText(Message replyMessage) {
  //   switch (replyMessage.type) {
  //     case 'image': return replyMessage.text.isNotEmpty ? replyMessage.text : '📷 Photo';
  //     case 'pdf': return '📄 ${replyMessage.fileName ?? 'PDF Document'}';
  //     case 'doc':
  //     case 'docx': return '📄 ${replyMessage.fileName ?? 'Word Document'}';
  //     default: return replyMessage.text;
  //   }
  // }

  String _getTypingText() {
    final typingUserIds =
        _typingUsers.keys.where((key) => _typingUsers[key] == true).toList();

    if (typingUserIds.isEmpty) return '';

    if (widget.chatType == 'group') {
      if (typingUserIds.length == 1) {
        return 'typing...';
      } else {
        return '${typingUserIds.length} people are typing...';
      }
    } else {
      return 'typing...';
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $period';

    if (difference.inDays == 0) {
      return time;
    } else if (difference.inDays == 1) {
      return 'Yesterday $time';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} $time';
    }
  }

  // String _formatTime(DateTime timestamp) {
  //   final now = DateTime.now();
  //   final difference = now.difference(timestamp);

  //   if (difference.inDays == 0) {
  //     return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  //   } else if (difference.inDays == 1) {
  //     return 'Yesterday ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  //   } else {
  //     return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  //   }
  // }

  String _formatDate(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);
    final difference = today.difference(messageDate).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7 &&
        messageDate.isAfter(today.subtract(Duration(days: now.weekday - 1)))) {
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      return weekdays[timestamp.weekday - 1];
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool _shouldShowTime(int index) {
    if (index == _messages.length - 1) return true;

    final currentMessage = _messages[index];
    final nextMessage = _messages[index + 1];

    final currentDate = DateTime(currentMessage.timestamp.year,
        currentMessage.timestamp.month, currentMessage.timestamp.day);
    final nextDate = DateTime(nextMessage.timestamp.year,
        nextMessage.timestamp.month, nextMessage.timestamp.day);

    return !currentDate.isAtSameMomentAs(nextDate);
  }
}

/// WhatsApp-style circular upload progress shown over image/video bubbles.
class _UploadProgressIndicator extends StatelessWidget {
  final double progress;
  const _UploadProgressIndicator({required this.progress});

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).toInt();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white30,
                color: Colors.white,
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Uploading...',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

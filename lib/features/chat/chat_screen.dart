import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../core/models/chat_model.dart';
import '../../core/models/message_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_realtime_service.dart';
import '../../core/services/whatsapp_text_parser.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/internet_checker.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../core/services/chat_list_update_service.dart';
import '../../core/services/active_chat_tracker.dart';
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

// NEW: Import message sync service
import '../../core/services/message_sync_service.dart';

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

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final ApiService _apiService;
  final StorageService _storage = StorageService();

  // NEW: Message sync service for instant loading
  final MessageSyncService _syncService = MessageSyncService();
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
  bool _isLoadingPermissions = true;
  String? _highlightedMessageId;
  bool _initialMessageSent = false;
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
      _isAttendanceGroup = widget.attendance_group;
      getUserRole();
      _initializeChat();
      _handleInitialMessage();
    });
  }

  var userRole;
  String? _userRoleCache; // Cache user role to avoid repeated lookups

  void getUserRole() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    debugPrint("AnkushuserRole ${user.toJson()}");
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

  Future<void> _initializeChat() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    _currentUserId = user.id;

    try {
      await FirebaseRealtimeService.setUserOnline(user.id);
      await _loadInitialMessages();

      debugPrint(
          "🔥 _setupRealtimeListeners check: attendance_group=$_isAttendanceGroup");
      // Setup Firebase listeners for non-attendance groups
      // Attendance group flag is now set in _loadInitialMessages()
      if (_isAttendanceGroup != true) {
        debugPrint("✅ Setting up Firebase listeners for regular chat");
        _setupRealtimeListeners();
      } else {
        debugPrint("⏭️ Skipping Firebase listeners for attendance group");
      }

      // Start background sync for API (every 30 seconds)
      _syncService.startBackgroundSync(
        chatId: widget.chatId,
        chatType: widget.chatType,
        apiService: _apiService,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
        otherUserId: _firebaseOtherUserId,
      );

      ref.read(chatProvider.notifier).resetUnreadCount(widget.chatId);

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

          // Update chat list to reset unread count
          ChatListUpdateService.updateOnMessageReceived(
            chatId: widget.chatId,
            chatType: widget.chatType,
            attendanceGroup: widget.attendance_group ?? false,
            lastMessage: _messages.isNotEmpty ? _messages.first.text : '',
            incrementUnread: false,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingOldMessages = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize chat: $e')),
        );
      }
      debugPrint('Error in _initializeChat: $e');
    }

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  int pageCount = 1;

  Future<void> _syncOldMessages() async {
    debugPrint("_syncOldMessages$_isLoadingOldMessages");
    if (_isLoadingOldMessages) return;

    setState(() {
      _isLoadingOldMessages = true;
    });

    try {
      final nextPage = pageCount + 1;

      final olderMessages = await _syncService.loadMoreMessages(
        chatId: widget.chatId,
        chatType: widget.chatType,
        apiService: _apiService,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
        page: nextPage,
        limit: ApiService.messageCount,
      );

      if (mounted) {
        setState(() {
          _messages.insertAll(0, olderMessages);
          _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          pageCount = nextPage;
          _isLoadingOldMessages = false;
        });
        debugPrint(
            '✅ Loaded page $nextPage with ${olderMessages.length} messages');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingOldMessages = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load old messages: $e')),
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
    _isAttendanceGroup ??= widget.attendance_group;
    _user ??= {
      'id': widget.chatId,
      'name': widget.chatName,
      'attendance_group': _isAttendanceGroup,
      if (widget.chatType == 'group') 'member_list': <dynamic>[],
    };
  }

  void _setupCacheWatcher() {
    _cacheSubscription?.cancel();
    _cacheSubscription = _syncService
        .watchMessages(
      widget.chatId,
      widget.chatType,
      currentUserId: _currentUserId,
      userRole: _userRoleCache,
      isAttendanceGroup: _isAttendanceGroup,
    )
        .listen((cachedMessages) {
      if (!mounted) return;
      if (cachedMessages.isEmpty && _messages.isNotEmpty) return;

      setState(() {
        _messages = _messages.isEmpty
            ? cachedMessages
            : _mergeMessages(_messages, cachedMessages);
        _isLoadingPermissions = false;
      });
    }, onError: (error) {
      debugPrint('Message cache watch error: $error');
    });
  }

  Future<void> _loadInitialMessages() async {
    try {
      _hydrateChatMetadataFromRoute();
      _setupCacheWatcher();

      if (widget.attendance_group == false) {


      final cachedMessages = await _syncService.getCachedMessages(
        widget.chatId,
        widget.chatType,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: widget.attendance_group,
      );

      if (mounted) {
        setState(() {
          if (cachedMessages.isNotEmpty) {
            _messages = cachedMessages;
          }
          _isLoadingPermissions = false;
        });
      }

      debugPrint('⚡ Chat opened with ${cachedMessages.length} cached messages');

      if (_isAttendanceGroup == true) {
        unawaited(_loadConversationMetadataFromApi(
          shouldLoadAttendanceMessages: true,
        ));
      } else {
        _warmRecentMessagesInBackground(
          shouldFallbackToApiMessages: cachedMessages.isEmpty,
        );
        unawaited(_loadConversationMetadataFromApi(
          shouldFallbackToApiMessages: false,
        ));
      }
    }
    } catch (e) {
      debugPrint('❌ Load initial messages error: $e');
      if (mounted) {
        setState(() {
          _isLoadingPermissions = false;
        });
      }
    }
  }

  void _warmRecentMessagesInBackground({
    required bool shouldFallbackToApiMessages,
  }) {
    unawaited(() async {
      final firebaseMessages = await _syncService.syncRecentFirebaseMessages(
        chatId: widget.chatId,
        chatType: widget.chatType,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: widget.attendance_group,
        otherUserId: _firebaseOtherUserId,
        limit: ApiService.messageCount,
      );

      if (!mounted ||
          !shouldFallbackToApiMessages ||
          firebaseMessages.isNotEmpty) {
        return;
      }

      await _loadConversationMetadataFromApi(
        shouldFallbackToApiMessages: true,
      );
    }());
  }

  Future<void> _loadConversationMetadataFromApi({
    bool shouldLoadAttendanceMessages = false,
    bool shouldFallbackToApiMessages = false,
  }) async {
    final hasInternet = await InternetChecker.hasInternet();
    if (!hasInternet) return;

    try {
      final id = int.parse(widget.chatId);
      final limit = shouldLoadAttendanceMessages || shouldFallbackToApiMessages
          ? ApiService.messageCount
          : 1;

      Map<String, dynamic>? userData;
      List<Message> messages = [];

      if (widget.chatType == 'group') {
        final response = await _apiService.getGroupMessages(id, 1, limit);
        userData = Map<String, dynamic>.from(response.user);
        messages = response.data;
      } else {
        final response = await _apiService.getConversation(id, 1, limit);
        userData = Map<String, dynamic>.from(response.user);
        messages = response.data;
      }

      if (!mounted) return;

      final attendanceValue = userData['attendance_group'];
      final isAttendance = attendanceValue == true ||
          attendanceValue == 1 ||
          attendanceValue?.toString().toLowerCase() == 'true';
      final previousAttendanceGroup = _isAttendanceGroup;

      setState(() {
        _user = userData;
        _isAttendanceGroup = isAttendance;
      });

      if (previousAttendanceGroup != _isAttendanceGroup) {
        _setupCacheWatcher();
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

        if (mounted) {
          setState(() {
            _messages = messages;
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
          debugPrint("AnkushrealtimeMessages ${realtimeMessages.first}");
          if (realtimeMessages.isNotEmpty && mounted) {
            final previousLength = _messages.length;
            setState(() {
              // Use cached _isAttendanceGroup flag for consistency
              if (_isAttendanceGroup == true) {
                _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
              } else {
                _messages = _mergeMessages(_messages, realtimeMessages);
              }
            });

            if (_messages.length > previousLength &&
                realtimeMessages.isNotEmpty) {
              final newMessage = realtimeMessages.first;
              if (newMessage.senderId != _currentUserId) {
                ref.read(chatProvider.notifier).onMessageReceived(
                      widget.chatId,
                      widget.chatType,
                      newMessage,
                      true,
                    );
              }
            }

            if (_isAtBottom && _messages.length > previousLength) {
              Future.delayed(
                  const Duration(milliseconds: 100), _scrollToBottom);
            }
          }
        });

    _typingSubscription = FirebaseRealtimeService.getTypingUsers(
            widget.chatId, widget.chatType,
            currentUserId: _currentUserId,
            attendanceGroup: _isAttendanceGroup,
            otherUserId: _currentUserId)
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
    debugPrint("AnkushuserRole ${user.toJson()}");
    // Ankush revert
    var userRole = user.actual_role.toLowerCase();
    if (userRole == 'no user') {
      userRole = user.role.toLowerCase();
    }
    final isLocked = _user!['is_locked'] == true;
    final messagePermission =
        _user!['message_permission']?.toString().toLowerCase();

    debugPrint(
        "AnkushuserRole _canSendMessage messagePermission ${messagePermission} isLocked $isLocked  userRole $userRole");
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
    return _user!['allow_attachments'] == true;
  }

  List<Message> _mergeMessages(
      List<Message> apiMessages, List<Message> realtimeMessages) {
    final messageMap = <String, Message>{};
    final firebaseIdToItem = <String, Message>{};

    // Add existing messages by firebaseId or id
    for (final message in apiMessages) {
      final key = message.firebaseId ?? message.id;
      if (key.isNotEmpty) {
        messageMap[key] = message;
      }
    }

    // Merge realtime messages
    for (final message in realtimeMessages) {
      final firebaseId = message.firebaseId;
      if (firebaseId != null && firebaseId.isNotEmpty) {
        // Remove temp message if exists
        final tempKey = messageMap.keys.firstWhere(
          (k) => k.startsWith('temp_') && messageMap[k]?.text == message.text,
          orElse: () => '',
        );
        if (tempKey.isNotEmpty) {
          messageMap.remove(tempKey);
        }
        messageMap[firebaseId] = message;
      } else if (message.id.startsWith('temp_')) {
        messageMap[message.id] = message;
      }
    }

    // Keep items with non-zero id
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

    if (_isAtBottom != isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
      });
    }

    // Load more messages when scrolling to top (in reverse list, top = maxScrollExtent)
    final distanceFromTop = position.maxScrollExtent - position.pixels;
    if (distanceFromTop <= 200 &&
        !_isLoadingOldMessages &&
        position.maxScrollExtent > 0) {
      // Use cached _isAttendanceGroup flag
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

  // Optimized: Mark message as read only once
  void _markMessageAsRead(Message message) {
    final firebaseId = message.firebaseId ?? message.id;
    // Use cached _isAttendanceGroup flag
    final msgId = _isAttendanceGroup == true ? message.id : message.msgId;
    final currentStatus = message.status[_currentUserId] ?? 'sent';

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
      return msg.text.toLowerCase().contains(_searchQuery.toLowerCase());
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
    if (_currentUserId == null) return;

    final messageText = text ?? fileName ?? '';
    if (messageText.trim().isEmpty && type == 'text') return;

    if (!await _ensureInternetForSend()) return;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final user = ref.read(authProvider).user!;

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
      replyToMessage: _replyToMessage,
    );

    // Optimistic UI update - add message immediately
    if (mounted) {
      setState(() {
        _messages.insert(0, message);
        _replyToMessage = null;
      });
    }

    // Cache message immediately
    await _syncService.addMessageToCache(
      widget.chatId,
      widget.chatType,
      message,
      currentUserId: _currentUserId,
      userRole: _userRoleCache,
      isAttendanceGroup: _isAttendanceGroup,
    );

    _messageController.clear();
    FirebaseRealtimeService.setTyping(
        widget.chatType, widget.chatId, _currentUserId!, false,
        attendanceGroup: _isAttendanceGroup);
    _scrollToBottom();

    try {
      final sentMessage = await _sendToAPI(message);
      await _syncService.replaceMessageInCache(
        widget.chatId,
        widget.chatType,
        tempId,
        sentMessage,
        currentUserId: _currentUserId,
        userRole: _userRoleCache,
        isAttendanceGroup: _isAttendanceGroup,
      );

      if (mounted) {
        setState(() {
          _messages = _mergeMessages(
            _messages.where((item) => item.id != tempId).toList(),
            [sentMessage],
          );
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
        attendanceGroup: widget.attendance_group ?? false,
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

      return msg.copyWith(
        chatId: widget.chatId,
        firebaseId: firebaseKey,
        status: {'default': 'sent'},
        replyToMessage: message.replyToMessage,
      );
    } catch (e) {
      debugPrint('Ankush /save $e ${message.toJson()}');
      rethrow;
    }
  }

  void _updateMessageStatus(String messageId, String status) {
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
    try {
      if (!await _ensureInternetForSend()) return;
      final uploadResponse = await _apiService.uploadFile(file, messageType);

      await _sendMessage(
        type: messageType,
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send file')),
        );
      }
    }
  }

  Future<void> _handleImageSelection(File file) async {
    try {
      if (!await _ensureInternetForSend()) return;
      setState(() {
        // Show loading state if needed
      });

      final uploadResponse = await _apiService.uploadFile(file, 'image');

      await _sendMessage(
        type: 'image',
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
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
    try {
      if (!await _ensureInternetForSend()) return;
      final uploadResponse = await _apiService.uploadFile(file, 'video');
      await _sendMessage(
        type: 'video',
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send video')),
        );
      }
    }
  }

  Future<void> _handleDocumentSelection(File file) async {
    try {
      if (!await _ensureInternetForSend()) return;
      final extension = file.path.split('.').last.toLowerCase();
      final messageType = extension == 'pdf' ? 'pdf' : 'doc';
      final uploadResponse = await _apiService.uploadFile(file, messageType);
      await _sendMessage(
        type: messageType,
        fileUrl: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        fileSize: uploadResponse.fileSize,
      );
    } catch (e) {
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
    // final messageState = ref.watch(messageProvider);
    final user = ref.watch(authProvider).user!;

    return SafeArea(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;

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
                            SizedBox(width: 8),
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
                              suffixStyle: TextStyle(color: Colors.red),
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
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        reverse: true,
                        cacheExtent:
                            500, // Cache more items for smoother scrolling
                        itemCount:
                            _messages.length + (_isLoadingOldMessages ? 1 : 0),
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
                            final messageKey = message.firebaseId ?? message.id;
                            if (!_markedAsReadMessages.contains(messageKey)) {
                              _markedAsReadMessages.add(messageKey);
                              _markMessageAsRead(message);
                            }
                          }

                          if (message.type == 'text' && message.text.isEmpty) {
                            return const SizedBox();
                          }

                          return AutoScrollTag(
                              key: ValueKey(message.id),
                              controller: _scrollController,
                              index: index,
                              child: _buildMessageBubble(message, isMe, index));
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
                else if (_isAttendanceGroup == true)
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
                                  content:
                                      Text('Attendance marked successfully')),
                            );
                            initUI();
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
                          onSendMessage: (text) => _sendMessage(text: text),
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
                            color: Colors.black.withOpacity(0.1),
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
            color: Colors.green.withOpacity(0.5),
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
            if (replyType == 'image' && replyMessage.file_path != null)
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(left: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl:
                        '${ApiService.baseUrl}/storage/${replyMessage.fileUrl!}',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.image, size: 16),
                    ),
                    errorWidget: (context, url, error) => Container(
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
          color: Colors.black.withOpacity(0.1),
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

  void _showFullScreenImage(String imageUrl) {
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
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  // Resize image for faster decoding
                  memCacheWidth: 400,
                  maxWidthDiskCache: 400,
                  placeholder: (context, url) => Center(
                    child: Container(
                      color: Colors.grey.shade300,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
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
    final imageUrl = message.fileUrl ?? message.file_path ?? '';
    final fullImageUrl = imageUrl.contains(ApiService.baseUrl)
        ? imageUrl
        : '${ApiService.baseUrl}/storage/$imageUrl';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: () => _showFullScreenImage(fullImageUrl),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 250, maxHeight: 300),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: fullImageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 250,
                    maxWidthDiskCache: 250,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, error, stackTrace) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.broken_image,
                            size: 50, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () => _downloadFile(message),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.download, color: Colors.white, size: 20),
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
    final videoUrl = message.fileUrl ?? message.file_path ?? '';
    final fullVideoUrl = videoUrl.contains(ApiService.baseUrl)
        ? videoUrl
        : '${ApiService.baseUrl}/storage/$videoUrl';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(videoUrl: fullVideoUrl),
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250, maxHeight: 200),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: VideoThumbnail(videoUrl: fullVideoUrl),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentContent(Message message) {
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
            child: Icon(
              _getFileIcon(message.type),
              color: Colors.white,
              size: 24,
            ),
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
                if (message.fileSize != null)
                  Text(
                    _formatFileSize(message.fileSize!),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            color: const Color(0xFF1dab61),
            onPressed: () => _downloadFile(message),
          ),
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

    if (widget.chatType == 'group') {
      // For group chat, check if all members have read
      if (_user != null && _user!['member_list'] != null) {
        final members = _user!['member_list'] as List;
        bool allRead = true;
        bool anyDelivered = false;

        for (final member in members) {
          final memberId = member['id']?.toString() ?? member.toString();
          if (memberId != _currentUserId) {
            final memberStatus = message.status[memberId] ?? 'sent';
            if (memberStatus == 'read') {
              anyDelivered = true;
            } else if (memberStatus == 'delivered') {
              allRead = false;
              anyDelivered = true;
            } else {
              allRead = false;
            }
          }
        }

        if (allRead && anyDelivered) {
          statusToCheck = 'read';
        } else if (anyDelivered) {
          statusToCheck = 'delivered';
        } else {
          statusToCheck = 'sent';
        }
      } else {
        statusToCheck = 'sent';
      }
    } else {
      // For private chat, check the receiver's status only
      final otherUserId = _firebaseOtherUserId;
      statusToCheck = message.status[otherUserId] ?? 'sent';
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
            color: Colors.black.withOpacity(0.1),
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
      for (final chatId in chatIds) {
        final chat = ref.read(chatProvider).chats.firstWhere(
              (c) => c.id == chatId,
              orElse: () => Chat(
                id: chatId,
                type: widget.chatType,
                participants: [],
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                unreadCount: {},
              ),
            );

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
          chatType: chat.type,
          currentUserId: user.id,
          attendanceGroup: _isAttendanceGroup,
          otherUserId: chat.type != 'group' ? chatId : '0',
        );

        // Send to API
        Message? msg;
        if (chat.type == 'group') {
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
          chatType: chat.type,
          currentUserId: user.id,
          otherUserId: chat.type != 'group' ? chatId : '0',
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

    if (difference.inDays == 0) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

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

# 🚀 QUICK START GUIDE - Offline Mode Integration

## Already Implemented ✅

All core services, widgets, and utilities are ready. Just integrate into your chat screen.

## 5-Minute Integration for Chat Screen

### Step 1: Import Required Files
```dart
import '../../core/services/offline_queue_service.dart';
import '../../core/services/sync_service.dart';
import '../../shared/widgets/offline_status_widget.dart';
import '../../shared/widgets/linkify_text.dart';
import '../../core/utils/internet_checker.dart';
import 'package:dio/dio.dart';
```

### Step 2: Initialize Sync Service
```dart
class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final SyncService _syncService;
  
  @override
  void initState() {
    super.initState();
    final dio = Dio();
    final apiService = ApiService(dio);
    _syncService = SyncService(apiService);
  }
}
```

### Step 3: Add Offline Status Widget (in build method)
```dart
Column(
  children: [
    const OfflineStatusWidget(),  // ← Add this line
    Expanded(child: /* your message list */),
    /* your message input */
  ],
)
```

### Step 4: Replace Text Widget with LinkifyText
```dart
// OLD:
Text(message.text, style: TextStyle(fontSize: 16))

// NEW:
LinkifyText(message.text, style: TextStyle(fontSize: 16))
```

### Step 5: Queue Messages When Offline
```dart
Future<void> _sendMessage({String? text}) async {
  if (text == null || text.trim().isEmpty) return;
  
  final hasInternet = await InternetChecker.hasInternet();
  
  if (!hasInternet) {
    // OFFLINE: Queue the message
    await OfflineMessageHelper.queueMessage(
      chatId: widget.chatId,
      chatType: widget.chatType,
      message: text,
      type: 'text',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📤 Message queued. Will send when online.'),
          backgroundColor: Colors.orange,
        ),
      );
      _messageController.clear();
    }
    return;
  }
  
  // ONLINE: Send immediately (your existing code)
  // ... existing send logic
}
```

### Step 6: Cache Messages on Load
```dart
Future<void> _loadInitialMessages() async {
  try {
    // 1. Load from cache instantly
    final cachedMessages = await _syncService._getCachedMessages(
      '${widget.chatType}_${widget.chatId}'
    );
    
    if (cachedMessages.isNotEmpty && mounted) {
      setState(() {
        _messages = cachedMessages;
        _isLoadingPermissions = false;
      });
    }
    
    // 2. Sync with backend in background
    final syncedMessages = await _syncService.syncChatMessages(
      chatId: widget.chatId,
      chatType: widget.chatType,
    );
    
    if (mounted) {
      setState(() {
        _messages = syncedMessages;
      });
    }
  } catch (e) {
    debugPrint('❌ Cache load failed, using API: $e');
    // Fallback to your existing API call
  }
}
```

## Done! 🎉

Your chat screen now has:
- ✅ Offline mode (queue messages when offline)
- ✅ Clickable links (URLs open in browser)
- ✅ Cached messages (instant load)
- ✅ Background sync (smooth experience)
- ✅ Queue status (see pending messages)

## Optional Enhancements

### Show "Pending" Badge on Messages
```dart
Widget _buildMessageBubble(Message message, bool isMe) {
  final isPending = message.id.startsWith('temp_');
  
  return Container(
    child: Column(
      children: [
        /* message content */
        
        if (isPending)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Pending',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
      ],
    ),
  );
}
```

### Add "Retry Failed" Button
```dart
final queueStats = OfflineQueueService.getQueueStats();
if (queueStats['failed'] > 0) {
  ElevatedButton(
    onPressed: () async {
      await OfflineQueueService._processQueue();
    },
    child: Text('Retry ${queueStats['failed']} Failed Messages'),
  );
}
```

## Notification Settings (Optional)

Add to profile/settings screen:

```dart
ListTile(
  title: Text('Notification Settings'),
  trailing: Icon(Icons.chevron_right),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationPreferencesScreen(),
      ),
    );
  },
)
```

## Testing Commands

```bash
# Test offline mode
# 1. Turn off internet
# 2. Open app → Chat list loads from cache
# 3. Send message → Shows "queued" snackbar
# 4. Turn on internet → Message sends automatically

# Test links
# 1. Send message: "Check https://google.com"
# 2. Link should be blue and underlined
# 3. Tap link → Opens in browser

# Test updates
# 1. Open app → Wait 2 seconds
# 2. If update available → Dialog shows
# 3. "Update Now" → Opens Play Store
```

## Need Help?

- See `OFFLINE_IMPLEMENTATION_GUIDE.md` for detailed docs
- See `IMPLEMENTATION_COMPLETE.md` for full feature list
- Check `offline_queue_service.dart` for queue methods
- Check `sync_service.dart` for caching methods

## Common Issues

**Queue not working?**
- Check `HiveInitService.initialize()` is called in main.dart
- Check `OfflineQueueService.initialize()` is called in main.dart

**Cache not loading?**
- Check `SyncService.initialize()` is called in main.dart
- Verify Hive boxes are opened successfully

**Links not clickable?**
- Ensure `url_launcher` package is in pubspec.yaml
- Replace `Text()` with `LinkifyText()`

**Update dialog not showing?**
- API endpoint must return correct version format
- Check console for update check logs

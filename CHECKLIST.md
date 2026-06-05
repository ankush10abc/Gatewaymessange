# Implementation Checklist: 6 Critical Offline-First APIs

## ✅ Flutter Client Implementation Status

### Phase 1: Core Services (COMPLETED ✅)

- [x] **API Service** (`lib/core/services/api_service_simple.dart`)
  - [x] `batchSendMessages()` - API 1
  - [x] `syncMessages()` - API 2
  - [x] `syncChats()` - API 3
  - [x] `batchMarkAsRead()` - API 4
  - [x] `getQueueStatus()` - API 5
  - [x] `checkAppVersion()` - API 6

- [x] **Offline Queue Service** (`lib/core/services/offline_queue_service.dart`)
  - [x] PendingMessage model
  - [x] Queue management (max 1000)
  - [x] Auto-send when online
  - [x] Batch processing (50 per batch)
  - [x] Retry logic (max 3 attempts)
  - [x] Queue statistics

- [x] **Sync Service** (`lib/core/services/sync_service.dart`)
  - [x] Incremental message sync
  - [x] Incremental chat list sync
  - [x] Local Hive caching
  - [x] Batch mark as read
  - [x] Last sync time tracking

- [x] **Update Service** (`lib/core/services/update_service.dart`)
  - [x] Version checking
  - [x] Force update dialog
  - [x] Optional update dialog
  - [x] Play Store deep linking
  - [x] Direct APK download

- [x] **Documentation**
  - [x] Integration guide with examples
  - [x] Implementation documentation
  - [x] Architecture diagrams
  - [x] This checklist

---

## ⏳ Backend Implementation (PENDING)

### Phase 2: Backend APIs (TODO)

- [ ] **API 1: Batch Message Send**
  - [ ] Create route: `POST /api/messages/batch-send`
  - [ ] Implement validation (temp_id, chat_id, message required)
  - [ ] Check user permissions per chat
  - [ ] Save messages in transaction
  - [ ] Return sent/failed arrays
  - [ ] Test with 100 messages
  - [ ] **Estimated time**: 1.5 hours

- [ ] **API 2: Incremental Message Sync**
  - [ ] Create route: `GET /api/messages/sync`
  - [ ] Query messages where `created_at > since` parameter
  - [ ] Query updated messages where `updated_at > since` and `created_at <= since`
  - [ ] Query deleted messages from soft delete table
  - [ ] Return new/updated/deleted arrays
  - [ ] Test with various timestamps
  - [ ] **Estimated time**: 1.5 hours

- [ ] **API 3: Incremental Chat List Sync**
  - [ ] Create route: `GET /api/chats/sync`
  - [ ] Query chats where `created_at > since`
  - [ ] Query chats where `updated_at > since` and `created_at <= since`
  - [ ] Query deleted chats from soft delete table
  - [ ] Return new/updated/deleted chat arrays
  - [ ] Test sync with 50 chats
  - [ ] **Estimated time**: 1.5 hours

- [ ] **API 4: Batch Mark as Read**
  - [ ] Create route: `POST /api/messages/batch-read`
  - [ ] Accept array of message IDs
  - [ ] Validate user can read these messages
  - [ ] Update `read_at` timestamp for all
  - [ ] Return success count
  - [ ] Test with 100 message IDs
  - [ ] **Estimated time**: 1 hour

- [ ] **API 5: Queue Status**
  - [ ] Create route: `GET /api/sync/queue-status`
  - [ ] Query user's pending messages (if stored server-side)
  - [ ] Return counts and oldest timestamp
  - [ ] Test with various queue states
  - [ ] **Estimated time**: 0.5 hours

- [ ] **API 6: App Version Check**
  - [ ] Create route: `GET /api/app/version-check`
  - [ ] Create `app_versions` table (version, platform, type, notes, apk_url)
  - [ ] Compare current_version with latest
  - [ ] Determine if force or optional update
  - [ ] Return update info with URLs
  - [ ] Test with different version combinations
  - [ ] **Estimated time**: 1.5 hours

**Total Backend Time**: 7-8 hours

---

## 📱 Flutter Integration (TODO)

### Phase 3: Integrate into Existing App

- [ ] **1. Initialize Services** (`main.dart`)
  ```dart
  // Add after Hive.initFlutter()
  await OfflineQueueService.initialize(apiService);
  await SyncService.initialize();
  ```
  - [ ] Add initialization code
  - [ ] Test app launches without errors
  - [ ] **Time**: 10 minutes

- [ ] **2. Update ChatProvider** (`lib/shared/providers/chat_provider.dart`)
  ```dart
  // Replace API call with sync service
  final cachedChats = await _syncService.getCachedChatList();
  state = AsyncValue.data(cachedChats);
  final syncedChats = await _syncService.syncChatList();
  state = AsyncValue.data(syncedChats);
  ```
  - [ ] Inject SyncService into provider
  - [ ] Load from cache first
  - [ ] Sync in background
  - [ ] Test instant loading
  - [ ] **Time**: 30 minutes

- [ ] **3. Update HomeScreen** (`lib/features/home/home_screen.dart`)
  - [ ] Add pull-to-refresh for manual sync
  - [ ] Add queue status indicator
  - [ ] Show "syncing" indicator when syncing
  - [ ] Test instant chat list display
  - [ ] **Time**: 30 minutes

- [ ] **4. Update ChatScreen - Send Messages** (`lib/features/chat/chat_screen.dart`)
  ```dart
  if (await OfflineQueueService.isOnline()) {
    await apiService.sendMessage(...);
  } else {
    await OfflineQueueService.queueMessage(pendingMessage);
    // Show "Will send when online" snackbar
  }
  ```
  - [ ] Add offline check before sending
  - [ ] Queue messages when offline
  - [ ] Show user feedback
  - [ ] Test offline sending
  - [ ] **Time**: 45 minutes

- [ ] **5. Update ChatScreen - Load Messages**
  - [ ] Load cached messages on open
  - [ ] Sync in background
  - [ ] Display pending messages with "clock" icon
  - [ ] Test instant message display
  - [ ] **Time**: 30 minutes

- [ ] **6. Implement Batch Mark as Read** (`lib/features/chat/chat_screen.dart`)
  ```dart
  final unreadIds = messages.where((m) => m.readAt == null)
                            .map((m) => int.parse(m.id))
                            .toList();
  await syncService.batchMarkAsRead(
    messageIds: unreadIds,
    chatId: chatId,
    chatType: chatType,
  );
  ```
  - [ ] Replace individual markAsRead calls
  - [ ] Batch mark on chat open
  - [ ] Test with 50 unread messages
  - [ ] **Time**: 20 minutes

- [ ] **7. Add Update Check** (Main screen)
  ```dart
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 2), () {
      updateService.checkAndShowUpdate(context);
    });
  }
  ```
  - [ ] Add check on app start
  - [ ] Test force update dialog
  - [ ] Test optional update dialog
  - [ ] **Time**: 15 minutes

- [ ] **8. Create Riverpod Providers** (`lib/shared/providers/`)
  - [ ] Create `syncServiceProvider`
  - [ ] Create `updateServiceProvider`
  - [ ] Update existing providers to use sync service
  - [ ] **Time**: 20 minutes

**Total Flutter Integration Time**: 3-4 hours

---

## 🧪 Testing Phase (TODO)

### Phase 4: Comprehensive Testing

- [ ] **Offline Queue Tests**
  - [ ] Turn off internet
  - [ ] Send 10 messages
  - [ ] Verify queue shows 10 pending
  - [ ] Turn on internet
  - [ ] Verify messages send automatically
  - [ ] Verify queue becomes empty

- [ ] **Incremental Sync Tests**
  - [ ] Open app (should load instantly)
  - [ ] Send message from another device
  - [ ] Pull to refresh
  - [ ] Verify only new message downloaded (check logs)
  - [ ] Repeat with 100 new messages

- [ ] **Batch Mark as Read Tests**
  - [ ] Receive 50 unread messages
  - [ ] Open chat
  - [ ] Check debug logs
  - [ ] Verify only 1 API call (not 50)
  - [ ] Verify all messages marked as read

- [ ] **Update Dialog Tests**
  - [ ] Set backend version to 1.0.24 (force update)
  - [ ] Launch app with version 1.0.23
  - [ ] Verify force dialog appears
  - [ ] Verify cannot skip
  - [ ] Set backend version to 1.0.25 (optional update)
  - [ ] Verify optional dialog appears
  - [ ] Verify can skip

- [ ] **Queue Full Tests**
  - [ ] Stay offline
  - [ ] Send 1000 messages
  - [ ] Try sending 1001st message
  - [ ] Verify error "Queue full" appears
  - [ ] Go online
  - [ ] Verify all 1000 send successfully

- [ ] **Performance Tests**
  - [ ] Measure app launch time (<500ms target)
  - [ ] Measure chat list load (<100ms target)
  - [ ] Measure chat open time (<100ms target)
  - [ ] Measure batch read time (<500ms for 50 messages)

- [ ] **Edge Case Tests**
  - [ ] Send message with no internet, then reinstall app
  - [ ] Corrupt Hive database and verify recovery
  - [ ] Test with 1 lakh messages in cache
  - [ ] Test sync with slow 2G connection
  - [ ] Test simultaneous message send from 2 devices

**Total Testing Time**: 4-5 hours

---

## 📊 Monitoring & Metrics (TODO)

### Phase 5: Production Monitoring

- [ ] **Add Analytics**
  - [ ] Track app launch time
  - [ ] Track chat list load time
  - [ ] Track message send success rate
  - [ ] Track queue size (avg/max)
  - [ ] Track sync failure rate

- [ ] **User Feedback**
  - [ ] Survey: "Is the app faster now?"
  - [ ] Track "app is slow" complaints (should decrease)
  - [ ] Monitor Play Store ratings

- [ ] **Server Monitoring**
  - [ ] Monitor API response times
  - [ ] Monitor database query performance
  - [ ] Monitor bandwidth usage (should decrease)
  - [ ] Track number of batch vs individual calls

**Time**: Ongoing

---

## 📝 Documentation (COMPLETED ✅)

- [x] `OFFLINE_IMPLEMENTATION.md` - Main documentation
- [x] `IMPLEMENTATION_SUMMARY.md` - Summary of changes
- [x] `ARCHITECTURE_DIAGRAM.md` - Visual architecture
- [x] `lib/core/integration_guide.dart` - Code examples
- [x] This checklist file

---

## 🎯 Success Criteria

After implementation, verify these metrics:

- [ ] App launch time < 500ms (target: <300ms)
- [ ] Chat list load < 100ms
- [ ] Chat open time < 100ms
- [ ] Message send success rate > 99%
- [ ] Sync failure rate < 1%
- [ ] Batch API usage > 90% (vs individual calls)
- [ ] User complaints about "slow app" decreased by 80%
- [ ] Play Store rating improved by 0.3+ stars

---

## 🚀 Deployment Checklist

- [ ] **Pre-Deployment**
  - [ ] All tests passing
  - [ ] Code reviewed
  - [ ] Backend APIs deployed to staging
  - [ ] Flutter app tested on staging
  - [ ] Performance benchmarks met

- [ ] **Backend Deployment**
  - [ ] Deploy to production server
  - [ ] Run database migrations
  - [ ] Test all 6 APIs manually
  - [ ] Monitor server logs for errors

- [ ] **Flutter Deployment**
  - [ ] Update version to 1.0.24
  - [ ] Build release APK/AAB
  - [ ] Test on physical devices (Android/iOS)
  - [ ] Upload to Play Store (internal testing)
  - [ ] Roll out to 10% users
  - [ ] Monitor crashes/errors
  - [ ] Roll out to 100% if stable

- [ ] **Post-Deployment**
  - [ ] Monitor analytics for 7 days
  - [ ] Check user feedback
  - [ ] Fix any critical bugs
  - [ ] Document lessons learned

---

## 📞 Support Contacts

| Role | Name | Contact |
|------|------|---------|
| Flutter Developer | [Your Name] | [Email/Phone] |
| Backend Developer | [Name] | [Email/Phone] |
| QA Lead | [Name] | [Email/Phone] |
| DevOps | [Name] | [Email/Phone] |

---

## 📅 Timeline

| Phase | Duration | Start Date | End Date | Status |
|-------|----------|------------|----------|--------|
| Flutter Client | 1 day | - | - | ✅ DONE |
| Backend APIs | 1 day | - | - | ⏳ PENDING |
| Integration | 0.5 day | - | - | ⏳ PENDING |
| Testing | 1 day | - | - | ⏳ PENDING |
| Deployment | 0.5 day | - | - | ⏳ PENDING |
| **Total** | **4 days** | - | - | **25% Complete** |

---

## 🎉 Project Status

```
╔══════════════════════════════════════════════════════════╗
║                   IMPLEMENTATION STATUS                   ║
╠══════════════════════════════════════════════════════════╣
║                                                           ║
║  Flutter Client:    ████████████████████████  100%  ✅   ║
║  Backend APIs:      ░░░░░░░░░░░░░░░░░░░░░░░░   0%  ⏳   ║
║  Integration:       ░░░░░░░░░░░░░░░░░░░░░░░░   0%  ⏳   ║
║  Testing:           ░░░░░░░░░░░░░░░░░░░░░░░░   0%  ⏳   ║
║                                                           ║
║  Overall Progress:  ██████░░░░░░░░░░░░░░░░░░  25%        ║
║                                                           ║
╚══════════════════════════════════════════════════════════╝
```

**Next Action**: Implement backend APIs (6-8 hours)

---

## 📌 Quick Reference

### Key Files to Modify
- `lib/shared/providers/chat_provider.dart` - Add sync service
- `lib/features/home/home_screen.dart` - Add instant loading
- `lib/features/chat/chat_screen.dart` - Add offline queue
- `main.dart` - Initialize services

### Key Commands
```bash
# Run tests
flutter test

# Check performance
flutter run --profile

# Build release
flutter build apk --release

# Check code
flutter analyze
```

### Helpful Debug Commands
```dart
// Print queue status
DebugUtils.printQueueStatus();

// Clear queue (testing only)
await OfflineQueueService.clearQueue();

// Force full resync
await syncService.forceFullResync();
```

---

**Last Updated**: [Current Date]
**Version**: 1.0
**Status**: ✅ Flutter Complete | ⏳ Backend Pending

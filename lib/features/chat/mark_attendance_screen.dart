import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../core/models/message_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_realtime_service.dart';
import '../../core/services/message_database_service.dart';
import '../../core/services/time_service.dart';
import '../../core/utils/chat_utils.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final String groupId;
  final ApiService apiService;

  const MarkAttendanceScreen({
    super.key,
    required this.groupId,
    required this.apiService,
  });

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  final TextEditingController _remarkController = TextEditingController();
  bool _isLoading = true;
  bool _canClockIn = false;
  bool _canClockOut = false;
  String? _lastAction;
  String? _lastActionAt;
  String? _errorMessage;
  bool _isSubmitting = false;
  DateTime? _currentTime;

  @override
  void initState() {
    super.initState();
    _loadTodayStatus();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadTodayStatus() async {
    try {
      _currentTime = await TimeService.getCurrentTime();
      final response = await widget.apiService.getTodayAttendanceStatus(
        int.parse(widget.groupId),
      );
      
      setState(() {
        _canClockIn = response['can_clockin'] ?? false;
        _canClockOut = response['can_clockout'] ?? false;
        _lastAction = response['last_action'];
        _lastActionAt = response['last_action_at'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load attendance status';

        _isLoading = false;
      });
    }
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are disabled. Please enable location.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage.toString(),style: TextStyle(color: Colors.white),),
            backgroundColor: Colors.red, // 👈 Change background color
          ),
        );
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permission denied. Please grant permission.';
          });
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Location permission permanently denied. Enable in settings.';
        });
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Location error: ${e.toString()}';
      });
      return null;
    }
  }

  Future<void> _markAttendance(String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              action == 'clockin' ? Icons.login : Icons.logout,
              color: action == 'clockin' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Text(
              action == 'clockin' ? 'Clock In' : 'Clock Out',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to ${action == 'clockin' ? 'clock in' : 'clock out'}?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('hh:mm a').format(_currentTime ?? DateTime.now()),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'clockin' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(action == 'clockin' ? 'Clock In' : 'Clock Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final position = await _getCurrentLocation();
    if (position == null) {
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    try {
      final responseData = await widget.apiService.markAttendance(
        groupId: int.parse(widget.groupId),
        action: action,
        latitude: position.latitude,
        longitude: position.longitude,
        remark: _remarkController.text.toString().trim(),
      );

      // Sync the attendance message to Firebase + SQLite immediately
      unawaited(_syncAttendanceMessage(responseData));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {

        _errorMessage = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage.toString(),style: TextStyle(color: Colors.white),),
            backgroundColor: Colors.red, // 👈 Change background color
          ),
        );
        _isSubmitting = false;
      });
    }
  }

  /// Syncs the attendance message returned by the API into Firebase + SQLite
  /// so it appears instantly in the attendance group chat (attendanceGroup=true path).
  /// Syncs the attendance message from the API response into Firebase + SQLite
  /// using the same write path as chat_screen.dart for consistency.
  Future<void> _syncAttendanceMessage(Map<String, dynamic> responseData) async {
    try {
      // New API response IS the message object directly
      final msgId = responseData['id']?.toString();
      if (msgId == null || msgId.isEmpty) return;

      final groupId = widget.groupId;
      final senderId = responseData['sender_id']?.toString() ??
          (responseData['sender'] as Map?)?['id']?.toString() ?? '';
      final senderName =
          (responseData['sender'] as Map?)?['name']?.toString() ?? '';
      final content = responseData['content']?.toString() ??
          responseData['text']?.toString() ?? '';
      final type = responseData['type']?.toString() ?? 'text';
      final fileUrl = responseData['file_url']?.toString();

      // Parse timestamp from created_at
      final createdAt = responseData['created_at']?.toString() ?? '';
      final timestamp =
          DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now();

      // Firebase path for attendance group: group_${groupId}true
      final firebaseChatId = ChatUtils.generateChatId(
        groupId,
        chatType: 'group',
        attendanceGroup: true,
      );

      // Build the exact same Firebase payload as FirebaseRealtimeService uses
      final firebasePayload = <String, dynamic>{
        'id': msgId,
        'msgId': msgId,
        'firebaseId': msgId,
        'chatId': groupId,
        'senderId': senderId,
        'sender_id': senderId,
        'senderName': senderName,
        'sender_name': senderName,
        'text': content,
        'content': content,
        'message': content,
        'type': type,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'status': {'default': 'sent'},
        if (fileUrl != null && fileUrl.isNotEmpty) 'file_url': fileUrl,
      };

      // Write to Firebase — message node + update chat metadata
      await Future.wait([
        FirebaseRealtimeService.database
            .ref('chats/$firebaseChatId/messages/$msgId')
            .set(firebasePayload),
        FirebaseRealtimeService.database
            .ref('chats/$firebaseChatId')
            .update({
          'lastMessage': firebasePayload,
          'updatedAt': ServerValue.timestamp,
        }),
      ]);

      // Build Message object and save to SQLite
      final message = Message(
        id: msgId,
        msgId: msgId,
        chatId: groupId,
        senderId: senderId,
        senderName: senderName,
        text: content,
        type: type,
        timestamp: timestamp,
        status: const {'default': 'sent'},
        firebaseId: msgId,
        fileUrl: fileUrl,
      );
      await MessageDatabaseService().saveMessages([message], groupId, 'group');

      debugPrint('✅ Attendance message $msgId synced → $firebaseChatId');
    } catch (e) {
      debugPrint('❌ _syncAttendanceMessage error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _loadTodayStatus();
            },
            child:

     _isLoading || _isSubmitting ?
    Center(
      child: Container(
        color: Colors.black26,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    ) :  SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 48,
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            DateFormat('hh:mm a').format(_currentTime ?? DateTime.now()),

                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            DateFormat('EEEE, MMMM d, y').format(_currentTime ?? DateTime.now()),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_lastAction != null && _lastActionAt != null)
                    Card(
                      color: Colors.green.shade200,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Last Action',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_lastAction!.toUpperCase()} at $_lastActionAt',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _canClockIn && !_isSubmitting
                              ? () => _markAttendance('clockin')
                              : null,
                          icon: const Icon(Icons.login),
                          label: const Text('Clock In'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[500],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _canClockOut && !_isSubmitting
                              ? () => _markAttendance('clockout')
                              : null,
                          icon: const Icon(Icons.logout),
                          label: const Text('Clock Out'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[500],
                            // disabledBackgroundColor: Colors.grey[300],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _remarkController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Remark (Optional)',
                      hintText: 'Enter any remarks...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_isLoading || _isSubmitting)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

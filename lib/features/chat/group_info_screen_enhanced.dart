import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/chat_model.dart';
import '../../core/constants/enums.dart';
import '../../shared/widgets/profile_image_widget.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final Chat group;

  const GroupInfoScreen({super.key, required this.group});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
        backgroundColor: const Color(0xFF1dab61),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Group Header
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                // Group Image
                ProfileImageWidget(
                  imageUrl: widget.group.groupImage,
                  userName: widget.group.groupName ?? 'Group',
                  role: 'admin',
                  radius: 50,
                ),
                const SizedBox(height: 16),
                // Group Name
                Text(
                  widget.group.groupName ?? 'Group Chat',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Group Description
                if (widget.group.groupDescription != null)
                  Text(
                    widget.group.groupDescription!,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 8),
                // Member Count
                Text(
                  '${widget.group.participants.length} members',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          // Group Actions
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications, color: Color(0xFF1dab61)),
                  title: const Text('Mute notifications'),
                  trailing: Switch(
                    value: false, // TODO: Implement mute functionality
                    onChanged: (value) {
                      // TODO: Handle mute toggle
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.wallpaper, color: Color(0xFF1dab61)),
                  title: const Text('Wallpaper'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Navigate to wallpaper selection
                  },
                ),
              ],
            ),
          ),

          // Members Section
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Members',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1dab61),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.group.participants.length,
                      itemBuilder: (context, index) {
                        final participantId = widget.group.participants[index];
                        return _buildMemberTile(participantId);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(String participantId) {
    // TODO: Fetch user details from provider
    return ListTile(
      leading: ProfileImageWidget(
        userName: 'User $participantId',
        role: 'parent',
        radius: 20,
      ),
      title: Text('User $participantId'),
      subtitle: const Text('Online'), // TODO: Show actual online status
      trailing: widget.group.groupRoles?[participantId] == 'admin'
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1dab61),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            )
          : null,
      onTap: () {
        // TODO: Show member options (admin only)
      },
    );
  }
}

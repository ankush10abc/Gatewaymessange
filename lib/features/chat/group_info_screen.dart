import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/models/chat_model.dart';
import '../../core/models/user_model.dart';
import '../../shared/providers/auth_provider.dart';

class GroupInfoScreen extends ConsumerWidget {
  final Chat groupChat;
  final List<User> members;

  const GroupInfoScreen({
    super.key,
    required this.groupChat,
    required this.members,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).user!;
    final isAdmin = groupChat.isUserAdmin(currentUser.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _editGroup(context);
                    break;
                  case 'delete':
                    _deleteGroup(context);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Group')),
                const PopupMenuItem(value: 'delete', child: Text('Delete Group')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Group Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: groupChat.groupImage != null
                      ? CachedNetworkImageProvider(groupChat.groupImage!)
                      : null,
                  child: groupChat.groupImage == null
                      ? Icon(Icons.group, size: 50, color: Colors.grey[600])
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  groupChat.groupName ?? 'Group',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                if (groupChat.groupDescription?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    groupChat.groupDescription!,
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Created ${_formatDate(groupChat.createdAt)}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(),

          // Members Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        'Members (${members.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1dab61),
                        ),
                      ),
                      const Spacer(),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.person_add),
                          onPressed: () => _addMembers(context),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final memberRole = groupChat.groupRoles?[member.id] ?? 'member';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey[300],
                          backgroundImage: member.profilePicture != null
                              ? CachedNetworkImageProvider(member.profilePicture!)
                              : null,
                          child: member.profilePicture == null
                              ? Text(member.name[0].toUpperCase())
                              : null,
                        ),
                        title: Text(member.name),
                        subtitle: Text(_getRoleDisplayName(member.role)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (memberRole == 'admin')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1dab61),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Admin',
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            if (isAdmin && member.id != currentUser.id)
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'make_admin':
                                      _makeAdmin(member.id);
                                      break;
                                    case 'remove':
                                      _removeMember(member.id);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (memberRole != 'admin')
                                    const PopupMenuItem(value: 'make_admin', child: Text('Make Admin')),
                                  const PopupMenuItem(value: 'remove', child: Text('Remove')),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'admin': return 'Administrator';
      case 'teacher': return 'Teacher';
      case 'parent': return 'Parent';
      default: return role.toUpperCase();
    }
  }

  void _editGroup(BuildContext context) {
    // Navigate to group edit screen
  }

  void _deleteGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text('Are you sure you want to delete this group? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Delete group logic
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _addMembers(BuildContext context) {
    // Navigate to add members screen
  }

  void _makeAdmin(String userId) {
    // Make user admin logic
  }

  void _removeMember(String userId) {
    // Remove member logic
  }
}

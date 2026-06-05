import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../core/models/user_model.dart';

class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  _GroupCreateScreenState createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<User> _selectedUsers = [];
  final List<User> _availableUsers = [];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter group name')),
      );
      return;
    }

    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    final currentUser = ref.read(authProvider).user!;
    final members = [currentUser.id, ..._selectedUsers.map((u) => u.id)];

    try {
      final chatId = await ref.read(chatProvider.notifier).createGroupChat(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        members: members,
        creatorId: currentUser.id,
      );

      context.go('/chat/$chatId');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          TextButton(
            onPressed: _createGroup,
            child: const Text(
              'CREATE',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Group Info Section
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey[300],
                      child: Icon(Icons.group, size: 30, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              hintText: 'Group name',
                              border: UnderlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              hintText: 'Group description (optional)',
                              border: UnderlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),

          // Selected Members
          if (_selectedUsers.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Members (${_selectedUsers.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1dab61),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _selectedUsers.map((user) => Chip(
                      label: Text(user.name),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() {
                          _selectedUsers.remove(user);
                        });
                      },
                    )).toList(),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],

          // Available Users
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add Members',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1dab61),
                    ),
                  ),
                ),
                ..._availableUsers.map((user) => CheckboxListTile(
                  value: _selectedUsers.contains(user),
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        _selectedUsers.add(user);
                      } else {
                        _selectedUsers.remove(user);
                      }
                    });
                  },
                  title: Text(user.name),
                  subtitle: Text(_getRoleDisplayName(user.role)),
                  secondary: CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    child: Text(
                      user.name[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  activeColor: const Color(0xFF1dab61),
                )),
              ],
            ),
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

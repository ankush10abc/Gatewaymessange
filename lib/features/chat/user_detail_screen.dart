import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../app/theme/app_theme.dart';

class UserDetailScreen extends StatelessWidget {
  final String userId;
  final String userName;
  final String? userImage;
  final String? userDescription;
  final String? userRole;
  final String? userPhone;
  final String? userEmail;
  final int? member_count;
  final String? imageUrl;
  final bool isGroup;
  final DateTime? lastSeen;
  final bool isOnline;
  final List<dynamic>? memberList;

  const UserDetailScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userImage,
    this.userDescription,
    this.userRole,
    this.userPhone,
    this.userEmail,
    this.member_count,
    this.imageUrl,
    this.isGroup = false,
    this.lastSeen,
    this.isOnline = false,
    this.memberList,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // App Bar with Profile Image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: const Color(0xFF1dab61),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1dab61),  AppTheme.whatsAppTeal],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    // Profile Picture with Hero Animation
                    Hero(
                      tag: 'profile_$userId',
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 70,
                          backgroundColor: Colors.white,
                          backgroundImage: userImage != null
                              ? CachedNetworkImageProvider(userImage!)
                              : null,
                          child: userImage == null
                              ? Icon(
                                  isGroup ? Icons.group : Icons.person,
                                  size: 70,
                                  color: Colors.grey[400],
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Name
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if(isGroup)
                    Text(
                      '${member_count} members',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Status
                    if (!isGroup)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey[600],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOnline ? 'Online' : _getLastSeenText(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Quick Actions
                  // _buildQuickActions(context),
                  const SizedBox(height: 20),
                  
                  // Information Cards
                  if (userDescription != null && userDescription!.isNotEmpty)
                    _buildInfoCard(
                      'About',
                      userDescription!,
                      Icons.info_outline,
                    ),
                  
                  if (isGroup && memberList != null && memberList!.isNotEmpty)
                    _buildMembersList(),
                  
                  if (userRole != null)
                    _buildInfoCard(
                      'Role',
                      _getRoleDisplayName(userRole!),
                      Icons.work_outline,
                    ),
                  
                  if (userPhone != null)
                    _buildInfoCard(
                      'Phone',
                      userPhone!,
                      Icons.phone_outlined,
                      onTap: () => _makeCall(userPhone!),
                    ),
                  
                  if (userEmail != null)
                    _buildInfoCard(
                      'Email',
                      userEmail!,
                      Icons.email_outlined,
                      onTap: () => _sendEmail(userEmail!),
                    ),
                  
                  // _buildInfoCard(
                  //   isGroup ? 'Group ID' : 'User ID',
                  //   userId,
                  //   Icons.tag,
                  // ),
                  
                  const SizedBox(height: 20),
                  
                  // Additional Actions
                  // _buildActionButtons(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!isGroup) ...[
            _buildActionButton(
              Icons.call,
              'Call',
              const Color(0xFF1dab61),
              () => _makeCall(userPhone ?? ''),
            ),
            _buildActionButton(
              Icons.videocam,
              'Video',
              const Color(0xFF1976D2),
              () => _makeVideoCall(),
            ),
          ],
          _buildActionButton(
            Icons.search,
            'Search',
            const Color(0xFFFF9800),
            () => _searchInChat(context),
          ),
          _buildActionButton(
            Icons.more_horiz,
            'More',
            const Color(0xFF9C27B0),
            () => _showMoreOptions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String content,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1dab61).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFF1dab61),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        if (!isGroup) ...[
          _buildFullWidthButton(
            'Block Contact',
            Icons.block,
            Colors.red,
            () => _blockContact(context),
          ),
          const SizedBox(height: 12),
        ],
        _buildFullWidthButton(
          isGroup ? 'Leave Group' : 'Delete Chat',
          isGroup ? Icons.exit_to_app : Icons.delete_outline,
          Colors.red,
          () => _deleteChat(context),
        ),
      ],
    );
  }

  Widget _buildFullWidthButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getLastSeenText() {
    if (lastSeen == null) return 'Last seen recently';
    final now = DateTime.now();
    final difference = now.difference(lastSeen!);
    
    if (difference.inMinutes < 1) return 'Last seen just now';
    if (difference.inHours < 1) return 'Last seen ${difference.inMinutes}m ago';
    if (difference.inDays < 1) return 'Last seen ${difference.inHours}h ago';
    return 'Last seen ${difference.inDays}d ago';
  }

  String _getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'admin': return 'Administrator';
      case 'teacher': return 'Teacher';
      case 'parent': return 'Parent';
      case 'student': return 'Student';
      default: return role.toUpperCase();
    }
  }

  void _makeCall(String phone) {
    // Implement call functionality
  }

  void _makeVideoCall() {
    // Implement video call functionality
  }

  void _sendEmail(String email) {
    // Implement email functionality
  }

  void _searchInChat(BuildContext context) {
    // Implement search in chat functionality
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share Contact'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Add to Favorites'),
              onTap: () => Navigator.pop(context),
            ),
            if (!isGroup)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Contact'),
                onTap: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }

  void _blockContact(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block Contact'),
        content: Text('Are you sure you want to block $userName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isGroup ? 'Leave Group' : 'Delete Chat'),
        content: Text(
          isGroup
              ? 'Are you sure you want to leave this group?'
              : 'Are you sure you want to delete this chat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              isGroup ? 'Leave' : 'Delete',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1dab61).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.group,
                    color: Color(0xFF1dab61),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${memberList!.length} Members',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: memberList!.length,
            itemBuilder: (context, index) {
              final member = memberList![index];
              return ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: member['profile_picture'] != null
                      ? CachedNetworkImageProvider(member['profile_picture'])
                      : null,
                  child: member['profile_picture'] == null
                      ? Icon(Icons.person, color: Colors.grey[600])
                      : null,
                ),
                title: Text(
                  member['name'] ?? 'Unknown',
                  style:  TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16, color: Colors.grey[900],
                  ),
                ),
                subtitle: Text(
                  _getRoleDisplayName(member['role'] ?? ''),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                trailing: member['is_online'] == true
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
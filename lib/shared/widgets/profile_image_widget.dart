import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfileImageWidget extends StatelessWidget {
  final String? imageUrl;
  final String userName;
  final String role;
  final double radius;
  final VoidCallback? onTap;

  const ProfileImageWidget({
    super.key,
    this.imageUrl,
    required this.userName,
    required this.role,
    this.radius = 25,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _getColorByRole(role),
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _buildDefaultIcon(),
                  errorWidget: (context, url, error) => _buildDefaultIcon(),
                ),
              )
            : _buildDefaultIcon(),
      ),
    );
  }

  Widget _buildDefaultIcon() {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: _getColorByRole(role),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getInitials(userName),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.6,
          ),
        ),
      ),
    );
  }

  Color _getColorByRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const Color(0xFF2196F3); // Blue for admin
      case 'teacher':
        return const Color(0xFF4CAF50); // Green for teacher
      case 'parent':
        return const Color(0xFFFF9800); // Orange for parent
      default:
        return const Color(0xFF9E9E9E); // Grey for unknown
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    final words = name.trim().split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    } else {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
  }
}

class RoleBasedProfileIcon extends StatelessWidget {
  final String role;
  final double size;

  const RoleBasedProfileIcon({
    super.key,
    required this.role,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getColorByRole(role),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _getIconByRole(role),
        color: Colors.white,
        size: size * 0.6,
      ),
    );
  }

  Color _getColorByRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const Color(0xFF2196F3);
      case 'teacher':
        return const Color(0xFF4CAF50);
      case 'parent':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _getIconByRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'teacher':
        return Icons.school;
      case 'parent':
        return Icons.family_restroom;
      default:
        return Icons.person;
    }
  }
}

class ProfileImagePicker extends StatelessWidget {
  final String? currentImageUrl;
  final String userName;
  final String role;
  final Function(String) onImageSelected;
  final double radius;

  const ProfileImagePicker({
    super.key,
    this.currentImageUrl,
    required this.userName,
    required this.role,
    required this.onImageSelected,
    this.radius = 50,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ProfileImageWidget(
          imageUrl: currentImageUrl,
          userName: userName,
          role: role,
          radius: radius,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => _showImagePicker(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1dab61),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showImagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Change Profile Picture',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _pickFromCamera();
                  },
                ),
                _buildOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickFromGallery();
                  },
                ),
                if (currentImageUrl != null)
                  _buildOption(
                    icon: Icons.delete,
                    label: 'Remove',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      onImageSelected('');
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color ?? const Color(0xFF1dab61),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _pickFromCamera() {
    // Implement camera picking
    // This would use ImagePicker.pickImage(source: ImageSource.camera)
  }

  void _pickFromGallery() {
    // Implement gallery picking
    // This would use ImagePicker.pickImage(source: ImageSource.gallery)
  }
}

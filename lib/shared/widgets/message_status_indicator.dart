// import 'package:flutter/material.dart';
// import '../../core/models/message_model.dart';
//
// class MessageStatusIndicator extends StatelessWidget {
//   final Message message;
//   final List<String> participants;
//
//   const MessageStatusIndicator({
//     super.key,
//     required this.message,
//     required this.participants,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final status = message.getDisplayStatus(participants);
//
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Icon(
//           _getStatusIcon(status),
//           size: 16,
//           color: _getStatusColor(status),
//         ),
//       ],
//     );
//   }
//
//   IconData _getStatusIcon(String status) {
//     switch (status) {
//       case 'sent':
//         return Icons.check; // Single tick
//       case 'delivered':
//         return Icons.done_all; // Double tick
//       case 'read':
//         return Icons.done_all; // Blue double tick
//       default:
//         return Icons.access_time; // Clock for sending
//     }
//   }
//
//   Color _getStatusColor(String status) {
//     switch (status) {
//       case 'sent':
//         return Colors.grey;
//       case 'delivered':
//         return Colors.grey;
//       case 'read':
//         return Colors.blue;
//       default:
//         return Colors.grey;
//     }
//   }
// }
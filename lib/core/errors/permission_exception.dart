class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);
  @override
  String toString() => 'PermissionException: $message';
}
enum UserRole {
  admin,
  teacher,
  parent,
}

enum MessageType {
  text,
  image,
  video,
  file,
  audio,
}

enum MessageStatus {
  sent,
  delivered,
  read,
}

enum OnlineStatus {
  online,
  offline,
  away,
}

enum ChatType {
  private,
  group,
}

enum BookingStatus {
  pending,
  confirmed,
  cancelled,
  completed,
}

enum PaymentStatus {
  pending,
  paid,
  failed,
  refunded,
}

enum LoadingState {
  idle,
  loading,
  success,
  error,
}

enum PaymentMethod {
  cash,
  card,
  online,
  wallet,
}
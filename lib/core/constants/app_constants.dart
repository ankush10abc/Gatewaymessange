class AppConstants {
  static const String appName = 'Gateway Messenger';
  static const String baseUrl = 'https://your-api-url.com/api';
  
  // Firebase Collections
  static const String usersCollection = 'users';
  static const String chatsCollection = 'chats';
  static const String messagesCollection = 'messages';
  static const String groupsCollection = 'groups';
  
  // User Roles
  static const String adminRole = 'admin';
  static const String teacherRole = 'teacher';
  static const String parentRole = 'parent';
  
  // Message Types
  static const String textMessage = 'text';
  static const String imageMessage = 'image';
  static const String fileMessage = 'file';
  static const String videoMessage = 'video';
  
  // Message Status
  static const String sentStatus = 'sent';
  static const String deliveredStatus = 'delivered';
  static const String readStatus = 'read';
  
  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String keyToken = 'auth_token';
  static const String userKey = 'user_data';
  static const String keyUserId = 'user_id';
  static const String keyUserType = 'user_type';
  static const String themeKey = 'theme_mode';
  
  // Hive Boxes
  static const String boxServices = 'services';
  static const String boxBookings = 'bookings';
  static const String boxCache = 'cache';
  
  // API Endpoints
  static const String epLogin = '/login';
  static const String epRegister = '/register';
  static const String epLogout = '/logout';
  static const String epProfile = '/profile';
  static const String epBookings = '/bookings';
  
  // Validation
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 50;
  static const int maxMessageLength = 1000;
  
  // File Upload
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'gif'];
  static const List<String> allowedFileTypes = ['pdf', 'doc', 'docx', 'txt'];
}
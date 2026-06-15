import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/chat/chat_deep_linking_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chat_selection_screen.dart';
import '../../features/chat/group_create_screen.dart';
import '../../features/chat/group_info_screen_enhanced.dart';
import '../../features/chat/media_viewer_screen_enhanced.dart';
import '../../features/chat/document_preview_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/common/no_internet_screen.dart';
import '../../core/models/chat_hive_model.dart';
import '../../core/models/chat_model.dart';
import '../../shared/providers/auth_provider.dart';

final routerProvider = StateNotifierProvider<GoRouterNotifier, GoRouter>((ref) {
  return GoRouterNotifier(ref);
});

class GoRouterNotifier extends StateNotifier<GoRouter> {
  final Ref _ref;

  GoRouterNotifier(this._ref) : super(_createRouter(_ref)) {
    _ref.listen(authProvider, (previous, next) {
      state.refresh();
    });
  }

  static GoRouter _createRouter(Ref ref) {
    return GoRouter(
      initialLocation: '/splash',
      redirect: (context, state) {
        final authState = ref.read(authProvider);

        // If auth is still loading, stay on splash
        if (authState.isLoading) {
          return state.fullPath == '/splash' ? null : '/splash';
        }

        final isLoggedIn = authState.isAuthenticated;
        final isOnLogin = state.fullPath == '/login';
        final isOnSplash = state.fullPath == '/splash';

        // If not logged in, redirect to login (except if already on login)
        if (!isLoggedIn && !isOnLogin) {
          return '/login';
        }

        // If logged in, redirect to home (except if already on a protected route)
        if (isLoggedIn && (isOnLogin || isOnSplash)) {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) => '/home',
        ),
        GoRoute(
          path: '/splash',
          builder: (context, state) => SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => HomeScreen(),
        ),
        GoRoute(
          path: '/chat/:chatId',
          builder: (context, state) {
            final chatId = state.pathParameters['chatId']!;
            final type = state.uri.queryParameters['type'] ?? 'user';
            final name = state.uri.queryParameters['name'] ?? 'Chat';
            final message = state.uri.queryParameters['message'];
            final attendanceGroup = ChatHiveModel.parseAttendanceGroup(
              state.uri.queryParameters['attendance_group'],
            );

            return ChatScreen(
              chatId: chatId,
              chatType: type,
              chatName: name,
              initialMessage: message,
              attendance_group: attendanceGroup,
            );
          },
        ),
        GoRoute(
          path: '/chat-selectionold',
          builder: (context, state) {
            debugPrint(
                'Deep link received:_checkPendingDeepLink ${state.uri.queryParameters['message']}');
            final message = state.uri.queryParameters['message'] ?? '';
            return ChatSelectionScreen(message: message);
          },
        ),
        GoRoute(
          path: '/chat-selection',
          builder: (context, state) {
            debugPrint(
                'Deep link received:_checkPendingDeepLink ${state.uri.queryParameters['message']}');
            final message = state.uri.queryParameters['message'] ?? '';
            return ChatDeepLinkingScreen(message: message);
          },
        ),
        GoRoute(
          path: '/send/app',
          redirect: (context, state) {
            final message = state.uri.queryParameters['message'];
            if (message != null) {
              return '/chat-selection?message=${Uri.encodeComponent(message)}';
            }
            return '/home';
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => ProfileScreen(),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => SearchScreen(),
        ),
        GoRoute(
          path: '/group/create',
          builder: (context, state) => GroupCreateScreen(),
        ),
        GoRoute(
          path: '/media/:type/:url',
          builder: (context, state) {
            final type = state.pathParameters['type']!;
            final url = state.pathParameters['url']!;
            return MediaViewerScreen(
              mediaUrl: Uri.decodeComponent(url),
              mediaType: type,
            );
          },
        ),
        GoRoute(
          path: '/group/info/:groupId',
          builder: (context, state) {
            final groupId = state.pathParameters['groupId']!;
            return GroupInfoScreen(
              group: Chat(
                id: groupId,
                type: 'group',
                participants: [],
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                unreadCount: {},
                groupName: 'Group',
              ),
            );
          },
        ),
        GoRoute(
          path: '/no-internet',
          builder: (context, state) => const NoInternetScreen(),
        ),
        GoRoute(
          path: '/document/:url/:fileName',
          builder: (context, state) {
            final url = Uri.decodeComponent(state.pathParameters['url']!);
            final fileName =
                Uri.decodeComponent(state.pathParameters['fileName']!);
            return DocumentPreviewScreen(
              documentUrl: url,
              fileName: fileName,
            );
          },
        ),
      ],
    );
  }
}

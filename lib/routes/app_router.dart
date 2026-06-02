import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/storage/storage_service.dart';
import '../features/auth/views/login_view.dart';
import '../features/home/home_screen.dart';
import '../features/user/views/user_dashboard_view.dart';
import '../features/agent/views/agent_dashboard_view.dart';

class AppRouter {
  final StorageService _storageService;

  AppRouter(this._storageService);

  late final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final isLoggedIn = await _storageService.getToken() != null;
      final userRole = await _storageService.getUserType();

      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      if (isLoggedIn && isLoginRoute) {
        return userRole == 'admin' ? '/agent' : '/user';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginView(),
      ),  GoRoute(
        path: '/home',
        builder: (context, state) =>  HomeScreen(),
      ),
      GoRoute(
        path: '/user',
        builder: (context, state) => const UserDashboardView(),
        routes: [
          GoRoute(
            path: 'bookings',
            builder: (context, state) => const Placeholder(), // UserBookingsView
          ),
          GoRoute(
            path: 'booking/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return const Placeholder(); // BookingDetailView(id)
            },
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const Placeholder(), // ProfileView
          ),
        ],
      ),
      GoRoute(
        path: '/agent',
        builder: (context, state) => const AgentDashboardView(),
        routes: [
          GoRoute(
            path: 'bookings',
            builder: (context, state) => const Placeholder(), // AgentBookingsView
          ),
          GoRoute(
            path: 'services',
            builder: (context, state) => const Placeholder(), // ServicesView
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const Placeholder(), // ProfileView
          ),
        ],
      ),
    ],
  );
}

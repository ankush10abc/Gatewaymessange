import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/single_device_auth_service.dart';

class AppLifecycleManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppLifecycleManager({
    super.key,
    required this.child,
  });

  @override
  _AppLifecycleManagerState createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends ConsumerState<AppLifecycleManager>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SingleDeviceAuthService.navigatorKey = GlobalKey<NavigatorState>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // _validateTokenOnResume();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.detached:
        _onAppDetached();
        break;
      default:
        break;
    }
  }

  Future<void> _validateTokenOnResume() async {
    if (await SingleDeviceAuthService.hasToken()) {
      final isValid = await SingleDeviceAuthService.isTokenValid();
      if (!isValid) {
        await SingleDeviceAuthService.logout();

        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please login again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  void _onAppPaused() {
    // Save app state or perform cleanup when app goes to background
  }

  void _onAppDetached() {
    // Perform final cleanup when app is being terminated
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: SingleDeviceAuthService.navigatorKey,
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => widget.child,
        );
      },
    );
  }
}

class TokenValidationProvider extends StateNotifier<TokenValidationState> {
  TokenValidationProvider() : super(TokenValidationState.initial());

  Future<void> validateToken() async {
    state = state.copyWith(isValidating: true);

    try {
      if (await SingleDeviceAuthService.hasToken()) {
        final isValid = await SingleDeviceAuthService.isTokenValid();

        if (isValid) {
          state = state.copyWith(
            isValidating: false,
            isValid: true,
            isAuthenticated: true,
          );
        } else {
          await SingleDeviceAuthService.logout();
          state = state.copyWith(
            isValidating: false,
            isValid: false,
            isAuthenticated: false,
            error: 'Token expired',
          );
        }
      } else {
        state = state.copyWith(
          isValidating: false,
          isValid: false,
          isAuthenticated: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isValidating: false,
        error: e.toString(),
      );
    }
  }

  Future<void> logout() async {
    await SingleDeviceAuthService.logout();
    state = TokenValidationState.initial();
  }
}

class TokenValidationState {
  final bool isValidating;
  final bool isValid;
  final bool isAuthenticated;
  final String? error;

  TokenValidationState({
    required this.isValidating,
    required this.isValid,
    required this.isAuthenticated,
    this.error,
  });

  factory TokenValidationState.initial() {
    return TokenValidationState(
      isValidating: false,
      isValid: false,
      isAuthenticated: false,
    );
  }

  TokenValidationState copyWith({
    bool? isValidating,
    bool? isValid,
    bool? isAuthenticated,
    String? error,
  }) {
    return TokenValidationState(
      isValidating: isValidating ?? this.isValidating,
      isValid: isValid ?? this.isValid,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: error,
    );
  }
}

final tokenValidationProvider =
    StateNotifierProvider<TokenValidationProvider, TokenValidationState>((ref) {
  return TokenValidationProvider();
});

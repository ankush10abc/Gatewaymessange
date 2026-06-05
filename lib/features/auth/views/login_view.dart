import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/textfields/app_text_field.dart';
import '../../../core/widgets/dropdown/app_dropdown.dart';
import '../../../core/services/api_service_simple.dart';
import '../viewmodels/auth_viewmodel.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> with ValidationMixin {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _selectedUserType = UserRole.parent;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final viewModel = ref.read(authViewModelProvider.notifier);
    final success = await viewModel.login(LoginRequest(
      mobile: _mobileController.text.trim(),
      password: _passwordController.text,
    ));
    debugPrint("Ankush Banawade ${success}");
    if (success && mounted) {
      // Navigation handled by router
    } else if (mounted) {
      final authState = ref.read(authViewModelProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authState.errorMessage ?? 'Login failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDimensions.marginXL),
                Text(
                  'Welcome Back',
                  style: Theme.of(context).textTheme.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.marginS),
                Text(
                  'Login to your account',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.marginXL),
                AppDropdown<UserRole>(
                  label: 'Login as',
                  value: _selectedUserType,
                  items: UserRole.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedUserType = value!);
                  },
                ),
                const SizedBox(height: AppDimensions.marginM),
                AppTextField(
                  label: 'Mobile',
                  hint: 'Enter your mobile number',
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  validator: (value) => value?.isEmpty == true ? 'Mobile is required' : null,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                const SizedBox(height: AppDimensions.marginM),
                AppTextField(
                  label: 'Password',
                  hint: 'Enter your password',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  validator: validatePassword,
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppDimensions.marginL),
                Consumer(
                  builder: (context, ref, _) {
                    final viewModel = ref.watch(authViewModelProvider);
                    return AppButton(
                      text: 'Login',
                      onPressed: _handleLogin,
                      isLoading: viewModel.state == LoadingState.loading,
                    );
                  },
                ),
                const SizedBox(height: AppDimensions.marginM),
                TextButton(
                  onPressed: () {
                    // Navigate to register
                  },
                  child: const Text('Don\'t have an account? Register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api_service.dart';
import '../../../../core/design_system/app_colors.dart';
import '../../../../core/design_system/app_typography.dart';
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/input.dart';
import 'reset_password_screen.dart';
import '../../../../core/widgets/premises_loader.dart';

class VerifyResetOtpScreen extends StatefulWidget {
  final String email;
  const VerifyResetOtpScreen({super.key, required this.email});

  @override
  State<VerifyResetOtpScreen> createState() => _VerifyResetOtpScreenState();
}

class _VerifyResetOtpScreenState extends State<VerifyResetOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final otp = _otpController.text.trim();
      await ApiService.verifyResetOtp(widget.email, otp);
      
      if (!mounted) return;
      
      context.push('/forgot-password/reset', extra: {'email': widget.email, 'otp': otp});
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 48,
                            width: 48,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Verify Code',
                        style: AppTypography.h2,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'A 6-digit verification code has been sent to ${widget.email}. Please enter it below.',
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 32),
                      AppInput(
                        label: 'Verification Code',
                        hint: '6-digit OTP',
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        prefixIcon: Icons.lock_clock_outlined,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Code is required';
                          if (v.length != 6) return 'Enter a 6-digit code';
                          return null;
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 32),
                      AppButton(
                        text: 'Verify Code',
                        isLoading: _isLoading,
                        onPressed: _verify,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Change Email'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      if (_isLoading)
        Positioned.fill(
          child: Container(
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.55),
            child: const Center(
              child: PremisesBrandedLoader(size: 90),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

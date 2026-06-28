import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/input.dart';

// Registration mode chosen by the user
enum _RegistrationRole { admin, faculty }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // -----------------------------------------------------------------------
  // Multi-step state
  // -----------------------------------------------------------------------
  int _currentStep = 0;
  _RegistrationRole _selectedRole = _RegistrationRole.faculty;
  bool _isLoading = false;
  String? _errorMessage;

  // -----------------------------------------------------------------------
  // Admin flow controllers
  // -----------------------------------------------------------------------
  final _orgNameController = TextEditingController();
  String _selectedOrgType = 'University';
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _adminConfirmPasswordController = TextEditingController();
  bool _adminObscurePass = true;
  bool _adminObscureConfirm = true;

  // OTP Step (admin only)
  String? _pendingAdminEmail;
  final _otpController = TextEditingController();

  // -----------------------------------------------------------------------
  // Faculty flow controllers
  // -----------------------------------------------------------------------
  final _empOrgCodeController = TextEditingController();
  Map<String, dynamic>? _fetchedOrgDetails; // Set after org code lookup or domain detection
  bool _isFetchingOrg = false;
  bool _isAutoDetectingOrg = false;
  bool _isPublicEmail = false;
  Timer? _debounce;

  final _empNameController = TextEditingController();
  final _empEmailController = TextEditingController();
  final _empPasswordController = TextEditingController();
  final _empConfirmPasswordController = TextEditingController();
  bool _empObscurePass = true;
  bool _empObscureConfirm = true;
  String? _selectedDepartmentId;
  String? _selectedDepartmentName;

  void _onEmailChanged(String email) {
    if (_selectedRole != _RegistrationRole.faculty) return;
    email = email.trim().toLowerCase();
    if (!email.contains('@') || email.endsWith('@')) {
      setState(() {
        _fetchedOrgDetails = null;
        _isPublicEmail = false;
        _errorMessage = null;
      });
      return;
    }

    final domain = email.split('@').last;
    final publicDomains = {
      'gmail.com', 'googlemail.com', 'yahoo.com', 'yahoo.co.in', 'yahoo.co.uk', 'ymail.com',
      'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'zoho.com', 'zoho.in', 'proton.me', 'protonmail.com'
    };
    if (publicDomains.contains(domain)) {
      setState(() {
        _isPublicEmail = true;
        _fetchedOrgDetails = null;
        _errorMessage = 'Public email detected. Organization code required.';
      });
      return;
    }

    _autoDetectOrg(email);
  }

  void _autoDetectOrg(String email) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() {
        _isAutoDetectingOrg = true;
        _errorMessage = null;
        _isPublicEmail = false;
        _fetchedOrgDetails = null;
      });
      try {
        final details = await ApiService.orgLookup(email: email);
        setState(() {
          _fetchedOrgDetails = details;
          _errorMessage = null;
          // Set organization code in controller to ensure it goes to the backend during submission
          _empOrgCodeController.text = details['organization_code'] ?? '';
        });
      } on ApiException catch (e) {
        if (e.message.contains("Public email") || e.message.contains("code required")) {
          setState(() {
            _isPublicEmail = true;
            _fetchedOrgDetails = null;
            _errorMessage = 'Public email detected. Organization code required.';
          });
        } else if (e.message.contains("not configured") || e.message.contains("not found")) {
          setState(() {
            _isPublicEmail = true;
            _fetchedOrgDetails = null;
            _errorMessage = 'Organization domain not configured.';
          });
        } else {
          setState(() {
            _fetchedOrgDetails = null;
            _errorMessage = e.message;
          });
        }
      } catch (e) {
        setState(() {
          _fetchedOrgDetails = null;
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      } finally {
        if (mounted) setState(() => _isAutoDetectingOrg = false);
      }
    });
  }

  // -----------------------------------------------------------------------
  // Form keys
  // -----------------------------------------------------------------------
  final _roleFormKey = GlobalKey<FormState>();
  final _adminDetailsFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _orgCodeFormKey = GlobalKey<FormState>();
  final _empDetailsFormKey = GlobalKey<FormState>();

  final List<String> _orgTypes = [
    'University', 'College', 'School', 'Institute', 'Company', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _empEmailController.addListener(() {
      _onEmailChanged(_empEmailController.text);
    });
  }

  @override
  void dispose() {
    _orgNameController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _adminConfirmPasswordController.dispose();
    _otpController.dispose();
    _empOrgCodeController.dispose();
    _empNameController.dispose();
    _empEmailController.dispose();
    _empPasswordController.dispose();
    _empConfirmPasswordController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _setError(String? msg) => setState(() => _errorMessage = msg);

  // -----------------------------------------------------------------------
  // ADMIN FLOW ACTIONS
  // -----------------------------------------------------------------------
  Future<void> _submitAdminDetails() async {
    if (!_adminDetailsFormKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ApiService.registerAdmin(
        orgName: _orgNameController.text.trim(),
        orgType: _selectedOrgType,
        adminName: _adminNameController.text.trim(),
        email: _adminEmailController.text.trim(),
        password: _adminPasswordController.text,
      );
      _pendingAdminEmail = _adminEmailController.text.trim();
      setState(() => _currentStep = 2);
    } on ApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOtp() async {
    if (!_otpFormKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await ApiService.verifyOtp(
        email: _pendingAdminEmail!,
        otp: _otpController.text.trim(),
      );
      if (!mounted) return;
      _showRegistrationSuccessDialog(
        orgName: result['name'] ?? '',
        orgCode: result['organization_code'] ?? '',
        onDone: () => context.go('/login'),
      );
    } on ApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRegistrationSuccessDialog({
    required String orgName,
    required String orgCode,
    required VoidCallback onDone,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, size: 64, color: AppColors.success),
                  const SizedBox(height: 24),
                  Text(
                    'Organization Created!',
                    style: AppTypography.h2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your workspace is ready. Faculty can now join using the code below.',
                    style: AppTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          orgName,
                          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          orgCode,
                          style: AppTypography.h1.copyWith(
                            letterSpacing: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'This code has also been sent to your registered email address.',
                    style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: orgCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Organization Code copied successfully.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Code'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onDone();
                    },
                    child: const Text('Continue to Login'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // FACULTY FLOW ACTIONS
  // -----------------------------------------------------------------------
  Future<void> _lookupOrgCode() async {
    if (!_orgCodeFormKey.currentState!.validate()) return;
    setState(() { _isFetchingOrg = true; _errorMessage = null; _fetchedOrgDetails = null; });
    try {
      final details = await ApiService.getOrgDetails(_empOrgCodeController.text.trim());
      setState(() { _fetchedOrgDetails = details; });
    } on ApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isFetchingOrg = false);
    }
  }

  Future<void> _submitFacultyRegistration() async {
    if (!_empDetailsFormKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ApiService.registerFaculty(
        fullName: _empNameController.text.trim(),
        email: _empEmailController.text.trim(),
        password: _empPasswordController.text,
        organizationCode: _empOrgCodeController.text.trim(),
        departmentId: _selectedDepartmentId,
      );
      if (!mounted) return;
      _showSuccessDialog(
        title: 'Registration Submitted! ✅',
        message:
            'Registration submitted. Pending admin approval.\n\n'
            'Your registration request has been submitted to the admin of '
            '"${_fetchedOrgDetails?['organization_name'] ?? ''}"\n\n'
            'You will be notified once your account is approved.',
        onDone: () => context.go('/login'),
      );
    } on ApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog({
    required String title,
    required String message,
    required VoidCallback onDone,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: AppTypography.h3),
        content: Text(message, style: AppTypography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () { Navigator.of(ctx).pop(); onDone(); },
            child: const Text('Continue to Login'),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // STEP NAVIGATION
  // -----------------------------------------------------------------------
  void _onContinueFromRoleStep() {
    setState(() {
      _currentStep = 1;
      _errorMessage = null;
    });
  }

  void _goBack() {
    setState(() {
      _errorMessage = null;
      if (_currentStep > 0) _currentStep--;
    });
  }

  // -----------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: _currentStep == 0 ? () => context.pop() : _goBack,
          tooltip: 'Back',
        ),
        title: Text(_appBarTitle, style: AppTypography.h3),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Step progress indicator
                    _buildStepTracker(theme),
                    const SizedBox(height: 28),

                    // Step content
                    _buildCurrentStep(theme, isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _appBarTitle {
    switch (_currentStep) {
      case 0: return 'Create Account';
      case 1: return _selectedRole == _RegistrationRole.admin
          ? 'Organization Details'
          : 'Find Your Organization';
      case 2: return _selectedRole == _RegistrationRole.admin
          ? 'Verify Email OTP'
          : 'Complete Your Profile';
      default: return 'Register';
    }
  }

  Widget _buildCurrentStep(ThemeData theme, bool isDark) {
    // Step 0: Role selection
    if (_currentStep == 0) return _buildRoleStep(theme, isDark);

    // Admin path
    if (_selectedRole == _RegistrationRole.admin) {
      if (_currentStep == 1) return _buildAdminDetailsStep(theme, isDark);
      if (_currentStep == 2) return _buildOtpStep(theme, isDark);
    }

    // Faculty path
    if (_selectedRole == _RegistrationRole.faculty) {
      if (_currentStep == 1) return _buildOrgCodeStep(theme, isDark);
      if (_currentStep == 2) return _buildFacultyDetailsStep(theme, isDark);
    }

    return const SizedBox.shrink();
  }

  // -----------------------------------------------------------------------
  // STEP 0: Role Selection
  // -----------------------------------------------------------------------
  Widget _buildRoleStep(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Register As', style: AppTypography.h3),
        const SizedBox(height: 6),
        Text(
          'Select Faculty if you want to join an existing organization, or Admin if you are registering a new workspace.',
          style: AppTypography.caption.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 24),
        _buildRoleTile(
          role: _RegistrationRole.faculty,
          title: 'Faculty Member',
          description: 'Join an existing organization by entering an organization code.',
          icon: Icons.badge_outlined,
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        _buildRoleTile(
          role: _RegistrationRole.admin,
          title: 'Organization Admin',
          description: 'Register a new organization and set up your workspace.',
          icon: Icons.corporate_fare_outlined,
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 32),
        AppButton(text: 'Continue', onPressed: _onContinueFromRoleStep),
      ],
    );
  }

  Widget _buildRoleTile({
    required _RegistrationRole role,
    required String title,
    required String description,
    required IconData icon,
    required ThemeData theme,
    required bool isDark,
  }) {
    final isSelected = _selectedRole == role;
    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 26,
                color: isSelected ? theme.colorScheme.primary : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? theme.colorScheme.primary : null,
                      )),
                  const SizedBox(height: 4),
                  Text(description,
                      style: AppTypography.caption.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      )),
                ],
              ),
            ),
            Radio<_RegistrationRole>(
              value: role,
              groupValue: _selectedRole,
              activeColor: theme.colorScheme.primary,
              onChanged: (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // ADMIN STEP 1: Organization + Admin Details
  // -----------------------------------------------------------------------
  Widget _buildAdminDetailsStep(ThemeData theme, bool isDark) {
    return Form(
      key: _adminDetailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Organization Information', theme, isDark),
          const SizedBox(height: 12),
          AppInput(
            label: 'Organization Name',
            hint: 'e.g., Mauli College',
            controller: _orgNameController,
            prefixIcon: Icons.corporate_fare,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Organization name is required'
                : null,
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Organization Type',
            value: _selectedOrgType,
            items: _orgTypes,
            onChanged: (v) { if (v != null) setState(() => _selectedOrgType = v); },
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          _sectionLabel('Administrator Account', theme, isDark),
          const SizedBox(height: 12),
          AppInput(
            label: 'Full Name',
            hint: 'e.g., Jane Smith',
            controller: _adminNameController,
            prefixIcon: Icons.person_outline,
            validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Email Address',
            hint: 'e.g., admin@university.edu',
            controller: _adminEmailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Password',
            hint: 'Minimum 6 characters',
            controller: _adminPasswordController,
            isPassword: _adminObscurePass,
            prefixIcon: Icons.lock_outlined,
            suffixIcon: IconButton(
              icon: Icon(_adminObscurePass
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _adminObscurePass = !_adminObscurePass),
            ),
            validator: (v) => v == null || v.length < 6
                ? 'Password must be at least 6 characters'
                : null,
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Confirm Password',
            hint: 'Re-enter your password',
            controller: _adminConfirmPasswordController,
            isPassword: _adminObscureConfirm,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_adminObscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _adminObscureConfirm = !_adminObscureConfirm),
            ),
            validator: (v) => v != _adminPasswordController.text
                ? 'Passwords do not match'
                : null,
          ),
          _buildErrorBox(),
          const SizedBox(height: 24),
          AppButton(
            text: 'Send Verification OTP',
            isLoading: _isLoading,
            onPressed: _submitAdminDetails,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // ADMIN STEP 2: OTP Verification
  // -----------------------------------------------------------------------
  Widget _buildOtpStep(ThemeData theme, bool isDark) {
    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_read_outlined,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Check your email',
            style: AppTypography.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'A 6-digit verification code was sent to\n$_pendingAdminEmail',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Text(
              '🔧 Development Mode: Check the backend terminal for the OTP.',
              style: AppTypography.caption.copyWith(color: AppColors.warning),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Verification Code',
            hint: '6-digit OTP',
            controller: _otpController,
            keyboardType: TextInputType.number,
            prefixIcon: Icons.pin_outlined,
            validator: (v) {
              if (v == null || v.trim().length != 6) return 'Enter the 6-digit code';
              return null;
            },
          ),
          _buildErrorBox(),
          const SizedBox(height: 24),
          AppButton(
            text: 'Verify & Create Organization',
            isLoading: _isLoading,
            onPressed: _submitOtp,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _submitAdminDetails,
              child: Text('Resend OTP', style: TextStyle(color: theme.colorScheme.primary)),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // FACULTY STEP 1: Organization Code Lookup
  // -----------------------------------------------------------------------
  Widget _buildOrgCodeStep(ThemeData theme, bool isDark) {
    final departments = _fetchedOrgDetails != null
        ? (_fetchedOrgDetails!['departments'] as List<dynamic>)
        : <dynamic>[];

    return Form(
      key: _orgCodeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Find Your Organization', style: AppTypography.h3),
          const SizedBox(height: 6),
          Text(
            'Enter your college/organization email. We will automatically detect your organization.',
            style: AppTypography.caption.copyWith(
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 20),
          AppInput(
            label: 'Email Address',
            hint: 'e.g., john@saraswaticollege.edu',
            controller: _empEmailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email address';
              return null;
            },
          ),
          if (_isAutoDetectingOrg) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Searching organization...',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ],
          if (_fetchedOrgDetails == null && _isPublicEmail && !_isAutoDetectingOrg) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage ?? 'Public email detected. Organization code required.',
                      style: AppTypography.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppInput(
                    label: 'Organization Code',
                    hint: 'e.g., SARASWATI123',
                    controller: _empOrgCodeController,
                    prefixIcon: Icons.vpn_key_outlined,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Code is required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isFetchingOrg ? null : _lookupOrgCode,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
                      ),
                      child: _isFetchingOrg
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Find'),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_fetchedOrgDetails != null) ...[
            const SizedBox(height: 16),
            _buildOrgFoundCard(_fetchedOrgDetails!, departments, theme, isDark),
          ],
          _buildErrorBox(),
          const SizedBox(height: 24),
          if (_fetchedOrgDetails != null)
            AppButton(
              text: 'Continue',
              onPressed: () {
                if (_orgCodeFormKey.currentState!.validate()) {
                  setState(() => _currentStep = 2);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOrgFoundCard(
      Map<String, dynamic> org, List departments, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
            const SizedBox(width: 8),
            Text('Organization detected. Departments loaded.',
                style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.success, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          _infoRow(Icons.corporate_fare_outlined, 'Name', org['organization_name'] ?? ''),
          _infoRow(Icons.tag, 'Code', org['organization_code'] ?? ''),
          if (departments.isNotEmpty)
            _infoRow(Icons.people_outline, 'Departments', '${departments.length} available'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text('$label: ', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
        Text(value, style: AppTypography.caption),
      ]),
    );
  }

  // -----------------------------------------------------------------------
  // FACULTY STEP 2: Personal Details
  // -----------------------------------------------------------------------
  Widget _buildFacultyDetailsStep(ThemeData theme, bool isDark) {
    final departments = _fetchedOrgDetails != null
        ? (_fetchedOrgDetails!['departments'] as List<dynamic>)
        : <dynamic>[];

    return Form(
      key: _empDetailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Joining: ${_fetchedOrgDetails?['organization_name'] ?? ''}', theme, isDark),
          const SizedBox(height: 16),
          AppInput(
            label: 'Full Name',
            hint: 'e.g., Dr. John Doe',
            controller: _empNameController,
            prefixIcon: Icons.person_outline,
            validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Password',
            hint: 'Minimum 6 characters',
            controller: _empPasswordController,
            isPassword: _empObscurePass,
            prefixIcon: Icons.lock_outlined,
            suffixIcon: IconButton(
              icon: Icon(_empObscurePass
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _empObscurePass = !_empObscurePass),
            ),
            validator: (v) => v == null || v.length < 6
                ? 'Password must be at least 6 characters'
                : null,
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Confirm Password',
            hint: 'Re-enter your password',
            controller: _empConfirmPasswordController,
            isPassword: _empObscureConfirm,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_empObscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _empObscureConfirm = !_empObscureConfirm),
            ),
            validator: (v) => v != _empPasswordController.text
                ? 'Passwords do not match'
                : null,
          ),
          if (departments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDepartmentDropdown(departments, isDark),
          ],
          _buildErrorBox(),
          const SizedBox(height: 24),
          AppButton(
            text: 'Submit Registration Request',
            isLoading: _isLoading,
            onPressed: _submitFacultyRegistration,
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentDropdown(List departments, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Department',
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            )),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedDepartmentId,
          decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          hint: const Text('Select your department'),
          validator: (v) => v == null ? 'Department required.' : null,
          items: departments
              .map((d) => DropdownMenuItem<String>(
                    value: d['id'] as String,
                    child: Text(d['name'] as String),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedDepartmentId = val;
                _selectedDepartmentName = departments
                    .firstWhere((d) => d['id'] == val)['name'] as String?;
              });
            }
          },
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Shared Widgets
  // -----------------------------------------------------------------------
  Widget _buildStepTracker(ThemeData theme) {
    final int totalSteps = 3;
    final steps = _selectedRole == _RegistrationRole.admin
        ? ['Role', 'Details', 'Verify OTP']
        : ['Role', 'Find Org', 'Register'];

    return Row(
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIndex = i ~/ 2;
          final isComplete = _currentStep > stepIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: isComplete
                  ? theme.colorScheme.primary
                  : Colors.grey.shade300,
            ),
          );
        }

        final stepIndex = i ~/ 2;
        final isActive = _currentStep >= stepIndex;
        final isComplete = _currentStep > stepIndex;
        final label = steps[stepIndex];

        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete
                    ? AppColors.success
                    : (isActive
                        ? theme.colorScheme.primary
                        : Colors.grey.shade300),
              ),
              child: Center(
                child: isComplete
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '${stepIndex + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? null : Colors.grey,
                fontSize: 10,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildErrorBox() {
    if (_errorMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeData theme, bool isDark) {
    return Text(
      text,
      style: AppTypography.bodyLarge.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          items: items
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

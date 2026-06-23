import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/input.dart';
import '../../../core/session_manager.dart';

class FacultyProfileScreen extends StatefulWidget {
  const FacultyProfileScreen({super.key});

  @override
  State<FacultyProfileScreen> createState() => _FacultyProfileScreenState();
}

class _FacultyProfileScreenState extends State<FacultyProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  // Profile data
  Map<String, dynamic>? _profileData;

  // Controllers
  final _phoneController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _photoUrlController = TextEditingController();
  
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _photoUrlController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadProfile();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emergencyController.dispose();
    _photoUrlController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final data = await ApiService.fetchFacultyProfile();
      setState(() {
        _profileData = data;
        _phoneController.text = data['phone_number'] ?? '';
        _emergencyController.text = data['emergency_contact'] ?? '';
        _photoUrlController.text = data['profile_photo_url'] ?? '';
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load profile. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final updates = <String, dynamic>{
        'phone_number': _phoneController.text.trim(),
        'emergency_contact': _emergencyController.text.trim(),
        'profile_photo_url': _photoUrlController.text.trim(),
      };
      
      if (_newPasswordController.text.isNotEmpty) {
        if (_newPasswordController.text != _confirmPasswordController.text) {
          throw const ApiException(message: 'New passwords do not match.', statusCode: 400, type: ApiErrorType.validation);
        }
        if (_currentPasswordController.text.isEmpty) {
          throw const ApiException(message: 'Current password is required to change password.', statusCode: 400, type: ApiErrorType.validation);
        }
        updates['current_password'] = _currentPasswordController.text;
        updates['new_password'] = _newPasswordController.text;
      }

      final data = await ApiService.updateFacultyProfile(updates);
      setState(() {
        _profileData = data;
        _successMessage = 'Profile updated successfully.';
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to update profile. Please try again.');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _profileData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: AppTypography.bodyLarge),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
          ],
        ),
      );
    }

    final p = _profileData!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(theme, isDark, p),
                  const SizedBox(height: 16),

                  if (_successMessage != null) _buildStatusMessage(_successMessage!, AppColors.success),
                  if (_errorMessage != null) _buildStatusMessage(_errorMessage!, AppColors.error),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Personal Details', style: AppTypography.h4),
                          const SizedBox(height: 20),
                          AppInput(
                            label: 'Phone Number',
                            hint: 'e.g., +1 234 567 890',
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            prefixIcon: Icons.phone_outlined,
                          ),
                          const SizedBox(height: 16),
                          AppInput(
                            label: 'Emergency Contact Info',
                            hint: 'Name and phone',
                            controller: _emergencyController,
                            prefixIcon: Icons.contact_phone_outlined,
                          ),
                          const SizedBox(height: 16),
                          AppInput(
                            label: 'Profile Photo URL',
                            hint: 'https://example.com/photo.jpg',
                            controller: _photoUrlController,
                            prefixIcon: Icons.image_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Security', style: AppTypography.h4),
                          const SizedBox(height: 20),
                          AppInput(
                            label: 'Current Password',
                            hint: 'Required for password change',
                            controller: _currentPasswordController,
                            isPassword: _obscureCurrent,
                            prefixIcon: Icons.lock_clock_outlined,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                              onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AppInput(
                            label: 'New Password',
                            hint: 'Min 6 characters',
                            controller: _newPasswordController,
                            isPassword: _obscureNew,
                            prefixIcon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                              onPressed: () => setState(() => _obscureNew = !_obscureNew),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AppInput(
                            label: 'Confirm New Password',
                            hint: 'Re-enter new password',
                            controller: _confirmPasswordController,
                            isPassword: _obscureConfirm,
                            prefixIcon: Icons.lock_reset_outlined,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            validator: (val) {
                              if (_newPasswordController.text.isNotEmpty && val != _newPasswordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Account Settings (Read-Only)', style: AppTypography.h4),
                          const SizedBox(height: 16),
                          _readOnlyRow('Faculty ID', p['id']?.toString() ?? '', isDark),
                          _readOnlyRow('Email Address', p['email'] ?? '', isDark),
                          _readOnlyRow('Organization', p['organization_name'] ?? '', isDark),
                          _readOnlyRow('Department', p['department_name'] ?? 'Not assigned', isDark),
                          _readOnlyRow('Active Handset', p['registered_device'] ?? 'None', isDark),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Session', style: AppTypography.h4),
                          const SizedBox(height: 12),
                          Text(
                            'Log out of your faculty account on this device. You will need to sign in again to access the dashboard.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: AppButton(
                              text: 'Sign Out / Log Out',
                              variant: ButtonVariant.outline,
                              leadingIcon: Icons.logout,
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Log Out'),
                                    content: const Text('Are you sure you want to log out from this device?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(true),
                                        child: const Text('Log Out', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await SessionManager.clear();
                                  if (context.mounted) {
                                    context.go('/login');
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  AppButton(
                    text: 'Save Profile Changes',
                    isLoading: _isSaving,
                    onPressed: _saveProfile,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, bool isDark, Map<String, dynamic> p) {
    return Card(
      color: theme.colorScheme.primary.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              backgroundImage: _photoUrlController.text.trim().isNotEmpty
                  ? NetworkImage(_photoUrlController.text.trim())
                  : null,
              child: _photoUrlController.text.trim().isEmpty
                  ? Text(
                      p['full_name'] != null ? p['full_name'][0].toUpperCase() : 'F',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    )
                  : null,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['full_name'] ?? 'Faculty Name', style: AppTypography.h3),
                  const SizedBox(height: 4),
                  Text(
                    '${p['department_name'] ?? 'No Department'} • ${p['organization_name']}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage(String message, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(color == AppColors.success ? Icons.check_circle_outline : Icons.error_outline, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTypography.bodyMedium.copyWith(color: color))),
        ],
      ),
    );
  }

  Widget _readOnlyRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value, 
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
            ),
          ),
        ],
      ),
    );
  }
}

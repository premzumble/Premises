import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/dropdown.dart';

class FacultyReasonRequestScreen extends StatefulWidget {
  const FacultyReasonRequestScreen({super.key});

  @override
  State<FacultyReasonRequestScreen> createState() => _FacultyReasonRequestScreenState();
}

class _FacultyReasonRequestScreenState extends State<FacultyReasonRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  String _reasonType = 'Medical';
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _reasonTypes = [
    'Medical',
    'Personal Emergency',
    'Official Duty',
    'Technical Issue',
    'Transportation',
    'Other',
  ];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await ApiService.submitReasonRequest(
        reasonType: _reasonType,
        notes: _notesController.text,
        // In a real app, we might capture current location here.
        // For this simulator, we just submit.
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excusal request submitted successfully.')),
        );
        context.go('/faculty/dashboard');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Excusal Reason'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/faculty/dashboard'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Request Excusal',
                    style: AppTypography.h2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you are outside the campus boundary during working hours, please provide a reason for your absence to avoid attendance penalties.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text('Reason Type', style: AppTypography.bodyLarge),
                  const SizedBox(height: 8),
                  AppDropdownFormField<String>(
                    value: _reasonType,
                    items: _reasonTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _reasonType = val);
                    },
                  ),
                  const SizedBox(height: 24),

                  Text('Additional Notes', style: AppTypography.bodyLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Provide details about your absence...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (val) {
                      if (_reasonType == 'Other' && (val == null || val.isEmpty)) {
                        return 'Please provide notes for "Other" reason type.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 40),

                  AppButton(
                    text: 'Submit Request',
                    onPressed: _submit,
                    isLoading: _isSubmitting,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/faculty/dashboard'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

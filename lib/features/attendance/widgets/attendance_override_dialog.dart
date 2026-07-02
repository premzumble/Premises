import 'package:flutter/material.dart';
import '../../../../core/design_system/app_colors.dart';
import '../../../../core/api_service.dart';

/// A premium, enterprise-grade dialog for manual attendance overrides.
class AttendanceOverrideDialog extends StatefulWidget {
  final String facultyName;
  final String facultyId;
  final String currentStatus;
  final String attendanceDate; // Formatted as YYYY-MM-DD

  const AttendanceOverrideDialog({
    super.key,
    required this.facultyName,
    required this.facultyId,
    required this.currentStatus,
    required this.attendanceDate,
  });

  @override
  State<AttendanceOverrideDialog> createState() => _AttendanceOverrideDialogState();
}

class _AttendanceOverrideDialogState extends State<AttendanceOverrideDialog> {
  final _formKey = GlobalKey<FormState>();
  
  String _selectedStatus = 'Full Day Present';
  String _selectedReason = 'Forgot Mobile Device';
  final _remarksController = TextEditingController();
  final _workingHoursController = TextEditingController();
  
  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;
  
  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _statusOptions = [
    'Full Day Present',
    'Half Day Present',
    'Half Day Absent',
    'Mark Absent'
  ];

  final List<String> _reasonOptions = [
    'Forgot Mobile Device',
    'Mobile Battery Drained',
    'GPS Failure',
    'Network Connectivity Issue',
    'Official Duty',
    'Emergency',
    'Other'
  ];

  @override
  void dispose() {
    _remarksController.dispose();
    _workingHoursController.dispose();
    super.dispose();
  }

  String? _formatTimeAsIso(TimeOfDay? time) {
    if (time == null) return null;
    final parts = widget.attendanceDate.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final dt = DateTime(year, month, day, time.hour, time.minute);
    return dt.toUtc().toIso8601String();
  }

  Future<void> _selectTime(BuildContext context, bool isCheckIn) async {
    final initialTime = isCheckIn 
        ? const TimeOfDay(hour: 9, minute: 0) 
        : const TimeOfDay(hour: 17, minute: 0);
        
    final selected = await showTimePicker(
      context: context,
      initialTime: isCheckIn ? (_checkInTime ?? initialTime) : (_checkOutTime ?? initialTime),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: const Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selected != null) {
      setState(() {
        if (isCheckIn) {
          _checkInTime = selected;
        } else {
          _checkOutTime = selected;
        }
      });
    }
  }

  Future<void> _submitOverride({bool forceReplace = false}) async {
    if (!_formKey.currentState!.validate()) return;
    
    // 1. Show Double Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Confirm Attendance Override'),
        content: Text(
          'You are about to manually override attendance for ${widget.facultyName} on ${widget.attendanceDate}.\n\n'
          'This action will be permanently recorded in the audit logs. Are you sure you want to continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Override'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final double? hours = _workingHoursController.text.isNotEmpty 
          ? double.tryParse(_workingHoursController.text) 
          : null;

      final res = await ApiService.overrideAttendance(
        facultyId: widget.facultyId,
        attendanceDate: widget.attendanceDate,
        overrideStatus: _selectedStatus,
        overrideReason: _selectedReason,
        overrideRemarks: _remarksController.text,
        manualCheckInTime: _formatTimeAsIso(_checkInTime),
        manualCheckOutTime: _formatTimeAsIso(_checkOutTime),
        effectiveWorkingHours: hours,
        forceReplace: forceReplace,
      );

      if (res['success'] == true) {
        if (mounted) {
          Navigator.pop(context, true); // Return true to indicate success
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Attendance override saved for ${widget.facultyName}'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } else if (res['data'] != null && res['data']['already_overridden'] == true) {
        // Handle Duplicate Override warning
        if (mounted) {
          final replace = await showDialog<bool>(
            context: context,
            builder: (warnContext) => AlertDialog(
              title: const Text('Already Overridden'),
              content: const Text(
                'This attendance record has already been manually overridden.\n\n'
                'Would you like to replace the existing override with this new configuration?'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(warnContext, false),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(warnContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Replace Existing Override'),
                ),
              ],
            ),
          );

          if (replace == true) {
            _submitOverride(forceReplace: true);
          } else {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'An error occurred while saving.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('ApiException[400/client]: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Manual Attendance Override',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Meta details
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _buildMetaRow('Faculty Member', widget.facultyName),
                            const SizedBox(height: 8),
                            _buildMetaRow('Faculty ID', widget.facultyId),
                            const SizedBox(height: 8),
                            _buildMetaRow('Attendance Date', widget.attendanceDate),
                            const SizedBox(height: 8),
                            _buildMetaRow('Current Status', widget.currentStatus),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Status Selector
                      const Text(
                        'Override Attendance Type',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        items: _statusOptions.map((opt) => DropdownMenuItem(
                          value: opt,
                          child: Text(opt, style: const TextStyle(fontSize: 14)),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedStatus = val;
                            });
                          }
                        },
                        decoration: _inputDecoration(),
                      ),
                      const SizedBox(height: 16),

                      // Reason Selector
                      const Text(
                        'Override Reason',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedReason,
                        items: _reasonOptions.map((opt) => DropdownMenuItem(
                          value: opt,
                          child: Text(opt, style: const TextStyle(fontSize: 14)),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedReason = val;
                            });
                          }
                        },
                        decoration: _inputDecoration(),
                      ),
                      const SizedBox(height: 16),

                      // Optional working hours & times
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Manual Check In',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton(
                                  onPressed: () => _selectTime(context, true),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    alignment: Alignment.centerLeft,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _checkInTime != null ? _checkInTime!.format(context) : 'Select check-in',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _checkInTime != null ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                          fontWeight: FontWeight.normal
                                        ),
                                      ),
                                      const Icon(Icons.access_time, size: 16, color: Color(0xFF64748B)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Manual Check Out',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton(
                                  onPressed: () => _selectTime(context, false),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    alignment: Alignment.centerLeft,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _checkOutTime != null ? _checkOutTime!.format(context) : 'Select check-out',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _checkOutTime != null ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                          fontWeight: FontWeight.normal
                                        ),
                                      ),
                                      const Icon(Icons.access_time, size: 16, color: Color(0xFF64748B)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Effective Working Hours
                      const Text(
                        'Effective Working Hours (Optional)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _workingHoursController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration(hint: 'e.g. 8.5'),
                        validator: (val) {
                          if (val != null && val.isNotEmpty) {
                            final n = double.tryParse(val);
                            if (n == null || n < 0 || n > 24) {
                              return 'Enter hours between 0 and 24';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Remarks
                      const Text(
                        'Override Remarks (Required)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _remarksController,
                        maxLines: 3,
                        decoration: _inputDecoration(hint: 'Enter administrative remarks justifying this override...'),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Remarks are strictly required for compliance.';
                          }
                          if (val.trim().length < 5) {
                            return 'Please enter a meaningful description (min 5 chars).';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF475569))),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : () => _submitOverride(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Override', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }
}

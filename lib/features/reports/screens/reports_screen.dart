import 'package:flutter/material.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../utils/report_exporter.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedReportType = 'Daily Attendance Summary';
  String _selectedExportFormat = 'CSV';

  final List<String> _reportTypes = [
    'Daily Attendance Summary',
    'Weekly Audits Summary',
    'Monthly Attendance Report',
    'Faculty-wise Logs Summary',
  ];

  final List<String> _exportFormats = ['PDF', 'CSV', 'Excel'];

  bool _isGenerating = false;

  // Report parameters
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedDeptId = 'All';
  String _selectedFacultyId = 'All';
  String _selectedAttendanceStatus = 'All';

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _faculty = [];
  bool _isLoadingParams = true;

  @override
  void initState() {
    super.initState();
    _loadParameters();
  }

  Future<void> _loadParameters() async {
    if (!mounted) return;
    setState(() => _isLoadingParams = true);
    try {
      final depts = await ApiService.fetchDepartments();
      final rosterRes = await ApiService.get('/admin/faculty-roster');
      List<Map<String, dynamic>> facultyList = [];
      if (rosterRes['success'] == true && rosterRes['data'] != null) {
        facultyList = List<Map<String, dynamic>>.from(rosterRes['data'] as List);
      }
      if (mounted) {
        setState(() {
          _departments = depts;
          _faculty = facultyList;
          _isLoadingParams = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load parameters for reports: $e');
      if (mounted) {
        setState(() => _isLoadingParams = false);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final exporter = ReportExporterFactory.getExporter(_selectedExportFormat);
      
      final Map<String, dynamic> params = {};
      if (_startDate != null) {
        params['start_date'] = _startDate!.toIso8601String().split('T')[0];
      }
      if (_endDate != null) {
        params['end_date'] = _endDate!.toIso8601String().split('T')[0];
      }
      if (_selectedDeptId != 'All') {
        params['department_id'] = _selectedDeptId;
      }
      if (_selectedFacultyId != 'All') {
        params['faculty_id'] = _selectedFacultyId;
      }
      if (_selectedAttendanceStatus != 'All') {
        params['attendance_status'] = _selectedAttendanceStatus;
      }

      final filePath = await exporter.exportReport(
        reportType: _selectedReportType,
        parameters: params,
      );

      if (mounted) {
        final message = filePath != null
            ? 'Report "$_selectedReportType" exported successfully to: $filePath'
            : 'Report "$_selectedReportType" exported successfully as $_selectedExportFormat.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on UnsupportedError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Export format not supported.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export report: ${e.message}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred during export: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              'Reports & Analytics Generator',
              style: AppTypography.h2.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            Text(
              'Compile, download, and export historical logs by department, dates, and faculty parameters.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 24),

            // Main settings card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose Parameters', style: AppTypography.h3),
                    const Divider(height: 24),
                    
                    // Report Type Dropdown
                    Text(
                      'Report Type',
                      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedReportType,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                      items: _reportTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedReportType = val);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Date Range Selector
                    Text(
                      'Date Range (Optional)',
                      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectDateRange,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          prefixIcon: Icon(Icons.date_range_outlined, size: 20),
                        ),
                        child: Text(
                          _startDate != null && _endDate != null
                              ? '${_startDate!.toLocal().toString().split(' ')[0]} to ${_endDate!.toLocal().toString().split(' ')[0]}'
                              : 'Select Date Range',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Department Dropdown
                    Text(
                      'Filter by Department',
                      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedDeptId,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                      items: [
                        const DropdownMenuItem(value: 'All', child: Text('All Departments', style: TextStyle(fontSize: 13))),
                        ..._departments.map((d) => DropdownMenuItem(
                              value: d['id']?.toString() ?? '',
                              child: Text(d['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedDeptId = val);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Faculty Dropdown
                    Text(
                      'Filter by Faculty',
                      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedFacultyId,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                      items: [
                        const DropdownMenuItem(value: 'All', child: Text('All Faculty', style: TextStyle(fontSize: 13))),
                        ..._faculty.map((f) => DropdownMenuItem(
                              value: f['id']?.toString() ?? '',
                              child: Text(f['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedFacultyId = val);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Attendance Status Dropdown
                    Text(
                      'Filter by Attendance Status',
                      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedAttendanceStatus,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                      items: ['All', 'PRESENT', 'ABSENT', 'OUTSIDE']
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s, style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedAttendanceStatus = val);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Export Format Selection
                    Text(
                      'Export File Format',
                      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: _exportFormats.map((format) {
                        final isSelected = _selectedExportFormat == format;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: ChoiceChip(
                            label: Text(format, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            selected: isSelected,
                            selectedColor: theme.colorScheme.primary.withOpacity(0.08),
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedExportFormat = format);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                    const Divider(height: 48),

                    // Generate button
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        text: 'Compile & Export Report',
                        isLoading: _isGenerating,
                        leadingIcon: Icons.download_outlined,
                        onPressed: _generateReport,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

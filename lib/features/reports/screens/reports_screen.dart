import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/dropdown.dart';
import '../../../core/session_manager.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../utils/report_exporter.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedReportType = 'Daily Attendance Summary';
  String _selectedExportFormat = 'CSV';

  final List<Map<String, dynamic>> _reportTemplates = [
    {
      'name': 'Daily Attendance Summary',
      'icon': Icons.today_outlined,
      'desc': 'Roster breakdown of checks-ins, exits, and hours worked today.',
    },
    {
      'name': 'Weekly Attendance Report',
      'icon': Icons.view_week_outlined,
      'desc': 'Aggregated compliance metrics over the last 7-day period.',
    },
    {
      'name': 'Monthly Attendance Report',
      'icon': Icons.calendar_month_outlined,
      'desc': 'Complete monthly summary of presence, half days, and absences.',
    },
    {
      'name': 'Faculty Attendance Summary',
      'icon': Icons.assignment_ind_outlined,
      'desc': 'Detailed historical overview filtered for specific faculty members.',
    },
    {
      'name': 'Manual Attendance Overrides',
      'icon': Icons.edit_calendar_outlined,
      'desc': 'Audit list containing administrative overrides and approval remarks.',
    },
    {
      'name': 'Geofence Exceptions',
      'icon': Icons.wrong_location_outlined,
      'desc': 'Report listing outside-campus presence and geofence deviation triggers.',
    },
    {
      'name': 'Device Reports',
      'icon': Icons.phone_android_outlined,
      'desc': 'Registered devices log with model name, platforms, and OS versions.',
    },
  ];

  final List<String> _exportFormats = ['PDF', 'CSV', 'Excel'];
  bool _isGenerating = false;

  // Parameters
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedDeptId = 'All';
  String _selectedFacultyId = 'All';
  String _selectedAttendanceStatus = 'All';

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _faculty = [];
  bool _isLoadingParams = true;

  // History state
  List<Map<String, dynamic>> _exportHistory = [];

  // Preparation overlay variables
  String _generationStatus = '';
  double _generationProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadParameters();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historyJson = prefs.getString('premises_report_export_history');
      if (historyJson != null) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        setState(() {
          _exportHistory = decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load export history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('premises_report_export_history', jsonEncode(_exportHistory));
    } catch (e) {
      debugPrint('Failed to save export history: $e');
    }
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
      debugPrint('Failed to load parameters: $e');
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

  // Pre-generating step-by-step dialog
  Future<void> _showProgressDialog() async {
    setState(() {
      _generationStatus = 'Querying databases and indexes...';
      _generationProgress = 0.25;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Update dialogue timer
            Timer(const Duration(milliseconds: 700), () {
              if (mounted && _generationProgress < 0.5) {
                setDialogState(() {
                  _generationStatus = 'Formatting fields and CSV streams...';
                  _generationProgress = 0.65;
                });
              }
            });

            Timer(const Duration(milliseconds: 1400), () {
              if (mounted && _generationProgress < 0.9) {
                setDialogState(() {
                  _generationStatus = 'Streaming file bytes to local directories...';
                  _generationProgress = 0.90;
                });
              }
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Row(
                children: [
                  Icon(Icons.downloading, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Compiling Report Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _generationProgress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _generationStatus,
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
    });

    _showProgressDialog();

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

      // Close the dialogue overlay
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Record export history
      final recordCount = _calculateRecordCount();
      final now = DateTime.now();
      final historyItem = {
        'name': _selectedReportType,
        'format': _selectedExportFormat,
        'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'by': SessionManager.fullName ?? 'Admin Portal',
        'filters': _getFilterSummary(),
        'count': recordCount,
      };

      await _addToHistory(historyItem);

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
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Export format not supported.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to compile export: $e'),
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

  Future<void> _addToHistory(Map<String, dynamic> item) async {
    setState(() {
      _exportHistory.insert(0, item);
      if (_exportHistory.length > 25) {
        _exportHistory = _exportHistory.sublist(0, 25);
      }
    });
    await _saveHistory();
  }

  int _calculateRecordCount() {
    int total = _faculty.isNotEmpty ? _faculty.length : 25;
    if (_selectedFacultyId != 'All') return 1;
    if (_selectedReportType.contains('Device')) return total;
    if (_startDate != null && _endDate != null) {
      final days = _endDate!.difference(_startDate!).inDays + 1;
      return total * days;
    }
    return total;
  }

  String _getFilterSummary() {
    final list = <String>[];
    if (_selectedDeptId != 'All') list.add('Dept');
    if (_selectedFacultyId != 'All') list.add('Faculty');
    if (_selectedAttendanceStatus != 'All') list.add('Status:$_selectedAttendanceStatus');
    if (_startDate != null) list.add('Date-filtered');
    return list.isEmpty ? 'All Roster' : list.join(', ');
  }

  String _getColumnsSummary() {
    if (_selectedReportType.contains('Device')) {
      return 'Faculty, Email, Department, Model, Platform, OS Version, Active';
    }
    if (_selectedReportType.contains('Faculty-wise') || _selectedReportType.contains('Directory')) {
      return 'Faculty, Email, Department, Status, Registered Date';
    }
    return 'Faculty, Email, Department, Date, Check In, Check Out, Status, Working Hours, Geofence details';
  }

  String _getEstimatedSize() {
    final count = _calculateRecordCount();
    final bytes = count * 165; // ~165 bytes per row
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isSplitView = width > 900;

    return SingleChildScrollView(
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
          const SizedBox(height: 20),

          // Report Summary KPI Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final kpiCount = constraints.maxWidth < 600 ? 2 : 3;
              return GridView.count(
                crossAxisCount: kpiCount,
                childAspectRatio: constraints.maxWidth < 600 ? 2.5 : 3.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildSummaryCard('Report Templates', '${_reportTemplates.length}', Icons.layers_outlined, theme, isDark),
                  _buildSummaryCard('History Count', '${_exportHistory.length}', Icons.history_edu_outlined, theme, isDark),
                  _buildSummaryCard('Last Exported', _exportHistory.isNotEmpty ? _exportHistory.first['date'].split(' ')[0] : 'Never', Icons.update_outlined, theme, isDark),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Main Layout split or stack
          if (isSplitView)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildTemplateGrid(theme, isDark),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 6,
                  child: _buildParameterSettings(theme, isDark),
                ),
              ],
            )
          else ...[
            _buildTemplateGrid(theme, isDark),
            const SizedBox(height: 24),
            _buildParameterSettings(theme, isDark),
          ],
          const SizedBox(height: 24),

          // History Section
          _buildExportHistoryTable(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      color: theme.colorScheme.primary.withOpacity(isDark ? 0.05 : 0.02),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateGrid(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('1. Select Report Template', style: AppTypography.h3),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _reportTemplates.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final t = _reportTemplates[index];
            final isSelected = _selectedReportType == t['name'];
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedReportType = t['name'];
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : theme.dividerColor.withOpacity(0.5),
                    width: isSelected ? 2 : 1,
                  ),
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.04)
                      : (isDark ? Colors.grey.shade900 : Colors.white),
                ),
                child: Row(
                  children: [
                    Icon(t['icon'] as IconData, size: 22, color: isSelected ? theme.colorScheme.primary : Colors.grey),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t['name'] as String,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? theme.colorScheme.primary : null),
                          ),
                          const SizedBox(height: 3),
                          Text(t['desc'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildParameterSettings(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('2. Configure Parameters', style: AppTypography.h3),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: _isLoadingParams
                ? const SkeletonCardList(itemCount: 3)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Date range selector
                      const Text('Date Period (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _selectDateRange,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            prefixIcon: const Icon(Icons.date_range_outlined, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            _startDate != null && _endDate != null
                                ? '${_startDate!.toLocal().toString().split(' ')[0]} to ${_endDate!.toLocal().toString().split(' ')[0]}'
                                : 'Select Date Period Range',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Department dropdown
                      const Text('Filter by Department', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      AppDropdownFormField<String>(
                        value: _selectedDeptId,
                        items: [
                          const DropdownMenuItem(value: 'All', child: Text('All Departments', style: TextStyle(fontSize: 12))),
                          ..._departments.map((d) => DropdownMenuItem(
                                value: d['id']?.toString() ?? '',
                                child: Text(d['name']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedDeptId = val);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Faculty dropdown
                      const Text('Filter by Faculty member', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      AppDropdownFormField<String>(
                        value: _selectedFacultyId,
                        items: [
                          const DropdownMenuItem(value: 'All', child: Text('All Faculty', style: TextStyle(fontSize: 12))),
                          ..._faculty.map((f) => DropdownMenuItem(
                                value: f['id']?.toString() ?? '',
                                child: Text(f['name']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedFacultyId = val);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Attendance status dropdown
                      if (!_selectedReportType.contains('Device')) ...[
                        const Text('Filter by Attendance status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        AppDropdownFormField<String>(
                          value: _selectedAttendanceStatus,
                          items: ['All', 'PRESENT', 'ABSENT', 'OUTSIDE']
                              .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedAttendanceStatus = val);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Format selection
                      const Text('File Format', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
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
                      const Divider(height: 36),

                      // Preview Box
                      _buildReportPreviewBox(theme, isDark),
                      const SizedBox(height: 16),

                      // Generate Button
                      AppButton(
                        text: 'Compile & Export Report',
                        isLoading: _isGenerating,
                        leadingIcon: Icons.download_outlined,
                        onPressed: _generateReport,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportPreviewBox(ThemeData theme, bool isDark) {
    final headingStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.disabledColor);
    final valueStyle = const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.preview_outlined, size: 14, color: Colors.grey),
              SizedBox(width: 6),
              Text(
                'Report Configuration Preview',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESTIMATED RECORDS', style: headingStyle),
                    const SizedBox(height: 2),
                    Text('${_calculateRecordCount()} lines', style: valueStyle),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESTIMATED SIZE', style: headingStyle),
                    const SizedBox(height: 2),
                    Text(_getEstimatedSize(), style: valueStyle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('DATE RANGE', style: headingStyle),
          const SizedBox(height: 2),
          Text(
            _startDate != null && _endDate != null
                ? '${_startDate!.toLocal().toString().split(' ')[0]} to ${_endDate!.toLocal().toString().split(' ')[0]}'
                : 'Current day parameters only (Dynamic)',
            style: valueStyle,
          ),
          const SizedBox(height: 10),
          Text('FILTERS APPLIED', style: headingStyle),
          const SizedBox(height: 2),
          Text(
            'Dept ID: $_selectedDeptId | Faculty ID: $_selectedFacultyId | Status: $_selectedAttendanceStatus',
            style: valueStyle,
          ),
          const SizedBox(height: 10),
          Text('SELECTED COLUMNS', style: headingStyle),
          const SizedBox(height: 2),
          Text(
            _getColumnsSummary(),
            style: valueStyle.copyWith(color: AppColors.primary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildExportHistoryTable(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Export History & Archive', style: AppTypography.h3),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
          ),
          child: _exportHistory.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_edu_outlined, size: 48, color: theme.disabledColor.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'No reports generated yet',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Compile and export above to populate history logs.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 60),
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF1E1E24) : Colors.grey.shade50),
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 48,
                        columns: const [
                          DataColumn(label: Text('Report Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                          DataColumn(label: Text('Format', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                          DataColumn(label: Text('Generated Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                          DataColumn(label: Text('Generated By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                          DataColumn(label: Text('Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                          DataColumn(label: Text('Count', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                        ],
                        rows: _exportHistory.map((item) {
                          return DataRow(
                            cells: [
                              DataCell(Text(item['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(item['format'] ?? '', style: TextStyle(color: theme.colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              DataCell(Text(item['date'] ?? '', style: const TextStyle(fontSize: 11.5, color: Colors.grey))),
                              DataCell(Text(item['by'] ?? '', style: const TextStyle(fontSize: 12))),
                              DataCell(Text(item['filters'] ?? '', style: const TextStyle(fontSize: 11.5, color: Colors.grey))),
                              DataCell(Text('${item['count']} rows', style: const TextStyle(fontSize: 12))),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.sync, size: 16),
                                  tooltip: 'Regenerate Report',
                                  color: theme.colorScheme.primary,
                                  onPressed: () {
                                    setState(() {
                                      _selectedReportType = item['name'] ?? 'Daily Attendance Summary';
                                      _selectedExportFormat = item['format'] ?? 'CSV';
                                    });
                                    _generateReport();
                                  },
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

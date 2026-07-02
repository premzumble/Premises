import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/api_service.dart';
import '../../../core/widgets/premises_loader.dart';
import '../../../core/session_manager.dart';
import '../widgets/attendance_override_dialog.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/dropdown.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  int _expandedIndex = -1;
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _dailyRecords = [];

  // Pagination state
  int _currentPage = 1;
  int _pageSize = 25;
  int _totalItems = 0;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDeptId = 'All';
  String _selectedStatus = 'All';
  String _selectedOverride = 'All';
  String _selectedCampusStatus = 'All';
  List<Map<String, dynamic>> _departments = [];
  Timer? _debounce;

  // KPI counters state
  int _kpiPresent = 0;
  int _kpiAbsent = 0;
  int _kpiHalfDay = 0;
  int _kpiOverrides = 0;
  int _kpiInside = 0;
  int _kpiOutside = 0;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _fetchAttendanceLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final depts = await ApiService.fetchDepartments();
      if (mounted) {
        setState(() {
          _departments = depts;
        });
      }
    } catch (e) {
      debugPrint('Failed to load departments: $e');
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = query;
        _currentPage = 1;
        _expandedIndex = -1;
      });
      _fetchAttendanceLogs();
    });
  }

  Future<void> _fetchAttendanceLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final formattedDate =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    final queryParams = <String>[];
    queryParams.add('target_date=$formattedDate');
    queryParams.add('page=$_currentPage');
    queryParams.add('page_size=$_pageSize');

    if (_searchQuery.trim().isNotEmpty) {
      queryParams.add('search_query=${Uri.encodeQueryComponent(_searchQuery.trim())}');
    }
    if (_selectedDeptId != 'All') {
      queryParams.add('department_id=$_selectedDeptId');
    }
    if (_selectedStatus != 'All') {
      queryParams.add('status=$_selectedStatus');
    }
    if (_selectedOverride != 'All') {
      queryParams.add('is_overridden=${_selectedOverride == 'Manually Overridden'}');
    }
    if (_selectedCampusStatus != 'All') {
      queryParams.add('campus_status=$_selectedCampusStatus');
    }

    try {
      final res = await ApiService.get('/admin/attendance-logs?${queryParams.join('&')}');
      if (res['success'] == true && res['data'] != null) {
        if (mounted) {
          setState(() {
            final data = res['data'];
            if (data is Map) {
              _dailyRecords = data['items'] ?? [];
              _currentPage = data['page'] ?? 1;
              _pageSize = data['page_size'] ?? 25;
              _totalItems = data['total'] ?? 0;
              
              // Load KPIs
              if (data['kpis'] != null) {
                final kpis = data['kpis'];
                _kpiPresent = kpis['present'] ?? 0;
                _kpiAbsent = kpis['absent'] ?? 0;
                _kpiHalfDay = kpis['half_day'] ?? 0;
                _kpiOverrides = kpis['overrides'] ?? 0;
                _kpiInside = kpis['inside'] ?? 0;
                _kpiOutside = kpis['outside'] ?? 0;
              }
            } else {
              _dailyRecords = data;
              _totalItems = data.length;
            }
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = res['message'] ?? 'Failed to load daily attendance logs.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _expandedIndex = -1;
        _currentPage = 1;
      });
      _fetchAttendanceLogs();
    }
  }

  String formatEventTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      final hr = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return "${hr.toString().padLeft(2, '0')}:$min $ampm";
    } catch (_) {
      return isoTime;
    }
  }

  Widget _highlightText(String text, String query, TextStyle style, TextStyle highlightStyle) {
    if (query.isEmpty) return Text(text, style: style);
    final matches = text.toLowerCase().indexOf(query.toLowerCase());
    if (matches == -1) return Text(text, style: style);

    final before = text.substring(0, matches);
    final match = text.substring(matches, matches + query.length);
    final after = text.substring(matches + query.length);

    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: before),
          TextSpan(text: match, style: highlightStyle),
          TextSpan(text: after),
        ],
      ),
    );
  }

  Widget _buildKpiDashboard(ThemeData theme, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 900 ? 3 : 6);
        double childAspectRatio = constraints.maxWidth < 600 ? 2.5 : 1.8;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildKpiCard('Present Today', '$_kpiPresent', Icons.check_circle_outline, AppColors.success, theme, isDark),
            _buildKpiCard('Absent Today', '$_kpiAbsent', Icons.cancel_outlined, AppColors.danger, theme, isDark),
            _buildKpiCard('Half Day', '$_kpiHalfDay', Icons.star_half_outlined, Colors.orange, theme, isDark),
            _buildKpiCard('Manual Overrides', '$_kpiOverrides', Icons.edit_calendar_outlined, Colors.indigo, theme, isDark),
            _buildKpiCard('Inside Campus', '$_kpiInside', Icons.my_location_outlined, AppColors.success, theme, isDark),
            _buildKpiCard('Outside Campus', '$_kpiOutside', Icons.location_searching_outlined, Colors.orange, theme, isDark),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, ThemeData theme, bool isDark) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      color: color.withOpacity(isDark ? 0.05 : 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
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

  Widget _buildFiltersBar(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search faculty name, email, phone, ID...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;

                final deptDropdown = AppDropdownFormField<String>(
                  value: _selectedDeptId,
                  label: 'Department',
                  items: [
                    const DropdownMenuItem(value: 'All', child: Text('All Departments', style: TextStyle(fontSize: 12))),
                    ..._departments.map((d) => DropdownMenuItem(
                          value: d['id']?.toString() ?? '',
                          child: Text(d['name']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                        )),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedDeptId = val;
                        _currentPage = 1;
                        _expandedIndex = -1;
                      });
                      _fetchAttendanceLogs();
                    }
                  },
                );

                final statusDropdown = AppDropdownFormField<String>(
                  value: _selectedStatus,
                  label: 'Attendance Status',
                  items: ['All', 'PRESENT', 'ABSENT', 'HALF_DAY']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedStatus = val;
                        _currentPage = 1;
                        _expandedIndex = -1;
                      });
                      _fetchAttendanceLogs();
                    }
                  },
                );

                final overrideDropdown = AppDropdownFormField<String>(
                  value: _selectedOverride,
                  label: 'Override Filter',
                  items: ['All', 'Manually Overridden', 'Automatic Geofence']
                      .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedOverride = val;
                        _currentPage = 1;
                        _expandedIndex = -1;
                      });
                      _fetchAttendanceLogs();
                    }
                  },
                );

                final campusDropdown = AppDropdownFormField<String>(
                  value: _selectedCampusStatus,
                  label: 'Campus Status',
                  items: ['All', 'INSIDE', 'OUTSIDE']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCampusStatus = val;
                        _currentPage = 1;
                        _expandedIndex = -1;
                      });
                      _fetchAttendanceLogs();
                    }
                  },
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: deptDropdown),
                      const SizedBox(width: 10),
                      Expanded(child: statusDropdown),
                      const SizedBox(width: 10),
                      Expanded(child: overrideDropdown),
                      const SizedBox(width: 10),
                      Expanded(child: campusDropdown),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      deptDropdown,
                      const SizedBox(height: 10),
                      statusDropdown,
                      const SizedBox(height: 10),
                      overrideDropdown,
                      const SizedBox(height: 10),
                      campusDropdown,
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_late_outlined, size: 64, color: theme.disabledColor.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              'No Attendance Records Found',
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _selectedDeptId != 'All' || _selectedStatus != 'All' || _selectedOverride != 'All' || _selectedCampusStatus != 'All'
                  ? 'No faculty matched your combined search query or filter parameters. Try clearing some filters.'
                  : 'No attendance records exist for this selected date preset.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: theme.disabledColor),
            ),
            const SizedBox(height: 24),
            if (_searchQuery.isNotEmpty || _selectedDeptId != 'All' || _selectedStatus != 'All' || _selectedOverride != 'All' || _selectedCampusStatus != 'All')
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                    _selectedDeptId = 'All';
                    _selectedStatus = 'All';
                    _selectedOverride = 'All';
                    _selectedCampusStatus = 'All';
                    _currentPage = 1;
                  });
                  _fetchAttendanceLogs();
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('Clear Filters'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 80),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF1E1E24) : Colors.grey.shade50),
              dataRowMinHeight: 56,
              dataRowMaxHeight: 56,
              horizontalMargin: 20,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Faculty Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Check In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Check Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Geofence Mins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              ],
              rows: _dailyRecords.map((record) {
                final isOverridden = record['is_overridden'] == true;

                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
                            child: Text(
                              (record['name'] as String).isEmpty ? '?' : record['name'].split(' ').last[0],
                              style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _highlightText(
                                record['name'] ?? 'Unknown Faculty',
                                _searchQuery,
                                const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                TextStyle(backgroundColor: Colors.yellow.withOpacity(0.3), fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              Text(
                                record['email'] ?? '',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    DataCell(Text(record['department'] ?? 'No Department', style: const TextStyle(fontSize: 12))),
                    DataCell(Text(record['first_entry'] ?? '-', style: const TextStyle(fontSize: 12))),
                    DataCell(Text(record['last_exit'] ?? '-', style: const TextStyle(fontSize: 12))),
                    DataCell(Text('In: ${record['inside_mins']} | Out: ${record['outside_mins']}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
                    DataCell(StatusChip(status: record['status'])),
                    DataCell(
                      isOverridden
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.indigo.withOpacity(0.2)),
                              ),
                              child: const Text('Manual', style: TextStyle(color: Colors.indigo, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          : const Text('Auto', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        color: theme.colorScheme.primary,
                        onPressed: () async {
                          final updated = await showDialog<bool>(
                            context: context,
                            builder: (context) => AttendanceOverrideDialog(
                              facultyName: record['name'] ?? 'Unknown Faculty',
                              facultyId: record['faculty_id'] ?? '',
                              currentStatus: record['status'] ?? 'ABSENT',
                              attendanceDate: "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
                            ),
                          );
                          if (updated == true) {
                            _fetchAttendanceLogs();
                          }
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
    );
  }

  Widget _buildSummaryText(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildTimelineTrackItem({
    required String time,
    required String title,
    required String location,
    required bool isLast,
    required bool isDark,
  }) {
    Color indicatorColor = title.contains('ENTER') || title.contains('RETURN')
        ? AppColors.success
        : AppColors.warning;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                time,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    location,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateString = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              final headerTexts = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Attendance Timeline',
                    style: AppTypography.h2.copyWith(
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  Text(
                    'Granular location check-ins and check-outs of active faculty.',
                    style: AppTypography.caption,
                  ),
                ],
              );

              final datePickerButton = OutlinedButton.icon(
                onPressed: () => _selectDate(context),
                icon: const Icon(Icons.calendar_today_outlined, size: 14),
                label: Text(dateString, style: const TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
                ),
              );

              if (isWide) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    headerTexts,
                    datePickerButton,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerTexts,
                    const SizedBox(height: 12),
                    datePickerButton,
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // KPI summaries Bar
          _buildKpiDashboard(theme, isDark),
          const SizedBox(height: 16),

          // Filters and Search Bar
          _buildFiltersBar(theme, isDark),
          const SizedBox(height: 16),

          // Core Data View
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: SkeletonCardList(itemCount: 4),
            )
          else if (_errorMessage != null && _dailyRecords.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _fetchAttendanceLogs,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_dailyRecords.isEmpty)
            _buildEmptyState(theme, isDark)
          else ...[
            if (isMobile)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _dailyRecords.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final record = _dailyRecords[index];
                  final isExpanded = _expandedIndex == index;
                  final timeline = record['timeline'] as List<dynamic>;

                  return Card(
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withOpacity(0.08),
                            child: Text(
                              (record['name'] as String).isEmpty ? '?' : record['name'].split(' ').last[0],
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                            ),
                          ),
                          title: _highlightText(
                            record['name'] ?? 'Unknown Faculty',
                            _searchQuery,
                            const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            TextStyle(backgroundColor: Colors.yellow.withOpacity(0.3), fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'In: ${record['first_entry']} | Out: ${record['last_exit']}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (record['is_overridden'] == true) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_calendar, size: 10, color: Colors.indigo),
                                      SizedBox(width: 4),
                                      Text(
                                        'Manual',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              StatusChip(status: record['status']),
                              const SizedBox(width: 12),
                              Icon(
                                isExpanded ? Icons.expand_less : Icons.expand_more,
                                size: 18,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                          onTap: () {
                            setState(() {
                              _expandedIndex = isExpanded ? -1 : index;
                            });
                          },
                        ),
                        if (isExpanded) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isWide = constraints.maxWidth > 400;
                                    final insideText = _buildSummaryText('Total Inside Campus:', '${record['inside_mins']} mins');
                                    final outsideText = _buildSummaryText('Total Outside Campus:', '${record['outside_mins']} mins');
                                    return isWide
                                        ? Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              insideText,
                                              outsideText,
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              insideText,
                                              const SizedBox(height: 12),
                                              outsideText,
                                            ],
                                          );
                                  },
                                ),
                                const SizedBox(height: 20),
                                if (record['is_overridden'] == true) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 20),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigo.withOpacity(0.15)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.assignment_ind_outlined, size: 16, color: Colors.indigo),
                                            SizedBox(width: 8),
                                            Text(
                                              'Administrative Override Configuration',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(child: _buildSummaryText('Manual Override Type:', record['override_status'] ?? '-')),
                                            Expanded(child: _buildSummaryText('Exception Reason:', record['override_reason'] ?? '-')),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSummaryText('Compliance Remarks:', record['override_remarks'] ?? '-'),
                                        if (record['effective_working_hours'] != null) ...[
                                          const SizedBox(height: 10),
                                          _buildSummaryText('Effective Working Hours:', '${record['effective_working_hours']} hours'),
                                        ],
                                        const SizedBox(height: 10),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            const Text('Faculty Acknowledgement:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                            const SizedBox(width: 8),
                                            if (record['acknowledged_at'] != null)
                                              const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.check_circle, size: 13, color: Color(0xFF10B981)),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Acknowledged',
                                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                                  ),
                                                ],
                                              )
                                            else
                                              const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.pending_actions_outlined, size: 13, color: Colors.grey),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Not Yet Viewed',
                                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (timeline.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8.0),
                                    child: Text('No location events recorded.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  )
                                else ...[
                                  Text('Geofence Timeline Events', style: AppTypography.h4),
                                  const SizedBox(height: 16),
                                  ...timeline.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final val = entry.value;
                                    return _buildTimelineTrackItem(
                                      time: formatEventTime(val['time']!.toString()),
                                      title: val['event']!.replaceAll('_', ' '),
                                      location: val['location']!,
                                      isLast: idx == timeline.length - 1,
                                      isDark: isDark,
                                    );
                                  }).toList(),
                                ],
                              ],
                            ),
                          ),
                          if (SessionManager.isAdmin) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final updated = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AttendanceOverrideDialog(
                                        facultyName: record['name'] ?? 'Unknown Faculty',
                                        facultyId: record['faculty_id'] ?? '',
                                        currentStatus: record['status'] ?? 'ABSENT',
                                        attendanceDate: dateString,
                                      ),
                                    );
                                    if (updated == true) {
                                      _fetchAttendanceLogs();
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.edit_calendar, size: 16),
                                  label: const Text('Override Attendance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              )
            else
              _buildDesktopTable(theme, isDark),
            
            // Pagination controls
            if (_totalItems > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() {
                                _currentPage--;
                                _expandedIndex = -1;
                              });
                              _fetchAttendanceLogs();
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Page $_currentPage of ${((_totalItems - 1) / _pageSize).floor() + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: _currentPage * _pageSize < _totalItems
                          ? () {
                              setState(() {
                                _currentPage++;
                                _expandedIndex = -1;
                              });
                              _fetchAttendanceLogs();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/api_service.dart';
import '../../../core/widgets/dropdown.dart';
import '../../../core/widgets/premises_loader.dart';
import '../../../core/widgets/skeleton_loader.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _selectedDatePreset = 'Today';
  String _selectedEventType = 'All';
  String _selectedActorType = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  final List<String> _datePresets = ['Today', 'Yesterday', 'Last 7 Days', 'Custom Range', 'All'];
  final List<String> _actorTypes = ['All', 'ADMIN', 'FACULTY', 'SYSTEM'];

  final List<String> _eventTypes = [
    'All',
    'LOGIN',
    'LOGOUT',
    'ENTER_CAMPUS',
    'EXIT_CAMPUS',
    'RETURN_CAMPUS',
    'REASON_SUBMITTED',
    'DEVICE_CHANGE',
    'ATTENDANCE_ACTION',
    'POLICY_CHANGE'
  ];

  List<Map<String, dynamic>> _auditLogs = [];
  DateTimeRange? _customDateRange;

  // View Mode: Table vs Timeline
  bool _isTableView = false;

  // Pagination state
  int _currentPage = 0;
  int _rowsPerPage = 10;

  // Debouncing search
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAuditLogs();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAuditLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.get('/admin/audit-logs');
      if (res['success'] == true && res['data'] != null) {
        if (mounted) {
          setState(() {
            _auditLogs = (res['data'] as List).map((item) {
              final rawTime = item['time'];
              DateTime dt = DateTime.now();
              String timeStr = '12:00 AM';
              if (rawTime != null) {
                try {
                  dt = DateTime.parse(rawTime.toString()).toLocal();
                  final hr = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
                  final min = dt.minute.toString().padLeft(2, '0');
                  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
                  timeStr = "${hr.toString().padLeft(2, '0')}:$min $ampm";
                } catch (_) {}
              }

              final action = (item['action'] ?? '').toString();
              IconData icon = Icons.info_outline;
              Color color = Colors.grey;
              String severity = 'INFO';

              if (action == 'LOGIN') {
                icon = Icons.login_outlined;
                color = Colors.blue;
              } else if (action == 'LOGOUT') {
                icon = Icons.logout_outlined;
                color = Colors.blue;
              } else if (action.contains('ENTER') || action.contains('RETURN')) {
                icon = Icons.zoom_in_map;
                color = Colors.green;
              } else if (action.contains('EXIT')) {
                icon = Icons.zoom_out_map;
                color = Colors.orange;
                severity = 'WARNING';
              } else if (action.contains('DEVICE') || action.contains('REGISTER_DEVICE')) {
                icon = Icons.phone_android_outlined;
                color = Colors.purple;
                severity = 'CRITICAL';
              } else if (action.contains('POLICY')) {
                icon = Icons.policy_outlined;
                color = Colors.red;
                severity = 'CRITICAL';
              } else if (action.contains('APPROVE') || action.contains('REJECT')) {
                icon = Icons.assignment_turned_in_outlined;
                color = Colors.green;
                severity = 'CRITICAL';
              }

              return {
                'id': item['id']?.toString() ?? '',
                'time': timeStr,
                'dateTime': dt,
                'actor': item['actor']?.toString() ?? 'System',
                'actor_type': item['actor_type']?.toString() ?? 'SYSTEM',
                'action': action,
                'details': item['details']?.toString() ?? '',
                'entity_type': item['entity_type']?.toString() ?? 'SYSTEM',
                'old_value': item['old_value'],
                'new_value': item['new_value'],
                'icon': icon,
                'color': color,
                'severity': severity,
              };
            }).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = res['message'] ?? 'Failed to load audit logs.';
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

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query;
        _currentPage = 0;
      });
    });
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customDateRange ?? DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 7)),
        end: DateTime.now(),
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _customDateRange) {
      setState(() {
        _customDateRange = picked;
        _currentPage = 0;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final sevenDaysAgoStart = todayStart.subtract(const Duration(days: 7));

    return _auditLogs.where((log) {
      final DateTime? dt = log['dateTime'] as DateTime?;
      
      // Date preset matching
      bool dateMatches = true;
      if (dt != null) {
        if (_selectedDatePreset == 'Today') {
          dateMatches = dt.isAfter(todayStart) || dt.isAtSameMomentAs(todayStart);
        } else if (_selectedDatePreset == 'Yesterday') {
          dateMatches = (dt.isAfter(yesterdayStart) || dt.isAtSameMomentAs(yesterdayStart)) && dt.isBefore(todayStart);
        } else if (_selectedDatePreset == 'Last 7 Days') {
          dateMatches = dt.isAfter(sevenDaysAgoStart) || dt.isAtSameMomentAs(sevenDaysAgoStart);
        } else if (_selectedDatePreset == 'Custom Range') {
          if (_customDateRange != null) {
            final start = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day);
            final end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59);
            dateMatches = dt.isAfter(start) && dt.isBefore(end);
          } else {
            dateMatches = false; // Wait for range input
          }
        }
      }

      final actorMatches = _selectedActorType == 'All' || log['actor_type'] == _selectedActorType;
      final eventMatches = _selectedEventType == 'All' || log['action'] == _selectedEventType;

      // Search matching
      bool searchMatches = true;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final actor = (log['actor'] ?? '').toString().toLowerCase();
        final action = (log['action'] ?? '').toString().toLowerCase();
        final details = (log['details'] ?? '').toString().toLowerCase();
        searchMatches = actor.contains(query) || action.contains(query) || details.contains(query);
      }

      return dateMatches && actorMatches && eventMatches && searchMatches;
    }).toList();
  }

  List<Map<String, dynamic>> get _paginatedLogs {
    final filtered = _filteredLogs;
    final startIndex = _currentPage * _rowsPerPage;
    if (startIndex >= filtered.length) return [];
    final endIndex = (startIndex + _rowsPerPage).clamp(0, filtered.length);
    return filtered.sublist(startIndex, endIndex);
  }

  // Count helper for KPIs
  int _countByActorType(String type) {
    return _auditLogs.where((l) => l['actor_type'] == type).length;
  }

  void _showLogDetailDialog(Map<String, dynamic> log) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String oldValStr = log['old_value'] != null ? const JsonEncoder.withIndent('  ').convert(log['old_value']) : '';
    final String newValStr = log['new_value'] != null ? const JsonEncoder.withIndent('  ').convert(log['new_value']) : '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Audit Event Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: Container(
            width: 550,
            constraints: const BoxConstraints(maxHeight: 500),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Event ID', log['id']),
                  _buildDetailRow('Timestamp', log['dateTime'].toString()),
                  _buildDetailRow('Actor Name', log['actor']),
                  _buildDetailRow('Actor Group', log['actor_type']),
                  _buildDetailRow('Action Type', log['action']),
                  _buildDetailRow('Severity', log['severity']),
                  _buildDetailRow('Entity Type', log['entity_type']),
                  const SizedBox(height: 16),
                  if (oldValStr.isNotEmpty) ...[
                    const Text('PREVIOUS VALUE (JSON)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black38 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        oldValStr,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (newValStr.isNotEmpty) ...[
                    const Text('UPDATED VALUE (JSON)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black38 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        newValStr,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (oldValStr.isEmpty && newValStr.isEmpty) ...[
                    const Text('DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(log['details'], style: const TextStyle(fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: log['id']));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Event ID copied to clipboard'), duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('Copy Event ID', style: TextStyle(fontSize: 11.5)),
            ),
            OutlinedButton.icon(
              onPressed: () {
                final summary = 'ID: ${log['id']}\nTime: ${log['dateTime']}\nActor: ${log['actor']} (${log['actor_type']})\nAction: ${log['action']}\nDetails: ${log['details']}';
                Clipboard.setData(ClipboardData(text: summary));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Audit Details copied to clipboard'), duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.content_copy, size: 14),
              label: const Text('Copy Details', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiBar(ThemeData theme, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final kpiCount = constraints.maxWidth < 600 ? 2 : 4;
        return GridView.count(
          crossAxisCount: kpiCount,
          childAspectRatio: constraints.maxWidth < 600 ? 2.5 : 3.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildSummaryCard('Total Logs', '${_auditLogs.length}', Icons.list_alt_outlined, AppColors.primary, theme, isDark),
            _buildSummaryCard('Admin Logs', '${_countByActorType("ADMIN")}', Icons.admin_panel_settings_outlined, Colors.indigo, theme, isDark),
            _buildSummaryCard('Faculty Logs', '${_countByActorType("FACULTY")}', Icons.person_search_outlined, Colors.orange, theme, isDark),
            _buildSummaryCard('System Logs', '${_countByActorType("SYSTEM")}', Icons.settings_suggest_outlined, Colors.blue, theme, isDark),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color, ThemeData theme, bool isDark) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      color: color.withOpacity(isDark ? 0.05 : 0.02),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityBadge(String severity) {
    Color bg = Colors.blue.withOpacity(0.1);
    Color fg = Colors.blue;
    if (severity == 'WARNING') {
      bg = Colors.orange.withOpacity(0.1);
      fg = Colors.orange;
    } else if (severity == 'CRITICAL') {
      bg = Colors.red.withOpacity(0.1);
      fg = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        severity,
        style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold),
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
            Icon(Icons.policy_outlined, size: 64, color: theme.disabledColor.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'No Audit Logs Found',
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _selectedActorType != 'All' || _selectedEventType != 'All'
                  ? 'No audit log items match your search queries or filter selections. Try clearing filters.'
                  : 'No logs recorded yet for this date range preset.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: theme.disabledColor),
            ),
            const SizedBox(height: 20),
            if (_searchQuery.isNotEmpty || _selectedActorType != 'All' || _selectedEventType != 'All' || _selectedDatePreset != 'Today')
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                    _selectedActorType = 'All';
                    _selectedEventType = 'All';
                    _selectedDatePreset = 'Today';
                    _currentPage = 0;
                  });
                  _fetchAuditLogs();
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('Reset Dashboard Filters'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableViewLayout(ThemeData theme, bool isDark) {
    final paginated = _paginatedLogs;
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
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 60),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF1E1E24) : Colors.grey.shade50),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                DataColumn(label: Text('Actor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                DataColumn(label: Text('Group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                DataColumn(label: Text('Severity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                DataColumn(label: Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
              ],
              rows: paginated.map((log) {
                return DataRow(
                  cells: [
                    DataCell(Text(log['dateTime'].toString().split(' ')[1].substring(0, 8), style: const TextStyle(fontSize: 11.5, color: Colors.grey))),
                    DataCell(Text(log['actor'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.backgroundDark : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(log['actor_type'], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    DataCell(Text(log['action'], style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    DataCell(_buildSeverityBadge(log['severity'])),
                    DataCell(
                      SizedBox(
                        width: 250,
                        child: Text(
                          log['details'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        onPressed: () => _showLogDetailDialog(log),
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

  Widget _buildTimelineViewLayout(ThemeData theme, bool isDark) {
    final paginated = _paginatedLogs;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: paginated.length,
      itemBuilder: (context, index) {
        final log = paginated[index];
        return Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: log['color'].withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(log['icon'], size: 16, color: log['color']),
                    ),
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
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Card(
                      child: InkWell(
                        onTap: () => _showLogDetailDialog(log),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        log['actor'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? AppColors.backgroundDark : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          log['actor_type'],
                                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    "${log['dateTime'].toString().split(' ')[0]} • ${log['time']}",
                                    style: AppTypography.caption,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    log['action'].replaceAll('_', ' '),
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  _buildSeverityBadge(log['severity']),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                log['details'],
                                style: TextStyle(
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filtered = _filteredLogs;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title block
          Text(
            'System Audit Logs',
            style: AppTypography.h2.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          Text(
            'Chronological audit trail of security, configuration alterations, and daily attendance calculations.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),

          // KPI Dashboard counters
          _buildKpiBar(theme, isDark),
          const SizedBox(height: 16),

          // Filters Card
          Card(
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
                            hintText: 'Search logs by actor, action name, or details...',
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
                      const SizedBox(width: 12),
                      // View Mode Toggle
                      ChoiceChip(
                        avatar: Icon(_isTableView ? Icons.list : Icons.table_chart, size: 14),
                        label: Text(_isTableView ? 'Timeline View' : 'Table View', style: const TextStyle(fontSize: 12)),
                        selected: _isTableView,
                        onSelected: (val) {
                          setState(() {
                            _isTableView = val;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 700;
                      
                      final dateDropdown = AppDropdownFormField<String>(
                        value: _selectedDatePreset,
                        label: 'Preset range',
                        items: _datePresets.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) async {
                          setState(() => _selectedDatePreset = val!);
                          if (val == 'Custom Range') {
                            await _selectCustomDateRange();
                          } else {
                            setState(() {
                              _currentPage = 0;
                            });
                          }
                        },
                      );
                      
                      final actorDropdown = AppDropdownFormField<String>(
                        value: _selectedActorType,
                        label: 'Actor Group',
                        items: _actorTypes.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() {
                          _selectedActorType = val!;
                          _currentPage = 0;
                        }),
                      );
                      
                      final eventDropdown = AppDropdownFormField<String>(
                        value: _selectedEventType,
                        label: 'Action Filter',
                        items: _eventTypes.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() {
                          _selectedEventType = val!;
                          _currentPage = 0;
                        }),
                      );

                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(child: dateDropdown),
                            const SizedBox(width: 12),
                            Expanded(child: actorDropdown),
                            const SizedBox(width: 12),
                            Expanded(child: eventDropdown),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            dateDropdown,
                            const SizedBox(height: 12),
                            actorDropdown,
                            const SizedBox(height: 12),
                            eventDropdown,
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // core layout display
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: SkeletonCardList(itemCount: 4),
            )
          else if (_errorMessage != null && _auditLogs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _fetchAuditLogs,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            _buildEmptyState(theme, isDark)
          else ...[
            if (_isTableView)
              _buildTableViewLayout(theme, isDark)
            else
              _buildTimelineViewLayout(theme, isDark),

            // Pagination Controls footer
            if (filtered.length > _rowsPerPage)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: _currentPage > 0
                          ? () {
                              setState(() {
                                _currentPage--;
                              });
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Page ${_currentPage + 1} of ${((filtered.length - 1) / _rowsPerPage).floor() + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: (_currentPage + 1) * _rowsPerPage < filtered.length
                          ? () {
                              setState(() {
                                _currentPage++;
                              });
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

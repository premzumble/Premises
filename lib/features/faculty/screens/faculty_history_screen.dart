import 'package:flutter/material.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/dropdown.dart';
import '../../../core/widgets/premises_loader.dart';
import '../../../core/widgets/skeleton_loader.dart';

class FacultyHistoryScreen extends StatefulWidget {
  const FacultyHistoryScreen({super.key});

  @override
  State<FacultyHistoryScreen> createState() => _FacultyHistoryScreenState();
}

class _FacultyHistoryScreenState extends State<FacultyHistoryScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Pagination & Filtering state
  String _rangeType = 'month'; // today, week, month, custom
  DateTimeRange? _customDateRange;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  List<dynamic> _records = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? start;
      String? end;
      if (_rangeType == 'custom' && _customDateRange != null) {
        start = _customDateRange!.start.toIso8601String().split('T').first;
        end = _customDateRange!.end.toIso8601String().split('T').first;
      }

      final data = await ApiService.fetchAttendanceHistory(
        rangeType: _rangeType,
        startDate: start,
        endDate: end,
        page: _currentPage,
      );

      setState(() {
        _records = data['records'] as List<dynamic>;
        _totalCount = data['total'] as int;
        final limit = data['limit'] as int;
        _totalPages = (_totalCount / limit).ceil();
        if (_totalPages < 1) _totalPages = 1;
      });
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load attendance history.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onRangeChanged(String? range) {
    if (range == null) return;
    setState(() {
      _rangeType = range;
      _currentPage = 1;
    });
    if (range != 'custom') {
      _loadHistory();
    } else {
      _selectCustomDateRange();
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customDateRange ?? DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _currentPage = 1;
      });
      _loadHistory();
    } else {
      setState(() {
        _rangeType = 'month'; // Revert back
      });
      _loadHistory();
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      setState(() => _currentPage++);
      _loadHistory();
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter card
          Card(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  final filterLabel = Text(
                    'Filter Range:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  );
                  final dropdown = AppDropdownFormField<String>(
                    value: _rangeType,
                    fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    items: const [
                      DropdownMenuItem(value: 'today', child: Text('Today')),
                      DropdownMenuItem(value: 'week', child: Text('Past Week')),
                      DropdownMenuItem(value: 'month', child: Text('Past Month')),
                      DropdownMenuItem(value: 'custom', child: Text('Custom Range...')),
                    ],
                    onChanged: _onRangeChanged,
                  );
                  final rangeText = (_rangeType == 'custom' && _customDateRange != null)
                      ? Text(
                          'Selected: ${_formatDate(_customDateRange!.start)} to ${_formatDate(_customDateRange!.end)}',
                          style: AppTypography.caption,
                        )
                      : const SizedBox.shrink();

                  return isWide
                      ? Row(
                          children: [
                            filterLabel,
                            const SizedBox(width: 16),
                            dropdown,
                            const Spacer(),
                            rangeText,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                filterLabel,
                                dropdown,
                              ],
                            ),
                            if (_rangeType == 'custom' && _customDateRange != null) ...[
                              const SizedBox(height: 8),
                              rangeText,
                            ],
                          ],
                        );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main history list / table
          Expanded(
            child: Card(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: _buildHistoryContent(theme, isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryContent(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: SkeletonCardList(itemCount: 4),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: AppTypography.bodyLarge),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: isDark ? Colors.grey[700] : Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No attendance records found for this range.',
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Check-In', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Check-Out', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Duration', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Excusal Details', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _records.map((r) {
                  final statusText = r['status']?.toString() ?? 'ABSENT';
                  return DataRow(
                    cells: [
                      DataCell(Text(r['date'] ?? '')),
                      DataCell(Text(_formatTime(r['check_in']))),
                      DataCell(Text(_formatTime(r['check_out']))),
                      DataCell(Text(r['working_duration'] ?? '00h 00m')),
                      DataCell(_buildStatusBadge(statusText, r['is_overridden'] == true)),
                      DataCell(_buildExcusalCell(r, theme, isDark)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        // Pagination Bar
        Divider(color: isDark ? AppColors.borderDark : AppColors.borderLight, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Records: $_totalCount',
                style: AppTypography.caption,
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentPage > 1 ? _prevPage : null,
                  ),
                  Text('Page $_currentPage of $_totalPages', style: AppTypography.bodyMedium),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage < _totalPages ? _nextPage : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status, bool isOverridden) {
    Color bg;
    Color fg;
    switch (status) {
      case 'PRESENT':
        bg = AppColors.success.withOpacity(0.12);
        fg = AppColors.success;
        break;
      case 'HALF_DAY':
        bg = Colors.orange.withOpacity(0.12);
        fg = Colors.orange;
        break;
      case 'ABSENT':
      default:
        bg = AppColors.danger.withOpacity(0.12);
        fg = AppColors.danger;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (isOverridden) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'OVERRIDE',
              style: TextStyle(
                color: Colors.indigo,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExcusalCell(Map<String, dynamic> r, ThemeData theme, bool isDark) {
    final submitted = r['reason_submitted'] as String?;
    final decision = r['admin_decision'] as String?;

    if (submitted == null) {
      return const Text('N/A', style: TextStyle(color: Colors.grey));
    }

    Color decisionColor = Colors.grey;
    if (decision == 'APPROVED') decisionColor = AppColors.success;
    if (decision == 'REJECTED') decisionColor = AppColors.danger;
    if (decision == 'PENDING') decisionColor = Colors.orange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(submitted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        Text(
          'Decision: ${decision ?? "PENDING"}',
          style: TextStyle(color: decisionColor, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }
}

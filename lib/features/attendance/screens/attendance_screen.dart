import 'package:flutter/material.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/api_service.dart';

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


  @override
  void initState() {
    super.initState();
    _fetchAttendanceLogs();
  }

  Future<void> _fetchAttendanceLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final formattedDate =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    try {
      final res = await ApiService.get('/admin/attendance-logs?target_date=$formattedDate&page=$_currentPage&page_size=$_pageSize');
      if (res['success'] == true && res['data'] != null) {
        if (mounted) {
          setState(() {
            final data = res['data'];
            if (data is Map) {
              _dailyRecords = data['items'] ?? [];
              _currentPage = data['page'] ?? 1;
              _pageSize = data['page_size'] ?? 25;
              _totalItems = data['total'] ?? 0;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateString = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Picker Row
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
        const SizedBox(height: 24),

        // List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null && _dailyRecords.isEmpty
                  ? Center(
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
                    )
                  : _dailyRecords.isEmpty
                      ? const Center(
                          child: Text(
                            'No attendance records found for this date.',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        )
                      : ListView.separated(
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
                                    title: Text(
                                      record['name'] ?? 'Unknown Faculty',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
        ),
        if (_totalItems > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
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
}

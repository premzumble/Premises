import 'package:flutter/material.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/api_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _selectedDatePreset = 'Today';
  String _selectedEventType = 'All';
  String _selectedActorType = 'All';
  bool _isLoading = true;
  String? _errorMessage;

  final List<String> _datePresets = ['Today', 'Yesterday', 'Last 7 Days', 'Custom Range'];
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

  @override
  void initState() {
    super.initState();
    _fetchAuditLogs();
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
              String datePreset = 'Custom Range';
              String timeStr = '12:00 AM';
              if (rawTime != null) {
                try {
                  final dt = DateTime.parse(rawTime.toString()).toLocal();
                  final now = DateTime.now();
                  final diff = DateTime(now.year, now.month, now.day).difference(DateTime(dt.year, dt.month, dt.day));
                  if (diff.inDays == 0) {
                    datePreset = 'Today';
                  } else if (diff.inDays == 1) {
                    datePreset = 'Yesterday';
                  } else if (diff.inDays <= 7) {
                    datePreset = 'Last 7 Days';
                  } else {
                    datePreset = 'Custom Range';
                  }
                  
                  final hr = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
                  final min = dt.minute.toString().padLeft(2, '0');
                  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
                  timeStr = "${hr.toString().padLeft(2, '0')}:$min $ampm";
                } catch (_) {}
              }
              
              final action = (item['action'] ?? '').toString();
              IconData icon = Icons.info_outline;
              Color color = Colors.grey;
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
              } else if (action.contains('DEVICE') || action.contains('REGISTER_DEVICE')) {
                icon = Icons.phone_android_outlined;
                color = Colors.purple;
              } else if (action.contains('POLICY')) {
                icon = Icons.policy_outlined;
                color = Colors.orange;
              } else if (action.contains('APPROVE') || action.contains('REJECT')) {
                icon = Icons.assignment_turned_in_outlined;
                color = Colors.green;
              }
              
              return {
                'id': item['id']?.toString() ?? '',
                'time': timeStr,
                'date': datePreset,
                'actor': item['actor']?.toString() ?? 'System',
                'actor_type': item['actor_type']?.toString() ?? 'SYSTEM',
                'action': action,
                'details': item['details']?.toString() ?? '',
                'icon': icon,
                'color': color,
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

  List<Map<String, dynamic>> get _filteredLogs {
    return _auditLogs.where((log) {
      final dateMatches = _selectedDatePreset == 'All' || log['date'] == _selectedDatePreset || _selectedDatePreset == 'Last 7 Days';
      final actorMatches = _selectedActorType == 'All' || log['actor_type'] == _selectedActorType;
      final eventMatches = _selectedEventType == 'All' || log['action'] == _selectedEventType;
      return dateMatches && actorMatches && eventMatches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filtered = _filteredLogs;

    return Column(
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
        const SizedBox(height: 20),

        // Filters Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                
                final dateDropdown = DropdownButtonFormField<String>(
                  value: _selectedDatePreset,
                  decoration: const InputDecoration(labelText: 'Preset range', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  items: _datePresets.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setState(() => _selectedDatePreset = val!),
                );
                
                final actorDropdown = DropdownButtonFormField<String>(
                  value: _selectedActorType,
                  decoration: const InputDecoration(labelText: 'Actor Group', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  items: _actorTypes.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setState(() => _selectedActorType = val!),
                );
                
                final eventDropdown = DropdownButtonFormField<String>(
                  value: _selectedEventType,
                  decoration: const InputDecoration(labelText: 'Action Filter', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  items: _eventTypes.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setState(() => _selectedEventType = val!),
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
          ),
        ),
        const SizedBox(height: 20),

        // Timeline Feed
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null && _auditLogs.isEmpty
                  ? Center(
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
                    )
                  : filtered.isEmpty
                      ? const Center(child: Text('No audit logs matched current query parameters.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final log = filtered[index];
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final isWide = constraints.maxWidth > 500;
                                            final actorBlock = Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    log['actor'],
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? AppColors.backgroundDark : Colors.grey.shade100,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                                                  ),
                                                  child: Text(
                                                    log['actor_type'],
                                                    style: TextStyle(
                                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight, 
                                                      fontSize: 9, 
                                                      fontWeight: FontWeight.bold
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                            final dateBlock = Text(
                                              "${log['date']} • ${log['time']}",
                                              style: AppTypography.caption,
                                            );

                                            return isWide
                                                ? Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Expanded(child: actorBlock),
                                                      const SizedBox(width: 8),
                                                      dateBlock,
                                                    ],
                                                  )
                                                : Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      actorBlock,
                                                      const SizedBox(height: 6),
                                                      dateBlock,
                                                    ],
                                                  );
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          log['action'].replaceAll('_', ' '),
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

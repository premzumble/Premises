import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/app_config.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/session_manager.dart';

/// Admin-only developer tool screen that simulates geofence entry/exit
/// events for testing the attendance pipeline without physical movement.
/// Only visible in debug builds (kDebugMode == true).
class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  final String _baseUrl = kBaseUrl;

  // Faculty list
  bool _loadingFaculty = false;
  List<Map<String, dynamic>> _facultyList = [];
  String? _selectedFacultyId;
  String? _selectedFacultyName;

  // Event log
  final List<_SimEvent> _events = [];

  // State
  bool _isRunning = false;
  Timer? _autoExitTimer;
  int _autoExitCountdown = 0;
  bool _autoExitEnabled = false;
  int _autoExitSeconds = 30;

  @override
  void initState() {
    super.initState();
    _loadFaculty();
  }

  @override
  void dispose() {
    _autoExitTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, String>> get _headers async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${SessionManager.accessToken ?? ''}',
    };
  }

  Future<void> _loadFaculty() async {
    setState(() => _loadingFaculty = true);
    try {
      final headers = await _headers;
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/admin/faculty?status=APPROVED&limit=100'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = (data['data'] as List?) ?? [];
        setState(() {
          _facultyList = items
              .map<Map<String, dynamic>>((e) => {
                    'id': e['id'],
                    'name': '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
                    'email': e['email'] ?? '',
                    'department': e['department'] ?? '',
                  })
              .toList();
          if (_facultyList.isNotEmpty) {
            _selectedFacultyId = _facultyList.first['id'];
            _selectedFacultyName = _facultyList.first['name'];
          }
        });
      } else {
        _addEvent(_SimEvent(
          type: _EventType.error,
          message: 'Failed to load faculty list: ${response.statusCode}',
        ));
      }
    } catch (e) {
      _addEvent(_SimEvent(type: _EventType.error, message: 'Error: $e'));
    } finally {
      setState(() => _loadingFaculty = false);
    }
  }

  void _addEvent(_SimEvent event) {
    setState(() => _events.insert(0, event));
  }

  Future<void> _simulateCheckIn() async {
    if (_selectedFacultyId == null) return;
    setState(() => _isRunning = true);
    _addEvent(_SimEvent(
      type: _EventType.info,
      message: '▶ Simulating GEOFENCE ENTRY for $_selectedFacultyName...',
    ));

    try {
      final headers = await _headers;
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/attendance/check-in'),
        headers: headers,
        body: json.encode({
          'faculty_id': _selectedFacultyId,
          'latitude': 18.403817,
          'longitude': 76.560943,
          'simulated': true,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        _addEvent(_SimEvent(
          type: _EventType.success,
          message: '✓ CHECK-IN successful for $_selectedFacultyName\n'
              '  Record ID: ${data['data']?['id'] ?? 'N/A'}\n'
              '  Time: ${data['data']?['check_in_time'] ?? 'N/A'}',
        ));
        if (_autoExitEnabled) {
          _startAutoExit();
        }
      } else {
        _addEvent(_SimEvent(
          type: _EventType.warning,
          message: '⚠ Check-in returned: ${data['message'] ?? response.body}',
        ));
      }
    } catch (e) {
      _addEvent(_SimEvent(type: _EventType.error, message: '✗ Check-in failed: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _simulateCheckOut() async {
    if (_selectedFacultyId == null) return;
    _autoExitTimer?.cancel();
    setState(() {
      _isRunning = true;
      _autoExitCountdown = 0;
    });
    _addEvent(_SimEvent(
      type: _EventType.info,
      message: '◀ Simulating GEOFENCE EXIT for $_selectedFacultyName...',
    ));

    try {
      final headers = await _headers;
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/attendance/check-out'),
        headers: headers,
        body: json.encode({
          'faculty_id': _selectedFacultyId,
          'latitude': 18.390000,
          'longitude': 76.545000,
          'simulated': true,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        _addEvent(_SimEvent(
          type: _EventType.success,
          message: '✓ CHECK-OUT successful for $_selectedFacultyName\n'
              '  Duration: ${data['data']?['working_hours'] ?? 'N/A'} hrs\n'
              '  Status: ${data['data']?['status'] ?? 'N/A'}',
        ));
      } else {
        _addEvent(_SimEvent(
          type: _EventType.warning,
          message: '⚠ Check-out returned: ${data['message'] ?? response.body}',
        ));
      }
    } catch (e) {
      _addEvent(_SimEvent(type: _EventType.error, message: '✗ Check-out failed: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _startAutoExit() {
    _autoExitTimer?.cancel();
    setState(() => _autoExitCountdown = _autoExitSeconds);
    _addEvent(_SimEvent(
      type: _EventType.info,
      message: '⏱ Auto check-out scheduled in $_autoExitSeconds seconds...',
    ));
    _autoExitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _autoExitCountdown--;
        if (_autoExitCountdown <= 0) {
          t.cancel();
          _autoExitCountdown = 0;
          _simulateCheckOut();
        }
      });
    });
  }

  void _cancelAutoExit() {
    _autoExitTimer?.cancel();
    setState(() => _autoExitCountdown = 0);
    _addEvent(_SimEvent(type: _EventType.warning, message: '✗ Auto check-out cancelled.'));
  }

  void _clearLog() {
    setState(() => _events.clear());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.science_outlined, color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Attendance Simulator', style: AppTypography.h2),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.deepPurple.withOpacity(0.4)),
                          ),
                          child: const Text(
                            'DEBUG ONLY',
                            style: TextStyle(
                              color: Colors.deepPurple,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Simulate geofence entry/exit events for faculty members',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 320, child: _buildControlPanel(theme, isDark)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildEventLog(theme, isDark)),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildControlPanel(theme, isDark),
                      const SizedBox(height: 16),
                      Expanded(child: _buildEventLog(theme, isDark)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.deepPurple.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Target Faculty',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _loadingFaculty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : DropdownButtonFormField<String>(
                  value: _selectedFacultyId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    prefixIcon: const Icon(Icons.person_outline, size: 18),
                  ),
                  hint: const Text('Select faculty member', style: TextStyle(fontSize: 13)),
                  items: _facultyList
                      .map((f) => DropdownMenuItem<String>(
                            value: f['id'] as String,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  f['name'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  f['email'] as String,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedFacultyId = val;
                      _selectedFacultyName = _facultyList
                          .firstWhere((f) => f['id'] == val, orElse: () => {'name': ''})['name'];
                    });
                  },
                ),
          const Divider(height: 28),

          // Auto-exit toggle
          const Text(
            'Auto Exit Timer',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: _autoExitEnabled,
                onChanged: (v) => setState(() => _autoExitEnabled = v),
                activeColor: Colors.deepPurple,
              ),
              const SizedBox(width: 8),
              const Text('Auto check-out after', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextFormField(
                  initialValue: _autoExitSeconds.toString(),
                  keyboardType: TextInputType.number,
                  enabled: _autoExitEnabled,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      _autoExitSeconds = parsed;
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              const Text('sec', style: TextStyle(fontSize: 12)),
            ],
          ),

          if (_autoExitCountdown > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Auto check-out in $_autoExitCountdown s',
                    style: const TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelAutoExit,
                    child: const Icon(Icons.close, color: Colors.orange, size: 16),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 28),

          // Action Buttons
          const Text(
            'Simulate Events',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_isRunning || _selectedFacultyId == null) ? null : _simulateCheckIn,
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Simulate Check-In (Enter Geofence)'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_isRunning || _selectedFacultyId == null) ? null : _simulateCheckOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Simulate Check-Out (Exit Geofence)'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          if (_isRunning) ...[
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Processing event...', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventLog(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  'Event Log',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (_events.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearLog,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.science_outlined, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'No events yet. Select a faculty member\nand simulate an attendance event.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return _buildEventTile(event, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(_SimEvent event, bool isDark) {
    Color color;
    Color bgColor;
    switch (event.type) {
      case _EventType.success:
        color = AppColors.success;
        bgColor = AppColors.success.withOpacity(0.08);
        break;
      case _EventType.error:
        color = AppColors.danger;
        bgColor = AppColors.danger.withOpacity(0.08);
        break;
      case _EventType.warning:
        color = Colors.orange;
        bgColor = Colors.orange.withOpacity(0.08);
        break;
      case _EventType.info:
        color = AppColors.primary;
        bgColor = AppColors.primary.withOpacity(0.08);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(_eventIcon(event.type), size: 12, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(event.timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(_EventType type) {
    switch (type) {
      case _EventType.success:
        return Icons.check;
      case _EventType.error:
        return Icons.close;
      case _EventType.warning:
        return Icons.warning_amber;
      case _EventType.info:
        return Icons.info_outline;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

enum _EventType { success, error, warning, info }

class _SimEvent {
  final _EventType type;
  final String message;
  final DateTime timestamp;

  _SimEvent({required this.type, required this.message}) : timestamp = DateTime.now();
}

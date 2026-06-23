import 'package:flutter/material.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/api_service.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _errorMessage;

  List<dynamic> _registrationRequests = [];
  List<dynamic> _deviceRequests = [];
  List<dynamic> _reasonRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllRequests() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final regRes = await ApiService.get('/admin/pending-registrations');
      final devRes = await ApiService.get('/admin/pending-device-swaps');
      final reasRes = await ApiService.get('/admin/pending-excusals');

      if (mounted) {
        setState(() {
          _registrationRequests = regRes['data'] as List<dynamic>;
          _deviceRequests = devRes['data'] as List<dynamic>;
          _reasonRequests = reasRes['data'] as List<dynamic>;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  String _formatDateOnly(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  Future<String?> _showRejectionReasonDialog(String name) async {
    final textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Reject Request', style: AppTypography.h3),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to reject the request for $name?'),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason (Optional)',
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            AppButton(
              text: 'Reject',
              onPressed: () => Navigator.of(context).pop(textController.text),
            ),
          ],
        );
      },
    );
  }

  Future<void> _approveRequest(String type, String id, String name) async {
    setState(() => _isLoading = true);
    try {
      String endpoint = '';
      if (type == 'registration') {
        endpoint = '/admin/approve-registration/$id';
      } else if (type == 'device') {
        endpoint = '/admin/approve-device-swap/$id';
      } else if (type == 'reason') {
        endpoint = '/admin/approve-excusal/$id';
      }

      await ApiService.post(endpoint, {});
      await _loadAllRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved request for $name.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to approve: ${e.toString()}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectRequest(String type, String id, String name) async {
    final reason = await _showRejectionReasonDialog(name);
    if (reason == null) return; // cancelled

    setState(() => _isLoading = true);
    try {
      String endpoint = '';
      if (type == 'registration') {
        endpoint = '/admin/reject-registration/$id';
      } else if (type == 'device') {
        endpoint = '/admin/reject-device-swap/$id';
      } else if (type == 'reason') {
        endpoint = '/admin/reject-excusal/$id';
      }

      await ApiService.post(endpoint, {'rejection_reason': reason});
      await _loadAllRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejected request for $name.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reject: ${e.toString()}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadAllRequests,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Block
          Text(
            'Approvals Queue',
            style: AppTypography.h2.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          Text(
            'Validate new accounts, device swaps, and out-of-geofence submissions.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 20),

          // Tabs
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: theme.colorScheme.primary,
            indicatorWeight: 3,
            dividerColor: isDark ? AppColors.borderDark : AppColors.borderLight,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Faculty Registrations (${_registrationRequests.length})'),
              Tab(text: 'Device Swaps (${_deviceRequests.length})'),
              Tab(text: 'Geofence Excusals (${_reasonRequests.length})'),
            ],
          ),
          const SizedBox(height: 20),

          // Error banner
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),

          // Tab views
          Expanded(
            child: _isLoading && _registrationRequests.isEmpty && _deviceRequests.isEmpty && _reasonRequests.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRegistrationTab(theme),
                      _buildDeviceTab(theme),
                      _buildReasonTab(theme),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationTab(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (_registrationRequests.isEmpty) {
      return const Center(child: Text('No pending faculty registrations.'));
    }

    return ListView.builder(
      itemCount: _registrationRequests.length,
      itemBuilder: (context, index) {
        final req = _registrationRequests[index];
        final id = req['id'].toString();
        final name = req['name']?.toString() ?? 'Unknown';
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_formatTime(req['time']?.toString() ?? ''), style: AppTypography.caption),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Email: ${req['email'] ?? ""}', style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight, fontSize: 13)),
                Text('Assigned Department: ${req['dept'] ?? ""}', style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight, fontSize: 13)),
                Text('Organization: ${req['org_name'] ?? ""}', style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight, fontSize: 13)),
                const Divider(height: 24),
                _buildActionButtons(
                  onApprove: () => _approveRequest('registration', id, name),
                  onReject: () => _rejectRequest('registration', id, name),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceTab(ThemeData theme) {
    if (_deviceRequests.isEmpty) {
      return const Center(child: Text('No pending device binding approvals.'));
    }

    final isDark = theme.brightness == Brightness.dark;

    return ListView.builder(
      itemCount: _deviceRequests.length,
      itemBuilder: (context, index) {
        final req = _deviceRequests[index];
        final id = req['id'].toString();
        final name = req['faculty_name']?.toString() ?? 'Unknown';
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_formatTime(req['time']?.toString() ?? ''), style: AppTypography.caption),
                  ],
                ),
                const SizedBox(height: 12),
                _buildFieldPair(theme, 'Email:', req['email']?.toString() ?? ''),
                _buildFieldPair(theme, 'Old Device (Active):', req['old_device']?.toString() ?? 'None'),
                _buildFieldPair(theme, 'New Device Requested:', req['new_device']?.toString() ?? ''),
                _buildFieldPair(theme, 'Reason Specified:', req['reason']?.toString() ?? 'No reason specified'),
                const Divider(height: 24),
                _buildActionButtons(
                  onApprove: () => _approveRequest('device', id, name),
                  onReject: () => _rejectRequest('device', id, name),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReasonTab(ThemeData theme) {
    if (_reasonRequests.isEmpty) {
      return const Center(child: Text('No pending geofence reason approvals.'));
    }

    final isDark = theme.brightness == Brightness.dark;

    return ListView.builder(
      itemCount: _reasonRequests.length,
      itemBuilder: (context, index) {
        final req = _reasonRequests[index];
        final id = req['id'].toString();
        final name = req['faculty_name']?.toString() ?? 'Unknown';
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_formatTime(req['time']?.toString() ?? ''), style: AppTypography.caption),
                  ],
                ),
                const SizedBox(height: 12),
                _buildFieldPair(theme, 'Attendance Date:', _formatDateOnly(req['date']?.toString() ?? '')),
                _buildFieldPair(theme, 'Violation Type:', (req['reason_type']?.toString() ?? '').replaceAll('_', ' ')),
                _buildFieldPair(theme, 'Faculty Explanation:', '"${req['notes']?.toString() ?? ""}"'),
                const Divider(height: 24),
                _buildActionButtons(
                  onApprove: () => _approveRequest('reason', id, name),
                  onReject: () => _rejectRequest('reason', id, name),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFieldPair(ThemeData theme, String label, String value) {
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final valueColor = isDark ? Colors.white70 : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: labelColor, fontSize: 13),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons({required VoidCallback onApprove, required VoidCallback onReject}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          text: 'Reject',
          variant: ButtonVariant.outline,
          onPressed: onReject,
        ),
        const SizedBox(width: 12),
        AppButton(
          text: 'Approve',
          onPressed: onApprove,
        ),
      ],
    );
  }
}

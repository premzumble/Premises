import 'package:flutter/material.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/premises_loader.dart';

class FacultyDeviceScreen extends StatefulWidget {
  const FacultyDeviceScreen({super.key});

  @override
  State<FacultyDeviceScreen> createState() => _FacultyDeviceScreenState();
}

class _FacultyDeviceScreenState extends State<FacultyDeviceScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.fetchDeviceHistory();
      setState(() {
        _devices = data;
      });
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load device history.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildContent(theme, isDark),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return const Center(child: PremisesBrandedLoader());
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
              onPressed: _loadDevices,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final activeDevice = _devices.firstWhere(
      (d) => d['is_active'] == true,
      orElse: () => {},
    );

    final previousDevices = _devices.where((d) => d['is_active'] == false).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Active Device', style: AppTypography.h3),
          const SizedBox(height: 12),
          if (activeDevice.isNotEmpty)
            _buildDeviceCard(activeDevice, theme, isDark, true)
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('No active device bound to this account.'),
              ),
            ),
          
          const SizedBox(height: 32),
          Text('Device History', style: AppTypography.h3),
          const SizedBox(height: 12),
          if (previousDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No previous devices recorded.',
                style: TextStyle(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                textAlign: TextAlign.center,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: previousDevices.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildDeviceCard(previousDevices[index], theme, isDark, false);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device, ThemeData theme, bool isDark, bool isActive) {
    return Card(
      elevation: isActive ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive 
          ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
          : BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  device['platform']?.toString().toLowerCase() == 'ios' 
                    ? Icons.apple 
                    : Icons.android,
                  size: 32,
                  color: isActive ? theme.colorScheme.primary : Colors.grey,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              device['device_model'] ?? 'Unknown Model',
                              style: AppTypography.h4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${device['manufacturer'] ?? ''} ${device['platform'] ?? ''} ${device['os_version'] ?? ''}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow('Identifier', device['device_identifier'] ?? 'N/A'),
            _buildDetailRow('Registered On', _formatDate(device['registered_at'])),
            if (!isActive)
              _buildDetailRow('Status', 'Deactivated', color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}

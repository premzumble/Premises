import 'package:flutter/material.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/session_manager.dart';
import '../../../core/widgets/premises_loader.dart';
import '../../../core/widgets/skeleton_loader.dart';

class FacultyNotificationsScreen extends StatefulWidget {
  const FacultyNotificationsScreen({super.key});

  @override
  State<FacultyNotificationsScreen> createState() => _FacultyNotificationsScreenState();
}

class _FacultyNotificationsScreenState extends State<FacultyNotificationsScreen> {
  bool _isLoading = true;
  bool _isLoadMore = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _notifications = [];
  
  final ScrollController _scrollController = ScrollController();
  int _skip = 0;
  final int _limit = 20;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadMore && _hasMore && !_isLoading) {
        _loadNotifications(reset: false);
      }
    }
  }

  Future<void> _loadNotifications({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _skip = 0;
        _hasMore = true;
      });
    } else {
      setState(() {
        _isLoadMore = true;
      });
    }

    try {
      final list = await ApiService.fetchNotifications(skip: _skip, limit: _limit);
      setState(() {
        if (reset) {
          _notifications = list;
        } else {
          _notifications.addAll(list);
        }
        
        if (list.length < _limit) {
          _hasMore = false;
        }
        _skip += list.length;
        
        // Update unread count only from the full list if we have it, 
        // but here we only have the current page. 
        // For accurate badge we should rely on the navigation polling or a separate count endpoint.
        _updateBadgeCount();
      });
    } on ApiException catch (e) {
      if (reset) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (reset) setState(() => _errorMessage = 'Failed to load notifications.');
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadMore = false;
      });
    }
  }

  Future<void> _updateBadgeCount() async {
    // Re-fetch all to get accurate badge if needed, or just use what we have in memory
    // For now, let's just use the polling mechanism in FacultyNavigation to keep it sync.
  }

  Future<void> _markRead(String id) async {
    final index = _notifications.indexWhere((n) => n['id'] == id);
    if (index != -1 && _notifications[index]['read_at'] == null) {
      setState(() {
        _notifications[index]['read_at'] = DateTime.now().toUtc().toIso8601String();
        SessionManager.unreadNotifications.value = (SessionManager.unreadNotifications.value - 1).clamp(0, 999);
      });

      try {
        await ApiService.markNotificationAsRead(id);
      } catch (_) {
        _loadNotifications(reset: true);
      }
    }
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (var n in _notifications) {
        n['read_at'] ??= DateTime.now().toUtc().toIso8601String();
      }
      SessionManager.unreadNotifications.value = 0;
    });

    try {
      await ApiService.markAllNotificationsAsRead();
    } catch (_) {
      _loadNotifications(reset: true);
    }
  }

  Future<void> _deleteNotification(String id) async {
    final index = _notifications.indexWhere((n) => n['id'] == id);
    if (index == -1) return;

    final wasUnread = _notifications[index]['read_at'] == null;
    setState(() {
      _notifications.removeAt(index);
      if (wasUnread) {
        SessionManager.unreadNotifications.value = (SessionManager.unreadNotifications.value - 1).clamp(0, 999);
      }
    });

    try {
      await ApiService.deleteNotification(id);
    } catch (_) {
      _loadNotifications(reset: true);
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to permanently delete all notifications? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _notifications = [];
      SessionManager.unreadNotifications.value = 0;
      _hasMore = false;
    });

    try {
      await ApiService.clearAllNotifications();
    } catch (_) {
      _loadNotifications(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_notifications.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.red),
                  label: const Text('Clear all', style: TextStyle(fontSize: 12, color: Colors.red)),
                ),
                const SizedBox(width: 8),
              ],
              if (_notifications.any((n) => n['read_at'] == null))
                TextButton.icon(
                  onPressed: _markAllRead,
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadNotifications(reset: true),
        child: _buildContent(isDark, theme),
      ),
    );
  }

  Widget _buildContent(bool isDark, ThemeData theme) {
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
            ElevatedButton(onPressed: () => _loadNotifications(reset: true), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_off_outlined, size: 48, color: isDark ? Colors.grey[700] : Colors.grey[400]),
                const SizedBox(height: 16),
                Text('You have no notifications yet.', style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _notifications.length + (_isLoadMore ? 1 : 0),
      padding: const EdgeInsets.only(bottom: 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        if (index == _notifications.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final n = _notifications[index];
        final id = n['id'] as String;
        final isUnread = n['read_at'] == null;
        final type = n['type'] as String? ?? 'INFO';

        return Dismissible(
          key: Key('notif_$id'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _deleteNotification(id),
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          child: Card(
            elevation: isUnread ? 2 : 0,
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isUnread
                  ? BorderSide(color: theme.colorScheme.primary.withOpacity(0.5), width: 1.5)
                  : BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
            child: InkWell(
              onTap: isUnread ? () => _markRead(id) : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIcon(type),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n['title'] ?? 'Notification',
                                  style: TextStyle(
                                    fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 15,
                                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                  ),
                                ),
                              ),
                              if (isUnread)
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n['message'] ?? '',
                            style: TextStyle(fontSize: 13, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatSentAt(n['sent_at']),
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                          ),
                          
                          if (type == 'ATTENDANCE_OVERRIDE') ...[
                            const SizedBox(height: 12),
                            if (n['acknowledged_at'] == null)
                              ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    await ApiService.acknowledgeNotification(id);
                                    setState(() {
                                      n['acknowledged_at'] = DateTime.now().toUtc().toIso8601String();
                                    });
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to acknowledge: $e')),
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Acknowledge Receipt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              )
                            else
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Receipt Acknowledged',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'ATTENDANCE_OVERRIDE':
        icon = Icons.edit_calendar_outlined;
        color = Colors.indigo;
        break;
      case 'SECURITY':
      case 'ALERT':
        icon = Icons.security_outlined;
        color = AppColors.danger;
        break;
      case 'ATTENDANCE':
      case 'ENTRY':
      case 'APPROVAL':
        icon = Icons.check_circle_outline;
        color = AppColors.success;
        break;
      case 'EXIT':
      case 'WARNING':
      case 'REJECTION':
        icon = Icons.warning_amber_outlined;
        color = Colors.orange;
        break;
      case 'REMINDER':
        icon = Icons.alarm_outlined;
        color = Colors.blue;
        break;
      default:
        icon = Icons.info_outline;
        color = Colors.grey;
        break;
    }
    return CircleAvatar(radius: 20, backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color, size: 20));
  }

  String _formatSentAt(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

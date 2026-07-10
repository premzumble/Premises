import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/session_manager.dart';
import '../../../core/services/notification_persistence_service.dart';
import '../../../core/services/notification_service.dart';

class FacultyNavigation extends StatefulWidget {
  final Widget child;
  final String location;

  const FacultyNavigation({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  State<FacultyNavigation> createState() => _FacultyNavigationState();
}

class _FacultyNavigationState extends State<FacultyNavigation> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
    // Poll notifications every 10 seconds for real-time badge updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _loadNotificationCount();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final list = await ApiService.fetchNotifications();
      final unreadCount = list.where((n) => n['read_at'] == null).length;
      SessionManager.unreadNotifications.value = unreadCount;

      // Check for new unread notifications to show as pop-ups
      for (var n in list) {
        if (n['read_at'] == null) {
          final id = n['id'] as String;
          final alreadyShown = await NotificationPersistenceService.isShown(id);
          
          if (!alreadyShown) {
            // Mark as shown immediately to prevent double pop-ups during async execution
            await NotificationPersistenceService.markAsShown(id);
            
            NotificationService.showNotification(
              id: id.hashCode, // Unique-ish ID for local notification
              title: n['title'] ?? 'Notification',
              body: n['message'] ?? '',
              payload: id,
            );
          }
        }
      }
    } catch (_) {
      // Ignore background fetch errors
    }
  }

  int _getSelectedIndex() {
    final loc = widget.location;
    if (loc.startsWith('/faculty/dashboard')) return 0;
    if (loc.startsWith('/faculty/history')) return 1;
    if (loc.startsWith('/faculty/notifications')) return 2;
    if (loc.startsWith('/faculty/device')) return 3;
    if (loc.startsWith('/faculty/profile')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/faculty/dashboard');
        break;
      case 1:
        context.go('/faculty/history');
        break;
      case 2:
        context.go('/faculty/notifications');
        break;
      case 3:
        context.go('/faculty/device');
        break;
      case 4:
        context.go('/faculty/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    
    final isMobile = width < 640;
    final isTablet = width >= 640 && width < 960;
    final isDesktop = width >= 960;

    final selectedIndex = _getSelectedIndex();

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 20,
                      width: 20,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Premises Faculty',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              actions: _buildAppBarActions(context),
            )
          : null,
      body: Row(
        children: [
          // Desktop Sidebar
          if (isDesktop)
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 26,
                            width: 26,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Premises',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSidebarCategory('Faculty Menu'),
                          _buildSidebarItem(0, Icons.home_outlined, 'My Presence', selectedIndex, context),
                          _buildSidebarItem(1, Icons.history, 'Attendance History', selectedIndex, context),
                          _buildSidebarItem(2, Icons.notifications_none_outlined, 'Notifications', selectedIndex, context),
                          _buildSidebarItem(3, Icons.phone_android_outlined, 'Device Management', selectedIndex, context),
                          _buildSidebarItem(4, Icons.person_outline, 'My Profile', selectedIndex, context),
                        ],
                      ),
                    ),
                  ),
                  _buildDesktopProfilePanel(context),
                ],
              ),
            ),

          // Tablet Navigation Rail
          if (isTablet)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor,
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.badge_outlined, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(height: 24),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (idx) => _onItemTapped(idx, context),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        const NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: Text('Presence', style: TextStyle(fontSize: 10)),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.history),
                          selectedIcon: Icon(Icons.history_toggle_off),
                          label: Text('History', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: ValueListenableBuilder<int>(
                            valueListenable: SessionManager.unreadNotifications,
                            builder: (context, count, child) {
                              return Badge(
                                label: Text('$count'),
                                isLabelVisible: count > 0,
                                child: const Icon(Icons.notifications_none_outlined),
                              );
                            },
                          ),
                          selectedIcon: ValueListenableBuilder<int>(
                            valueListenable: SessionManager.unreadNotifications,
                            builder: (context, count, child) {
                              return Badge(
                                label: Text('$count'),
                                isLabelVisible: count > 0,
                                child: const Icon(Icons.notifications),
                              );
                            },
                          ),
                          label: const Text('Alerts', style: TextStyle(fontSize: 10)),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.phone_android_outlined),
                          selectedIcon: Icon(Icons.phone_android),
                          label: Text('Device', style: TextStyle(fontSize: 10)),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.person_outline),
                          selectedIcon: Icon(Icons.person),
                          label: Text('Profile', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isMobile)
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Faculty Workspace',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onBackground,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const Spacer(),
                        ..._buildAppBarActions(context),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: selectedIndex,
              onTap: (idx) => _onItemTapped(idx, context),
              selectedItemColor: theme.colorScheme.primary,
              unselectedItemColor: Colors.grey,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Presence',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  activeIcon: Icon(Icons.history_toggle_off),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: ValueListenableBuilder<int>(
                    valueListenable: SessionManager.unreadNotifications,
                    builder: (context, count, child) {
                      return Badge(
                        label: Text('$count'),
                        isLabelVisible: count > 0,
                        child: const Icon(Icons.notifications_none_outlined),
                      );
                    },
                  ),
                  activeIcon: ValueListenableBuilder<int>(
                    valueListenable: SessionManager.unreadNotifications,
                    builder: (context, count, child) {
                      return Badge(
                        label: Text('$count'),
                        isLabelVisible: count > 0,
                        child: const Icon(Icons.notifications),
                      );
                    },
                  ),
                  label: 'Alerts',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.phone_android_outlined),
                  activeIcon: Icon(Icons.phone_android),
                  label: 'Device',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            )
          : null,
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(
          Theme.of(context).brightness == Brightness.dark
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
          size: 20,
        ),
        tooltip: 'Toggle Theme',
        onPressed: () {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final nextMode = isDark ? ThemeMode.light : ThemeMode.dark;
          themeNotifier.value = nextMode;
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString('theme_mode', nextMode == ThemeMode.dark ? 'dark' : 'light');
          });
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8.0, right: 12.0),
        child: ValueListenableBuilder<int>(
          valueListenable: SessionManager.unreadNotifications,
          builder: (context, count, child) {
            return Badge(
              label: Text('$count'),
              isLabelVisible: count > 0,
              child: IconButton(
                icon: const Icon(Icons.notifications_none_outlined, size: 20),
                onPressed: () => context.go('/faculty/notifications'),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildSidebarCategory(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onBackground.withOpacity(0.5),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    int index,
    IconData icon,
    String label,
    int selectedIndex,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = selectedIndex == index;

    Color itemColor;
    Color bg;
    Color borderAccentColor;

    if (isSelected) {
      if (isDark) {
        itemColor = const Color(0xFFFFFFFF); // Bug 2 selection: Pure White text
        bg = const Color(0xFF0056D2).withOpacity(0.10); // Sapphire Blue 10% opacity fill
        borderAccentColor = const Color(0xFF0056D2); // Sapphire Blue left accent indicator
      } else {
        itemColor = AppColors.primary;
        bg = AppColors.primary.withOpacity(0.06);
        borderAccentColor = AppColors.primary;
      }
    } else {
      itemColor = isDark
          ? const Color(0xFFA1A1AA) // Inactive sophisticated muted grey
          : AppColors.textSecondaryLight;
      bg = Colors.transparent;
      borderAccentColor = Colors.transparent;
    }

    Widget leadingWidget = Icon(icon, color: itemColor, size: 20);
    if (index == 2) {
      leadingWidget = ValueListenableBuilder<int>(
        valueListenable: SessionManager.unreadNotifications,
        builder: (context, count, child) {
          return Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: Icon(icon, color: itemColor, size: 20),
          );
        },
      );
    }

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: ListTile(
            dense: true,
            hoverColor: isDark ? Colors.white.withOpacity(0.04) : AppColors.primary.withOpacity(0.03),
            leading: leadingWidget,
            title: Text(
              label,
              style: AppTypography.bodyLarge.copyWith(
                color: itemColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            onTap: () => _onItemTapped(index, context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
        ),
        if (isSelected)
          Positioned(
            left: 0,
            top: 10,
            bottom: 10,
            child: Container(
              width: 3.0, // 3px thick left-border accent in Sapphire Blue
              decoration: BoxDecoration(
                color: borderAccentColor,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopProfilePanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = SessionManager.fullName ?? 'Faculty';
    final email = SessionManager.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'F';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Text(initial,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Theme Toggle Button
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () {
              final nextMode = isDark ? ThemeMode.light : ThemeMode.dark;
              themeNotifier.value = nextMode;
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString('theme_mode', nextMode == ThemeMode.dark ? 'dark' : 'light');
              });
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 18,
              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
            ),
            onSelected: (val) async {
              if (val == 'logout') {
                await SessionManager.clear();
                if (context.mounted) context.go('/login');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Logout',
                          style: TextStyle(fontSize: 13, color: Colors.red)),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

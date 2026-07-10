import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/input.dart';
import '../../../core/session_manager.dart';
import '../../../core/api_service.dart';
import '../../../core/app_config.dart';
import '../../../core/services/location_service.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../admin/walkthrough/controller/walkthrough_controller.dart';
import '../../admin/walkthrough/walkthrough_steps_definition.dart';
import '../../admin/walkthrough/widgets/walkthrough_tooltip.dart';
import '../widgets/google_map_editor.dart';
import '../../../core/widgets/premises_loader.dart';
import '../../../core/utils/platform_pointer_interceptor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Navigation Section State
  String _activeSection = 'General';
  final List<Map<String, dynamic>> _sections = [
    {'name': 'General', 'icon': Icons.tune},
    {'name': 'Attendance Policy', 'icon': Icons.policy_outlined},
    {'name': 'Working Hours', 'icon': Icons.access_time},
    {'name': 'Campus Geofence', 'icon': Icons.map_outlined},
    {'name': 'Departments', 'icon': Icons.business_outlined},
    {'name': 'Security', 'icon': Icons.shield_outlined},
    {'name': 'Notifications', 'icon': Icons.notifications_outlined},
    {'name': 'Account', 'icon': Icons.person_outline},
    if (kDebugMode) {'name': 'Developer Tools', 'icon': Icons.science_outlined},
  ];

  // General Settings State
  String _facultyRegistrationMode = 'ADMIN_APPROVAL';
  bool _allowExternalEmails = false;

  // Attendance Policy State
  final _allowedOutsideController = TextEditingController(text: '25');
  final _reminder1Controller = TextEditingController(text: '25');
  final _reminder2Controller = TextEditingController(text: '28');
  final _reminder3Controller = TextEditingController(text: '31');
  final _evaluationController = TextEditingController(text: '35');
  TimeOfDay _halfDayTime = const TimeOfDay(hour: 14, minute: 30);
  TimeOfDay _absentTime = const TimeOfDay(hour: 14, minute: 30);

  // Working Hours State
  TimeOfDay _workStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workEndTime = const TimeOfDay(hour: 17, minute: 0);

  // Campus Geofence State (Visual Configurator Variables)
  final _latitudeController = TextEditingController(text: '18.403817');
  final _longitudeController = TextEditingController(text: '76.560943');
  final _manualLatController = TextEditingController(text: '18.403817');
  final _manualLngController = TextEditingController(text: '76.560943');
  final _coordsFormKey = GlobalKey<FormState>();
  bool _hasGeofence = false;
  double? _savedLatitude;
  double? _savedLongitude;
  double? _savedRadiusMeters;
  double _radiusMeters = 500.0;
  final _searchController = TextEditingController();

  String _googleMapsApiKey = '';
  String _geofenceType = 'circle';
  List<dynamic>? _geofenceVertices;

  // Pending data from editor's onChangedData callback.
  // Stored separately to avoid feeding it back as props and creating
  // a setState→rebuild→didUpdateWidget→notifyChanged feedback loop.
  Map<String, dynamic>? _pendingEditorData;

  // Guard flag to suppress _onCoordsChanged during programmatic updates
  bool _suppressCoordsListener = false;

  // Guard flag: true while processing a notification FROM the editor
  // (onChangedData). Prevents didUpdateWidget from reacting to the rebuild
  // that onChangedData's setState triggers.
  bool _editorIsNotifying = false;

  final MapController _mapController = MapController();
  LatLng? _testLatLng;
  bool _isTestMode = false;
  String? _testResult;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSuggestions = false;
  bool _isSavingGeofence = false;
  bool _isLoadingGeofence = false;
  final String _baseUrl = kBaseUrl;
  bool _geofenceIsDirty = false;

  // Original saved configurations for dirty state checking
  double? _originalLatitude;
  double? _originalLongitude;
  double? _originalRadiusMeters;
  String? _originalGeofenceType;
  List<dynamic>? _originalGeofenceVertices;

  Future<void> _switchSection(String sectionName) async {
    if (_activeSection == 'Campus Geofence' && _geofenceIsDirty) {
      setMapPointerEvents(false); // Disable map pointer events to prevent iframe interception
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Padding(
          padding: const EdgeInsets.only(top: 40.0), // Margins the dialog slightly from the top edge
          child: AlertDialog(
            alignment: Alignment.topCenter, // Aligns dialog to the top center, keeping it off the map
            title: const Text('Unsaved Geofence Changes'),
            content: const Text(
              'You have unsaved changes in your campus geofence boundary configuration. '
              'Are you sure you want to discard them and switch sections?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFA1A1AA), // Neutral secondary style
                ),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  _restoreOriginalGeofenceState();
                  setState(() {
                    _activeSection = sectionName;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0056D2), // Primary action Sapphire Blue style
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                child: const Text('Discard'),
              ),
            ],
          ),
        ),
      ).then((_) {
        setMapPointerEvents(true); // Re-enable pointer events when the dialog is dismissed
      });
      return;
    }
    setState(() {
      _activeSection = sectionName;
    });
  }

  void _restoreOriginalGeofenceState() {
    _suppressCoordsListener = true;
    setState(() {
      _geofenceType = _originalGeofenceType ?? 'circle';
      _geofenceVertices = _originalGeofenceVertices;
      _savedLatitude = _originalLatitude;
      _savedLongitude = _originalLongitude;
      _savedRadiusMeters = _originalRadiusMeters;

      final lat = _originalLatitude ?? 18.403817;
      final lng = _originalLongitude ?? 76.560943;
      final rad = _originalRadiusMeters ?? 500.0;

      _latitudeController.text = lat.toStringAsFixed(6);
      _longitudeController.text = lng.toStringAsFixed(6);
      _manualLatController.text = lat.toStringAsFixed(6);
      _manualLngController.text = lng.toStringAsFixed(6);
      _radiusMeters = rad;
      _pendingEditorData = null;
      _geofenceIsDirty = false;
    });
    _suppressCoordsListener = false;
    try {
      _mapController.move(LatLng(_originalLatitude ?? 18.403817, _originalLongitude ?? 76.560943), 15.0);
    } catch (_) {}
  }

  // Departments State
  final List<String> _departments = [];
  final _newDeptController = TextEditingController();

  // Security Settings State
  bool _requireMfa = false;
  bool _restrictDevices = true;
  bool _logAdminActions = true;

  // Notifications Settings State
  bool _notifyOnDeviceChange = true;
  bool _notifyOnExitViolation = true;
  bool _notifyOnApprovals = true;

  // Department-wise policy selection
  String? _selectedPolicyDeptId;
  String _selectedPolicyDeptName = 'Organization Default';

  @override
  void initState() {
    super.initState();
    _latitudeController.addListener(_onCoordsChanged);
    _longitudeController.addListener(_onCoordsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllSettings();
      // Notify the walkthrough controller that Settings is now rendered.
      // The controller starts Phase 2 only when awaiting this signal.
      if (mounted) {
        WalkthroughController.instance.onSettingsReady(context);
      }
    });
  }

  @override
  void dispose() {
    _latitudeController.removeListener(_onCoordsChanged);
    _longitudeController.removeListener(_onCoordsChanged);
    _allowedOutsideController.dispose();
    _reminder1Controller.dispose();
    _reminder2Controller.dispose();
    _reminder3Controller.dispose();
    _evaluationController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _manualLatController.dispose();
    _manualLngController.dispose();
    _searchController.dispose();
    _newDeptController.dispose();
    super.dispose();
  }

  void _onCoordsChanged() {
    // Skip when the listener fires due to programmatic text changes
    // (e.g. during _fetchGeofence or search result selection)
    if (_suppressCoordsListener) return;

    final double? lat = double.tryParse(_latitudeController.text);
    final double? lng = double.tryParse(_longitudeController.text);
    if (lat != null && lng != null) {
      try {
        _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
      } catch (_) {}
      
      // Synchronize manual coordinates text fields
      if (_manualLatController.text != _latitudeController.text) {
        _manualLatController.text = _latitudeController.text;
      }
      if (_manualLngController.text != _longitudeController.text) {
        _manualLngController.text = _longitudeController.text;
      }
      setState(() {});
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // pi / 180
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) *
        (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742000 * math.asin(math.sqrt(a)); // 2 * R * 1000 where R = 6371 km
  }


  Future<String?> _getAuthToken() async {
    // Use the token already in session (set at login)
    if (SessionManager.accessToken != null) {
      return SessionManager.accessToken;
    }
    // No session — can't auto-authenticate, return null
    return null;
  }


  Future<void> _fetchGeofence() async {
    setState(() {
      _isLoadingGeofence = true;
    });
    final token = await _getAuthToken();
    if (token == null) {
      debugPrint('Could not authenticate with backend. Cannot fetch geofence.');
      setState(() {
        _isLoadingGeofence = false;
      });
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/geofence/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        if (resData['success'] == true && resData['data'] is List && (resData['data'] as List).isNotEmpty) {
          final geofence = resData['data'][0];
          if (geofence != null) {
            final String type = geofence['geofence_type'] as String? ?? 'circle';
            final List<dynamic>? vertices = geofence['vertices'];
            
            double lat = 18.403817;
            double lng = 76.560943;
            if (type == 'polygon' && vertices != null && vertices.isNotEmpty) {
              final centroid = _calculateCentroid(vertices);
              lat = centroid['latitude']!;
              lng = centroid['longitude']!;
            } else {
              lat = geofence['latitude'] != null ? (geofence['latitude'] as num).toDouble() : 18.403817;
              lng = geofence['longitude'] != null ? (geofence['longitude'] as num).toDouble() : 76.560943;
            }
            final double rad = geofence['radius_meters'] != null ? (geofence['radius_meters'] as num).toDouble() : 500.0;

            // Suppress coord listener to prevent duplicate map moves
            _suppressCoordsListener = true;
            setState(() {
              _savedLatitude = type == 'polygon' ? lat : (geofence['latitude'] != null ? lat : null);
              _savedLongitude = type == 'polygon' ? lng : (geofence['longitude'] != null ? lng : null);
              _savedRadiusMeters = geofence['radius_meters'] != null ? rad : null;
              _geofenceType = type;
              _geofenceVertices = vertices;

              _originalLatitude = _savedLatitude;
              _originalLongitude = _savedLongitude;
              _originalRadiusMeters = _savedRadiusMeters;
              _originalGeofenceType = type;
              _originalGeofenceVertices = vertices;
              _geofenceIsDirty = false;

              _pendingEditorData = null; // Reset pending data on fresh load
              _latitudeController.text = lat.toStringAsFixed(6);
              _longitudeController.text = lng.toStringAsFixed(6);
              _manualLatController.text = lat.toStringAsFixed(6);
              _manualLngController.text = lng.toStringAsFixed(6);
              _radiusMeters = rad;
              _hasGeofence = true;
            });
            _suppressCoordsListener = false;
            // Move map once after all state is set
            try {
              _mapController.move(LatLng(lat, lng), 15.0);
            } catch (_) {}
          }
        } else {
          _suppressCoordsListener = true;
          setState(() {
            _savedLatitude = null;
            _savedLongitude = null;
            _savedRadiusMeters = null;
            _geofenceType = 'circle';
            _geofenceVertices = null;

            _originalLatitude = null;
            _originalLongitude = null;
            _originalRadiusMeters = null;
            _originalGeofenceType = 'circle';
            _originalGeofenceVertices = null;
            _geofenceIsDirty = false;

            _pendingEditorData = null;
            _hasGeofence = false;
            _latitudeController.text = '18.403817';
            _longitudeController.text = '76.560943';
            _manualLatController.text = '18.403817';
            _manualLngController.text = '76.560943';
            _radiusMeters = 500.0;
          });
          _suppressCoordsListener = false;
          try {
            _mapController.move(const LatLng(18.403817, 76.560943), 15.0);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch geofences from backend: $e');
    } finally {
      setState(() {
        _isLoadingGeofence = false;
      });
    }
  }

  Future<void> _saveGeofence() async {
    // Use pending editor data if available (latest from onChangedData),
    // otherwise fall back to saved state (from last fetch/save response).
    final effectiveType = (_pendingEditorData?['geofence_type'] as String?) ?? _geofenceType;
    final effectiveVertices = _pendingEditorData?['vertices'] ?? _geofenceVertices;
    final effectiveLat = _pendingEditorData != null
        ? (_pendingEditorData!['latitude'] as num?)?.toDouble()
        : _savedLatitude;
    final effectiveLng = _pendingEditorData != null
        ? (_pendingEditorData!['longitude'] as num?)?.toDouble()
        : _savedLongitude;
    final effectiveRad = _pendingEditorData != null
        ? (_pendingEditorData!['radius_meters'] as num?)?.toDouble()
        : _savedRadiusMeters;

    final Map<String, dynamic> payload = {
      'geofence_type': effectiveType,
      'name': 'Campus Boundary',
      'is_active': true
    };
    if (effectiveType == 'circle') {
      payload['latitude'] = effectiveLat ?? 18.403817;
      payload['longitude'] = effectiveLng ?? 76.560943;
      payload['radius_meters'] = effectiveRad ?? 500.0;
      payload['vertices'] = null;
    } else {
      double? centroidLat;
      double? centroidLng;
      if (effectiveVertices != null && (effectiveVertices as List).isNotEmpty) {
        double latSum = 0.0;
        double lngSum = 0.0;
        for (final v in effectiveVertices) {
          final m = Map<String, dynamic>.from(v);
          latSum += (m['latitude'] as num).toDouble();
          lngSum += (m['longitude'] as num).toDouble();
        }
        centroidLat = latSum / effectiveVertices.length;
        centroidLng = lngSum / effectiveVertices.length;
      }
      payload['latitude'] = centroidLat;
      payload['longitude'] = centroidLng;
      payload['radius_meters'] = null;
      payload['vertices'] = effectiveVertices;
    }
    await _saveCustomGeofence(payload);
  }

  Map<String, double> _calculateCentroid(List<dynamic>? verticesList) {
    if (verticesList == null || verticesList.isEmpty) {
      return {'latitude': 18.403817, 'longitude': 76.560943};
    }
    double latSum = 0.0;
    double lngSum = 0.0;
    for (final v in verticesList) {
      final m = Map<String, dynamic>.from(v);
      latSum += (m['latitude'] as num).toDouble();
      lngSum += (m['longitude'] as num).toDouble();
    }
    return {
      'latitude': latSum / verticesList.length,
      'longitude': lngSum / verticesList.length,
    };
  }

  Future<void> _saveCustomGeofence(Map<String, dynamic> payload) async {
    setState(() {
      _isSavingGeofence = true;
    });

    final token = await _getAuthToken();
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to authenticate with backend.'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() {
        _isSavingGeofence = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/geofence/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
      );
      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        if (resData['success'] == true) {
          final savedGf = resData['data'];
          final type = savedGf['geofence_type'] ?? 'circle';
          final List<dynamic>? vertices = savedGf['vertices'];
          
          double? lat;
          double? lng;
          if (type == 'polygon' && vertices != null && vertices.isNotEmpty) {
            final centroid = _calculateCentroid(vertices);
            lat = centroid['latitude'];
            lng = centroid['longitude'];
          } else {
            lat = savedGf['latitude'] != null ? (savedGf['latitude'] as num).toDouble() : null;
            lng = savedGf['longitude'] != null ? (savedGf['longitude'] as num).toDouble() : null;
          }
          final rad = savedGf['radius_meters'] != null ? (savedGf['radius_meters'] as num).toDouble() : null;

          setState(() {
            _geofenceType = type;
            _savedLatitude = lat;
            _savedLongitude = lng;
            _savedRadiusMeters = rad;
            _geofenceVertices = vertices;

            _originalGeofenceType = type;
            _originalLatitude = lat;
            _originalLongitude = lng;
            _originalRadiusMeters = rad;
            _originalGeofenceVertices = vertices;

            _pendingEditorData = null; // Reset after save
            _hasGeofence = true;
            _geofenceIsDirty = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Campus geofence settings successfully saved to PostgreSQL.'),
              backgroundColor: AppColors.success,
            ),
          );
          // Sync geofence status with local tracking service
          await LocationService.syncWithServer();
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: ${response.body}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error connecting to backend: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      setState(() {
        _isSavingGeofence = false;
      });
    }
  }

  bool _isLoadingSettings = false;
  List<Map<String, dynamic>> _dbDepartments = [];

  Future<void> _fetchGoogleMapsConfig() async {
    final token = await _getAuthToken();
    if (token == null) {
      print('[SettingsScreen] Auth token is null! Cannot fetch maps config.');
      return;
    }
    try {
      final url = '$_baseUrl/api/v1/geofence/config';
      print('[SettingsScreen] Fetching Maps Config from: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      print('[SettingsScreen] Response status: ${response.statusCode}');
      print('[SettingsScreen] Response body: ${response.body}');
      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        if (resData['success'] == true && resData['data'] != null) {
          final key = resData['data']['google_maps_api_key'] as String? ?? '';
          print('[SettingsScreen] Extracted API Key from response: "$key"');
          setState(() {
            _googleMapsApiKey = key;
          });
        } else {
          print('[SettingsScreen] Success is false or data is null in response.');
        }
      }
    } catch (e) {
      print('[SettingsScreen] Exception in _fetchGoogleMapsConfig: $e');
    }
  }

  Future<void> _loadPolicyForSelected() async {
    try {
      final policy = await ApiService.fetchPolicy(departmentId: _selectedPolicyDeptId);
      setState(() {
        _allowedOutsideController.text = (policy['allowed_outside_minutes'] ?? 0).toString();
        _reminder1Controller.text = (policy['reminder_1_minutes'] ?? 0).toString();
        _reminder2Controller.text = (policy['reminder_2_minutes'] ?? 0).toString();
        _reminder3Controller.text = (policy['reminder_3_minutes'] ?? 0).toString();
        _evaluationController.text = (policy['evaluation_minutes'] ?? 15).toString();

        if (policy['start_time'] != null) {
          final parts = policy['start_time'].split(':');
          _workStartTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (policy['end_time'] != null) {
          final parts = policy['end_time'].split(':');
          _workEndTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (policy['half_day_cutoff_time'] != null) {
          final parts = policy['half_day_cutoff_time'].split(':');
          _halfDayTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (policy['absent_cutoff_time'] != null) {
          final parts = policy['absent_cutoff_time'].split(':');
          _absentTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      });
    } catch (e) {
      debugPrint('Error loading policy for ${_selectedPolicyDeptName}: $e');
    }
  }

  Future<void> _loadAllSettings() async {
    setState(() {
      _isLoadingSettings = true;
    });
    try {
      await _fetchGoogleMapsConfig();
    } catch (e) {
      debugPrint('Error loading maps config: $e');
    }
    try {
      await _fetchGeofence();
    } catch (e) {
      debugPrint('Error loading geofence: $e');
    }

    try {
      final orgSettings = await ApiService.fetchSettings();
      setState(() {
        _facultyRegistrationMode = orgSettings['faculty_registration_mode'] ?? 'ADMIN_APPROVAL';
        _allowExternalEmails = orgSettings['allow_external_emails'] ?? false;
        _requireMfa = orgSettings['require_mfa'] ?? false;
        _restrictDevices = orgSettings['restrict_devices'] ?? true;
        _logAdminActions = orgSettings['log_admin_actions'] ?? true;
        _notifyOnDeviceChange = orgSettings['notify_on_device_change'] ?? true;
        _notifyOnExitViolation = orgSettings['notify_on_exit_violation'] ?? true;
        _notifyOnApprovals = orgSettings['notify_on_approvals'] ?? true;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }

    try {
      await _loadDepartments();
    } catch (e) {
      debugPrint('Error loading departments: $e');
    } finally {
      // Load policy (defaults to Org Default)
      await _loadPolicyForSelected();
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final depts = await ApiService.fetchDepartments();
      setState(() {
        _dbDepartments = depts;
        _departments.clear();
        for (var d in depts) {
          _departments.add(d['name'] as String);
        }
      });
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  // ─── Walkthrough Helpers ─────────────────────────────────────────────────

  /// Returns the [GlobalKey] registered for this settings section's Showcase,
  /// or [null] if the section is not part of the tour.
  GlobalKey? _getSectionShowcaseKey(String sectionName) {
    switch (sectionName) {
      case 'General':
        return WalkthroughKeys.settingsGeneral;
      case 'Departments':
        return WalkthroughKeys.settingsDepartments;
      case 'Working Hours':
        return WalkthroughKeys.settingsWorkingHours;
      case 'Attendance Policy':
        return WalkthroughKeys.settingsAttendancePolicy;
      case 'Campus Geofence':
        return WalkthroughKeys.settingsGeofence;
      case 'Security':
        return WalkthroughKeys.settingsSecurity;
      case 'Notifications':
        return WalkthroughKeys.settingsNotifications;
      case 'Account':
        return WalkthroughKeys.settingsAccount;
      default:
        return null;
    }
  }

  /// Builds the [WalkthroughTooltip] for a given settings section.
  Widget? _buildSectionTooltip(String sectionName) {
    switch (sectionName) {
      case 'General':
        return const WalkthroughTooltip(
          stepNumber: 3,
          title: 'General Configuration',
          body:
              'Set your faculty registration mode (Admin Approval vs. Open Enrollment) and configure allowed email domains for your organization.',
          icon: Icons.tune,
          isFirstInPhase: true,
        );
      case 'Departments':
        return const WalkthroughTooltip(
          stepNumber: 4,
          title: 'Departments — Create First!',
          body:
              'Define your organization departments. Every faculty profile requires a department — so create these BEFORE registering any faculty members.',
          icon: Icons.business_outlined,
          callToAction:
              'Add departments first, then register faculty members.',
        );
      case 'Working Hours':
        return const WalkthroughTooltip(
          stepNumber: 5,
          title: 'Working Hours',
          body:
              'Set your organization daily working schedule boundaries. The attendance monitoring system tracks presence only within these defined hours.',
          icon: Icons.access_time_outlined,
        );
      case 'Attendance Policy':
        return const WalkthroughTooltip(
          stepNumber: 6,
          title: 'Attendance Policy',
          body:
              'Configure absence thresholds, reminder timings, and evaluation intervals. These rules govern all automated attendance decisions system-wide.',
          icon: Icons.policy_outlined,
          callToAction:
              'These settings directly affect faculty push notifications.',
        );
      case 'Campus Geofence':
        return const WalkthroughTooltip(
          stepNumber: 7,
          title: '🗺️ Campus Geofence — Critical!',
          body:
              'Define the physical attendance boundary of your campus. Faculty can only check in when their GPS location is within this geographic area.',
          icon: Icons.map_outlined,
          callToAction:
              'Set this accurately — it is the core of attendance tracking.',
        );
      case 'Security':
        return const WalkthroughTooltip(
          stepNumber: 8,
          title: 'Security Settings',
          body:
              'Configure multi-factor authentication policies, device lock restrictions, and admin action audit logging for your organization.',
          icon: Icons.shield_outlined,
        );
      case 'Notifications':
        return const WalkthroughTooltip(
          stepNumber: 9,
          title: 'Notification Preferences',
          body:
              'Choose which system events generate admin alerts — new faculty registrations, campus exit violations, device swap requests, and more.',
          icon: Icons.notifications_outlined,
        );
      case 'Account':
        return const WalkthroughTooltip(
          stepNumber: 10,
          title: 'Administrator Account',
          body:
              'View and manage your admin profile, update credentials, and review active session and device registration details.',
          icon: Icons.person_outline,
          callToAction:
              'Settings complete! Head back to explore the management modules.',
        );
      default:
        return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  String _timeOfDayToTimeString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _cleanErrorMessage(Object e) {
    if (e is ApiException) {
      if (e.statusCode == 401) {
        return 'Your session has expired. Please log in again.';
      }
      return e.message;
    }
    return e.toString();
  }

  Future<void> _saveGeneralSettings() async {
    try {
      await ApiService.updateSettings({
        'faculty_registration_mode': _facultyRegistrationMode,
        'allow_external_emails': _allowExternalEmails,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('General settings saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving general settings: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _saveAttendancePolicy() async {
    try {
      await ApiService.updatePolicy({
        'department_id': _selectedPolicyDeptId,
        'allowed_outside_minutes': int.tryParse(_allowedOutsideController.text) ?? 0,
        'reminder_1_minutes': int.tryParse(_reminder1Controller.text) ?? 0,
        'reminder_2_minutes': int.tryParse(_reminder2Controller.text) ?? 0,
        'reminder_3_minutes': int.tryParse(_reminder3Controller.text) ?? 0,
        'evaluation_minutes': int.tryParse(_evaluationController.text) ?? 15,
        'half_day_cutoff_time': _timeOfDayToTimeString(_halfDayTime),
        'absent_cutoff_time': _timeOfDayToTimeString(_absentTime),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Attendance policy for ${_selectedPolicyDeptName} saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving attendance policy: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _saveWorkingHours() async {
    try {
      await ApiService.updatePolicy({
        'department_id': _selectedPolicyDeptId,
        'start_time': _timeOfDayToTimeString(_workStartTime),
        'end_time': _timeOfDayToTimeString(_workEndTime),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Working hours for ${_selectedPolicyDeptName} saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving working hours: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _saveSecuritySettings() async {
    try {
      await ApiService.updateSettings({
        'require_mfa': _requireMfa,
        'restrict_devices': _restrictDevices,
        'log_admin_actions': _logAdminActions,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Security settings saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving security settings: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _saveNotificationsSettings() async {
    try {
      await ApiService.updateSettings({
        'notify_on_device_change': _notifyOnDeviceChange,
        'notify_on_exit_violation': _notifyOnExitViolation,
        'notify_on_approvals': _notifyOnApprovals,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification settings saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving notification settings: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _addDepartmentToDB(String name) async {
    try {
      await ApiService.createDepartment(name, '');
      await _loadDepartments();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Department "$name" added successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding department: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _removeDepartmentFromDB(int index) async {
    final deptName = _departments[index];
    final deptObj = _dbDepartments.firstWhere((d) => d['name'] == deptName, orElse: () => {});
    if (deptObj.isEmpty || deptObj['id'] == null) return;
    
    try {
      await ApiService.deleteDepartment(deptObj['id'] as String);
      await _loadDepartments();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Department "$deptName" removed successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing department: ${_cleanErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _saveAllSettings() async {
    setState(() {
      _isLoadingSettings = true;
    });
    try {
      await Future.wait([
        _saveGeneralSettings(),
        _saveAttendancePolicy(),
        _saveWorkingHours(),
        _saveSecuritySettings(),
        _saveNotificationsSettings(),
        _saveGeofence(),
      ]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All system configurations saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      debugPrint('Error saving all settings: $e');
    } finally {
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }



  Future<void> _addDepartment() async {
    final text = _newDeptController.text.trim();
    if (text.isNotEmpty) {
      _newDeptController.clear();
      await _addDepartmentToDB(text);
    }
  }

  Future<void> _deleteDepartment(int index) async {
    final dept = _departments[index];
    if (dept == 'Computer Science' || dept == 'Electrical Engineering') {
      AppDialog.show(
        context: context,
        title: 'Delete Department Failed',
        content: 'Cannot delete "$dept" because active faculty profiles remain assigned to it.',
        confirmText: 'Acknowledge',
        onConfirm: () {},
      );
    } else {
      await _removeDepartmentFromDB(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 960;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branding Header
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final isWide = headerConstraints.maxWidth > 600;
              final headerInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premises Settings',
                    style: AppTypography.h1.copyWith(
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Smart Attendance & Premises Monitoring Control Panel',
                    style: AppTypography.caption,
                  ),
                ],
              );
              final saveBtn = AppButton(
                text: 'Save All Changes',
                onPressed: _saveAllSettings,
              );

              return isWide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: headerInfo),
                        const SizedBox(width: 16),
                        saveBtn,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerInfo,
                        const SizedBox(height: 12),
                        saveBtn,
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: isDesktop ? _buildDesktopLayout(theme) : _buildMobileLayout(theme),
          ),
        ],
      ),
    );
  }

  // 1. DESKTOP VIEWPORTS (Two-pane sidebar layout)
  Widget _buildDesktopLayout(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar list
        Container(
          width: 240,
          margin: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sections.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final section = _sections[index];
              final sectionName = section['name'] as String;
              final isSelected = _activeSection == sectionName;

              Color itemColor;
              Color bg;
              Color borderAccentColor;

              if (isSelected) {
                if (isDark) {
                  itemColor = const Color(0xFFFFFFFF); // High-contrast White text & icon in dark mode
                  bg = const Color(0xFF0056D2).withOpacity(0.10); // 10% opacity Sapphire Blue fill
                  borderAccentColor = const Color(0xFF0056D2); // Sapphire Blue left accent indicator
                } else {
                  itemColor = AppColors.primary;
                  bg = AppColors.primary.withOpacity(0.06);
                  borderAccentColor = AppColors.primary;
                }
              } else {
                itemColor = isDark
                    ? const Color(0xFFA1A1AA) // Inactive Zinc grey preservation
                    : AppColors.textSecondaryLight;
                bg = Colors.transparent;
                borderAccentColor = Colors.transparent;
              }

              final tile = Material(
                color: Colors.transparent,
                child: Stack(
                  children: [
                    Container(
                      color: bg,
                      child: ListTile(
                        selected: isSelected,
                        leading: Icon(
                          section['icon'],
                          color: itemColor,
                          size: 20,
                        ),
                        title: Text(
                          sectionName,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                            color: itemColor,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.chevron_right, color: itemColor, size: 16)
                            : null,
                        onTap: () => _switchSection(sectionName),
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 3.0, // 3px thick left-border accent in Sapphire Blue
                          color: borderAccentColor,
                        ),
                      ),
                  ],
                ),
              );
              // Wrap tour sections with Showcase widget
              final showcaseKey = _getSectionShowcaseKey(sectionName);
              final tooltipContent = _buildSectionTooltip(sectionName);
              if (showcaseKey == null || tooltipContent == null) return tile;
              return Showcase.withWidget(
                key: showcaseKey,
                overlayOpacity: 0.78,
                disableDefaultTargetGestures: true,
                targetShapeBorder: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                targetPadding: const EdgeInsets.all(4),
                container: tooltipContent,
                child: tile,
              );
            },
          ),
        ),
        
        // Right Detail Pane
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeSection,
                      style: AppTypography.h2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getSectionDescription(_activeSection),
                      style: AppTypography.caption,
                    ),
                    const Divider(height: 36),
                    _buildActivePaneContent(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 2. MOBILE VIEWPORTS (Horizontal segmented tab selector)
  Widget _buildMobileLayout(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Horizontal sliding categories
        SizedBox(
          height: 45,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _sections.length,
            itemBuilder: (context, index) {
              final section = _sections[index];
              final sectionName = section['name'] as String;
              final isSelected = _activeSection == sectionName;
              final chip = Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    sectionName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _activeSection = sectionName;
                      });
                    }
                  },
                ),
              );
              // Also wrap mobile chips with Showcase for tour support
              final showcaseKey = _getSectionShowcaseKey(sectionName);
              final tooltipContent = _buildSectionTooltip(sectionName);
              if (showcaseKey == null || tooltipContent == null) return chip;
              return Showcase.withWidget(
                key: showcaseKey,
                overlayOpacity: 0.78,
                disableDefaultTargetGestures: true,
                container: tooltipContent,
                child: chip,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        
        // Active Content
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeSection,
                      style: AppTypography.h3,
                    ),
                    const Divider(height: 24),
                    _buildActivePaneContent(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getSectionDescription(String sectionName) {
    switch (sectionName) {
      case 'General':
        return 'Configure organization registration mode policies and email filters.';
      case 'Attendance Policy':
        return 'Configure operational attendance rule evaluations and push notifications.';
      case 'Working Hours':
        return 'Set mandatory daily operational timeframe boundaries for monitoring.';
      case 'Campus Geofence':
        return 'Map organizational physical site limits using visual coordinate pins.';
      case 'Departments':
        return 'Manage and review active internal academic/corporate rosters.';
      case 'Security':
        return 'Enforce multi-factor verification logins and active hardware locks.';
      case 'Notifications':
        return 'Configure exits, threshold delays, and notification targets.';
      case 'Account':
        return 'Manage your administrator account session and view profile details.';
      case 'Developer Tools':
        return 'Debug-only tools for testing geofence and attendance workflows.';
      default:
        return '';
    }
  }

  // Renders the specific widget according to active sidebar tab
  Widget _buildActivePaneContent(ThemeData theme) {
    if (_isLoadingSettings) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40.0),
          child: CircularProgressIndicator(),
        ),
      );
    }
    switch (_activeSection) {
      case 'General':
        return _buildGeneralPane(theme);
      case 'Attendance Policy':
        return _buildAttendancePolicyPane(theme);
      case 'Working Hours':
        return _buildWorkingHoursPane(theme);
      case 'Campus Geofence':
        return _buildGeofencePane(theme);
      case 'Departments':
        return _buildDepartmentsPane(theme);
      case 'Security':
        return _buildSecurityPane(theme);
      case 'Notifications':
        return _buildNotificationsPane(theme);
      case 'Account':
        return _buildAccountPane(theme);
      case 'Developer Tools':
        return _buildDeveloperToolsPane(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  // =========================================================================
  // SUB-PANES IMPLEMENTATIONS
  // =========================================================================

  Widget _buildGeneralPane(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: _facultyRegistrationMode == 'AUTO_APPROVE',
          onChanged: (val) {
            setState(() {
              _facultyRegistrationMode = val ? 'AUTO_APPROVE' : 'ADMIN_APPROVAL';
            });
          },
          title: const Text('Auto-Approve Faculty Registrations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Bypass admin verification queues for domain email accounts.', style: TextStyle(fontSize: 11)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          value: _allowExternalEmails,
          onChanged: (val) {
            setState(() {
              _allowExternalEmails = val;
            });
          },
          title: const Text('Allow Guest Domain Logins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Permit accounts outside the official organization whitelist.', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(height: 24),
        AppButton(
          text: 'Save General Settings',
          onPressed: _saveGeneralSettings,
        ),
      ],
    );
  }

  Widget _buildDeptSelectorForPolicy() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.business_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 16),
          const Text(
            'Configure for:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButton<String?>(
              value: _selectedPolicyDeptId,
              isExpanded: true,
              underline: const SizedBox(),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? AppColors.textSecondaryDark 
                    : AppColors.textSecondaryLight,
                size: 20,
              ),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Theme.of(context).brightness == Brightness.dark 
                  ? AppColors.surfaceDark 
                  : AppColors.surfaceLight,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Organization Default', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                ..._dbDepartments.map((d) => DropdownMenuItem<String?>(
                  value: d['id'] as String,
                  child: Text(d['name'] as String, style: const TextStyle(fontSize: 13)),
                )).toList(),
              ],
              onChanged: (val) async {
                setState(() {
                  _selectedPolicyDeptId = val;
                  if (val == null) {
                    _selectedPolicyDeptName = 'Organization Default';
                  } else {
                    _selectedPolicyDeptName = _dbDepartments.firstWhere((d) => d['id'] == val)['name'];
                  }
                  _isLoadingSettings = true;
                });
                await _loadPolicyForSelected();
                setState(() {
                  _isLoadingSettings = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendancePolicyPane(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // Helper to build a clean card container
    Widget cardContainer({required String title, required Widget child}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.h3.copyWith(fontSize: 14),
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeptSelectorForPolicy(),
        cardContainer(
          title: 'Attendance Rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInput(
                label: 'Allowed Outside Duration Buffer',
                hint: 'Minutes',
                controller: _allowedOutsideController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.timer_outlined,
              ),
              const SizedBox(height: 8),
              const Text(
                'Allowed outside duration timeframe limit before policy checks initiate (e.g., 25 minutes).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        cardContainer(
          title: 'Reminder Rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInput(
                label: 'First Out-of-Geofence Warning Delay',
                hint: 'Minutes',
                controller: _reminder1Controller,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.notifications_none,
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'Second Warning Reminder Delay',
                hint: 'Minutes',
                controller: _reminder2Controller,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.notifications_outlined,
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'Final Persistent Warning Push Alert',
                hint: 'Minutes',
                controller: _reminder3Controller,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.notifications_active_outlined,
              ),
              const SizedBox(height: 12),
              const Text(
                'Timeline details for sending alert notifications to out-of-bounds faculty (e.g., 25m, 28m, and 31m).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        cardContainer(
          title: 'Attendance Evaluation Settings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInput(
                label: 'Attendance Policy Evaluation Trigger',
                hint: 'Minutes',
                controller: _evaluationController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.refresh_outlined,
              ),
              const SizedBox(height: 8),
              const Text(
                'Time limit before active status evaluation commits (e.g., 35 minutes). If faculty remains out-of-bounds at this point without submitting a reason request, policies are applied.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        cardContainer(
          title: 'Status Cutoff Thresholds',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 500;
                  final halfDayTile = ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Half-Day Cutoff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(_halfDayTime.format(context), style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.access_time, size: 18),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _halfDayTime);
                      if (picked != null) setState(() => _halfDayTime = picked);
                    },
                  );
                  final absentTile = ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Absent Threshold', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(_absentTime.format(context), style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.access_time, size: 18),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _absentTime);
                      if (picked != null) setState(() => _absentTime = picked);
                    },
                  );

                  return isWide
                      ? Row(
                          children: [
                            Expanded(child: halfDayTile),
                            const SizedBox(width: 24),
                            Expanded(child: absentTile),
                          ],
                        )
                      : Column(
                          children: [
                            halfDayTile,
                            const Divider(height: 1),
                            absentTile,
                          ],
                        );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Daily evaluation thresholds (e.g., 2:30 PM). Violations occurring before this time mark the faculty member Absent; violations occurring after this time mark them Half-Day.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          text: 'Save Attendance Policy',
          onPressed: _saveAttendancePolicy,
        ),
      ],
    );
  }

  Widget _buildWorkingHoursPane(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeptSelectorForPolicy(),
        // Info Alert banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Working Hours are mandatory parameters. Location event monitoring and reminder checks operate strictly during this configured daily timeframe.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            final startCard = Card(
              color: isDark ? AppColors.backgroundDark : Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shift Start Time',
                      style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _workStartTime.format(context),
                      style: AppTypography.h1.copyWith(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      text: 'Choose Start',
                      variant: ButtonVariant.outline,
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _workStartTime);
                        if (picked != null) {
                          setState(() => _workStartTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
            final endCard = Card(
              color: isDark ? AppColors.backgroundDark : Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shift End Time',
                      style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _workEndTime.format(context),
                      style: AppTypography.h1.copyWith(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      text: 'Choose End',
                      variant: ButtonVariant.outline,
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _workEndTime);
                        if (picked != null) {
                          setState(() => _workEndTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );

            return isWide
                ? Row(
                    children: [
                      Expanded(child: startCard),
                      const SizedBox(width: 16),
                      Expanded(child: endCard),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      startCard,
                      const SizedBox(height: 16),
                      endCard,
                    ],
                  );
          },
        ),
        const SizedBox(height: 24),
        AppButton(
          text: 'Save Working Hours',
          onPressed: _saveWorkingHours,
        ),
      ],
    );
  }



  double _calculatePolygonAreaSqM(List<dynamic> vertices) {
    if (vertices.length < 3) return 0.0;
    double latSum = 0.0;
    for (final v in vertices) {
      latSum += (v['latitude'] as num).toDouble();
    }
    final double latCenter = latSum / vertices.length;
    
    const double R = 6371000.0;
    final double latRad = latCenter * math.pi / 180.0;
    final double cosLat = math.cos(latRad);
    
    final List<Map<String, double>> projected = vertices.map((v) {
      final double lat = (v['latitude'] as num).toDouble();
      final double lng = (v['longitude'] as num).toDouble();
      final double x = lng * math.pi / 180.0 * R * cosLat;
      final double y = lat * math.pi / 180.0 * R;
      return {'x': x, 'y': y};
    }).toList();
    
    double area = 0.0;
    final int n = projected.length;
    for (int i = 0; i < n; i++) {
      final p1 = projected[i];
      final p2 = projected[(i + 1) % n];
      area += p1['x']! * p2['y']! - p2['x']! * p1['y']!;
    }
    return area.abs() * 0.5;
  }

  // Campus Geofence Canvas + Coordinates Configurator
  Widget _buildGeofencePane(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_savedLatitude != null || _geofenceType == 'polygon')
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              border: Border.all(color: isDark ? AppColors.borderDark : const Color(0xFFA5D6A7)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFC8E6C9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_user, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _geofenceType == 'polygon'
                            ? 'Active Campus Geofence: Polygon Boundary'
                            : 'Active Campus Geofence (Saved in Database)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _geofenceType == 'polygon'
                            ? 'Vertices Count: ${_geofenceVertices?.length ?? 0}'
                            : 'Latitude: ${_savedLatitude?.toStringAsFixed(6)}   |   Longitude: ${_savedLongitude?.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _geofenceType == 'polygon'
                            ? 'Calculated Area: ${(_geofenceVertices == null) ? 0.0 : _calculatePolygonAreaSqM(_geofenceVertices!).toStringAsFixed(1)} m²'
                            : 'Radius: ${_savedRadiusMeters?.round()}m   |   Area: ${(math.pi * math.pow(_savedRadiusMeters ?? 0, 2) / 10000).toStringAsFixed(2)} ha (~${_formatNumber((math.pi * math.pow(_savedRadiusMeters ?? 0, 2)).round())} m²)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_savedLatitude == null && _geofenceType != 'polygon')
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "No campus location has been configured yet. Use the GIS interface below to draw or search.",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Container(
          height: 600,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg - 1),
            child: _googleMapsApiKey.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PremisesBrandedLoader(),
                        SizedBox(height: 16),
                        Text('Initializing premium GIS configurator...'),
                      ],
                    ),
                  )
                : GoogleMapEditor(
                    apiKey: _googleMapsApiKey,
                    initialLatitude: _savedLatitude ?? 18.403817,
                    initialLongitude: _savedLongitude ?? 76.560943,
                    initialRadius: _savedRadiusMeters ?? 500.0,
                    initialType: _geofenceType,
                    initialVerticesJson: _geofenceVertices != null ? json.encode(_geofenceVertices) : null,
                    onSave: (Map<String, dynamic> data) async {
                      await _saveCustomGeofence(data);
                    },
                    onChanged: () {
                      // Handled by onChangedData
                    },
                    onChangedData: (Map<String, dynamic> data) {
                      // Store the latest editor state for use during save,
                      // but do NOT update _savedLatitude/_savedLongitude/_savedRadiusMeters
                      // as those feed back into GoogleMapEditor as initialLatitude/etc
                      // and would create a rebuild→didUpdateWidget→notifyChanged loop.
                      _pendingEditorData = data;

                      // Set guard flag so didUpdateWidget knows this rebuild
                      // originated from the editor itself and should be ignored.
                      _editorIsNotifying = true;

                      // Only update display-related state (info panel) and dirty flag.
                      setState(() {
                        _geofenceType = data['geofence_type'] ?? 'circle';
                        _geofenceVertices = data['vertices'];
                        _geofenceIsDirty = _calculateGeofenceDirtyState(data);
                      });

                      // Clear the guard after the synchronous build cycle.
                      // The build (and therefore didUpdateWidget) happens synchronously
                      // within setState, so clearing it here is safe.
                      _editorIsNotifying = false;
                    },
                  ),
          ),
        ),
      ],
    );
  }

  bool _calculateGeofenceDirtyState(Map<String, dynamic> data) {
    final String type = data['geofence_type'] ?? 'circle';
    final String origType = _originalGeofenceType ?? 'circle';
    if (type != origType) return true;

    if (type == 'circle') {
      final double? lat = data['latitude'] != null ? (data['latitude'] as num).toDouble() : null;
      final double? lng = data['longitude'] != null ? (data['longitude'] as num).toDouble() : null;
      final double? rad = data['radius_meters'] != null ? (data['radius_meters'] as num).toDouble() : null;

      final double? origLat = _originalLatitude;
      final double? origLng = _originalLongitude;
      final double? origRad = _originalRadiusMeters;

      if (origLat == null || origLng == null || origRad == null) {
        return true;
      }

      if ((lat! - origLat).abs() > 0.000001) return true;
      if ((lng! - origLng).abs() > 0.000001) return true;
      if ((rad! - origRad).abs() > 0.1) return true;
    } else {
      final List<dynamic>? vertices = data['vertices'];
      final List<dynamic>? origVertices = _originalGeofenceVertices;

      if (vertices == null && origVertices == null) return false;
      if (vertices == null || origVertices == null) return true;
      if (vertices.length != origVertices.length) return true;

      for (int i = 0; i < vertices.length; i++) {
        final v = vertices[i];
        final ov = origVertices[i];
        if (v == null || ov == null) return true;
        
        final double lat = (v['latitude'] as num).toDouble();
        final double lng = (v['longitude'] as num).toDouble();
        final double olat = (ov['latitude'] as num).toDouble();
        final double olng = (ov['longitude'] as num).toDouble();

        if ((lat - olat).abs() > 0.000001) return true;
        if ((lng - olng).abs() > 0.000001) return true;
      }
    }
    return false;
  }

  String _formatNumber(int number) {
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return number.toString().replaceAllMapped(reg, (Match match) => '${match[1]},');
  }



  Widget _buildDepartmentsPane(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            final deptInput = AppInput(
              label: 'Department Title',
              hint: 'e.g., Physics, Chemistry',
              controller: _newDeptController,
            );
            final addBtn = AppButton(
              text: 'Add Dept',
              onPressed: _addDepartment,
            );

            return isWide
                ? Row(
                    children: [
                      Expanded(child: deptInput),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0), // Align with float input
                        child: addBtn,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      deptInput,
                      const SizedBox(height: 12),
                      addBtn,
                    ],
                  );
          },
        ),
        const SizedBox(height: 24),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _departments.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _departments[index],
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                onPressed: () => _deleteDepartment(index),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSecurityPane(ThemeData theme) {
    return Column(
      children: [
        SwitchListTile(
          value: _requireMfa,
          onChanged: (val) => setState(() => _requireMfa = val),
          title: const Text('Require Multi-Factor Authentication (MFA)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Forces all organizational admins to authenticate using MFA apps.', style: TextStyle(fontSize: 11)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          value: _restrictDevices,
          onChanged: (val) => setState(() => _restrictDevices = val),
          title: const Text('Hardware Device Lock Binding', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Permits attendance reporting strictly from configured hardware identifiers.', style: TextStyle(fontSize: 11)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          value: _logAdminActions,
          onChanged: (val) => setState(() => _logAdminActions = val),
          title: const Text('Enforce Full Audit Logging', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Maintains history track logs for all configuration mutations.', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(height: 24),
        AppButton(
          text: 'Save Security Settings',
          onPressed: _saveSecuritySettings,
        ),
      ],
    );
  }

  Widget _buildNotificationsPane(ThemeData theme) {
    return Column(
      children: [
        SwitchListTile(
          value: _notifyOnDeviceChange,
          onChanged: (val) => setState(() => _notifyOnDeviceChange = val),
          title: const Text('Device Change Requests Alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Warns admins immediately when swap requests are queued.', style: TextStyle(fontSize: 11)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          value: _notifyOnExitViolation,
          onChanged: (val) => setState(() => _notifyOnExitViolation = val),
          title: const Text('Geofence Violation Alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Sends alerts on dashboard for faculty who exit campus geofences.', style: TextStyle(fontSize: 11)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          value: _notifyOnApprovals,
          onChanged: (val) => setState(() => _notifyOnApprovals = val),
          title: const Text('Roster Approval Email Triggers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Notify faculty members when registrations are approved.', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(height: 24),
        AppButton(
          text: 'Save Notification Settings',
          onPressed: _saveNotificationsSettings,
        ),
      ],
    );
  }

  Widget _buildAccountPane(ThemeData theme) {
    final name = SessionManager.fullName ?? 'Administrator';
    final email = SessionManager.email ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile Information',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'A',
              style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 18),
            ),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text(email, style: const TextStyle(fontSize: 13)),
        ),
        const Divider(height: 32),
        const Text(
          'Session Management',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        const Text(
          'Log out of your administrative session on this device. You will need to sign in again to access the control panel.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            text: 'Sign Out / Log Out',
            variant: ButtonVariant.outline,
            leadingIcon: Icons.logout,
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log Out'),
                  content: const Text('Are you sure you want to log out from this device?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Log Out', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await SessionManager.clear();
                if (context.mounted) {
                  context.go('/login');
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeveloperToolsPane(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warning banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.deepPurple.withOpacity(0.35)),
          ),
          child: const Row(
            children: [
              Icon(Icons.bug_report_outlined, color: Colors.deepPurple, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Developer Tools are only visible in DEBUG builds and will not appear in production. These tools bypass real location and directly trigger backend attendance events.',
                  style: TextStyle(fontSize: 12, color: Colors.deepPurple, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Attendance Simulator
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.science_outlined, color: AppColors.success, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendance Simulator',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Simulate geofence check-in / check-out for any faculty',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Use this tool to test the full attendance pipeline without physically entering the geofence. It fires real API events, creates attendance records, and sends notifications to the faculty member.',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 16),
              AppButton(
                text: 'Open Attendance Simulator',
                leadingIcon: Icons.open_in_new,
                onPressed: () => context.go('/admin/simulator'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

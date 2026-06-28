import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';

class GoogleMapEditor extends StatefulWidget {
  final String apiKey;
  final double initialLatitude;
  final double initialLongitude;
  final double initialRadius;
  final String initialType;
  final String? initialVerticesJson;
  final Function(Map<String, dynamic> data) onSave;
  final VoidCallback? onChanged;

  const GoogleMapEditor({
    super.key,
    required this.apiKey,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.initialRadius,
    required this.initialType,
    this.initialVerticesJson,
    required this.onSave,
    this.onChanged,
  });

  @override
  State<GoogleMapEditor> createState() => _GoogleMapEditorState();
}

class _GoogleMapEditorState extends State<GoogleMapEditor> {
  late String _activeMode;
  late LatLng _circleCenter;
  late double _circleRadius;
  List<LatLng> _polygonVertices = [];
  final MapController _mapController = MapController();

  // History stacks for mobile undo/redo
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _activeMode = widget.initialType;
    _circleCenter = LatLng(widget.initialLatitude, widget.initialLongitude);
    _circleRadius = widget.initialRadius;

    if (widget.initialVerticesJson != null) {
      try {
        final List<dynamic> parsed = json.decode(widget.initialVerticesJson!);
        _polygonVertices = parsed
            .map((v) => LatLng((v['latitude'] as num).toDouble(), (v['longitude'] as num).toDouble()))
            .toList();
      } catch (e) {
        debugPrint('Error parsing vertices on mobile: $e');
      }
    }
  }

  void _saveHistoryState() {
    final state = {
      'mode': _activeMode,
      'centerLat': _circleCenter.latitude,
      'centerLng': _circleCenter.longitude,
      'radius': _circleRadius,
      'vertices': _polygonVertices.map((v) => {'lat': v.latitude, 'lng': v.longitude}).toList(),
    };
    _undoStack.add(json.encode(state));
    if (_undoStack.length > 20) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    setState(() {});
    if (widget.onChanged != null) widget.onChanged!();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final currentState = {
      'mode': _activeMode,
      'centerLat': _circleCenter.latitude,
      'centerLng': _circleCenter.longitude,
      'radius': _circleRadius,
      'vertices': _polygonVertices.map((v) => {'lat': v.latitude, 'lng': v.longitude}).toList(),
    };
    _redoStack.add(json.encode(currentState));

    final prevState = json.decode(_undoStack.removeLast());
    setState(() {
      _activeMode = prevState['mode'];
      _circleCenter = LatLng(prevState['centerLat'], prevState['centerLng']);
      _circleRadius = prevState['radius'];
      final List<dynamic> verts = prevState['vertices'];
      _polygonVertices = verts.map((v) => LatLng(v['lat'], v['lng'])).toList();
    });
    if (widget.onChanged != null) widget.onChanged!();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final currentState = {
      'mode': _activeMode,
      'centerLat': _circleCenter.latitude,
      'centerLng': _circleCenter.longitude,
      'radius': _circleRadius,
      'vertices': _polygonVertices.map((v) => {'lat': v.latitude, 'lng': v.longitude}).toList(),
    };
    _undoStack.add(json.encode(currentState));

    final nextState = json.decode(_redoStack.removeLast());
    setState(() {
      _activeMode = nextState['mode'];
      _circleCenter = LatLng(nextState['centerLat'], nextState['centerLng']);
      _circleRadius = nextState['radius'];
      final List<dynamic> verts = nextState['vertices'];
      _polygonVertices = verts.map((v) => LatLng(v['lat'], v['lng'])).toList();
    });
    if (widget.onChanged != null) widget.onChanged!();
  }

  double _calculatePolygonArea() {
    if (_polygonVertices.length < 3) return 0.0;
    // Flat-surface projection Shoelace calculation (approximate localized area)
    double latSum = 0.0;
    for (final v in _polygonVertices) {
      latSum += v.latitude;
    }
    final latCenter = latSum / _polygonVertices.length;
    final double radCenter = latCenter * math.pi / 180.0;
    const double R = 6371000.0;
    final double metersPerLat = math.pi * R / 180.0;
    final double metersPerLng = math.pi * R * math.cos(radCenter) / 180.0;

    double area = 0.0;
    for (int i = 0; i < _polygonVertices.length; i++) {
      final p1 = _polygonVertices[i];
      final p2 = _polygonVertices[(i + 1) % _polygonVertices.length];
      final x1 = p1.longitude * metersPerLng;
      final y1 = p1.latitude * metersPerLat;
      final x2 = p2.longitude * metersPerLng;
      final y2 = p2.latitude * metersPerLat;
      area += (x1 * y2 - x2 * y1);
    }
    return (area.abs() / 2.0);
  }

  double _calculatePolygonPerimeter() {
    if (_polygonVertices.length < 2) return 0.0;
    double perimeter = 0.0;
    const double R = 6371000.0;
    for (int i = 0; i < _polygonVertices.length; i++) {
      final p1 = _polygonVertices[i];
      final p2 = _polygonVertices[(i + 1) % _polygonVertices.length];
      // Haversine distance
      final dLat = (p2.latitude - p1.latitude) * math.pi / 180.0;
      final dLon = (p2.longitude - p1.longitude) * math.pi / 180.0;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(p1.latitude * math.pi / 180.0) *
              math.cos(p2.latitude * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);
      final c = 2 * math.asin(math.sqrt(a));
      perimeter += R * c;
    }
    return perimeter;
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    _saveHistoryState();
    if (_activeMode == 'circle') {
      setState(() {
        _circleCenter = point;
      });
    } else {
      setState(() {
        _polygonVertices.add(point);
      });
    }
  }

  void _removeVertex(int index) {
    _saveHistoryState();
    setState(() {
      _polygonVertices.removeAt(index);
    });
  }

  void _clearShape() {
    _saveHistoryState();
    setState(() {
      if (_activeMode == 'circle') {
        _circleRadius = 100.0;
      } else {
        _polygonVertices.clear();
      }
    });
  }

  void _centerMap() {
    LatLng center = _circleCenter;
    if (_activeMode == 'polygon' && _polygonVertices.isNotEmpty) {
      double latSum = 0;
      double lngSum = 0;
      for (final v in _polygonVertices) {
        latSum += v.latitude;
        lngSum += v.longitude;
      }
      center = LatLng(latSum / _polygonVertices.length, lngSum / _polygonVertices.length);
    }
    _mapController.move(center, 15.0);
  }

  void _saveGeofence() {
    final Map<String, dynamic> data = {
      'geofence_type': _activeMode,
      'name': 'Campus Boundary',
      'is_active': true,
    };
    if (_activeMode == 'circle') {
      data['latitude'] = _circleCenter.latitude;
      data['longitude'] = _circleCenter.longitude;
      data['radius_meters'] = _circleRadius;
      data['vertices'] = null;
    } else {
      data['latitude'] = null;
      data['longitude'] = null;
      data['radius_meters'] = null;
      data['vertices'] = _polygonVertices
          .map((v) => {'latitude': v.latitude, 'longitude': v.longitude})
          .toList();
    }
    widget.onSave(data);
  }

  String _formatArea(double area) {
    if (area >= 1000000) {
      return '${(area / 1000000).toStringAsFixed(2)} km²';
    }
    return '${area.toStringAsFixed(0)} m²';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark();
    final double area = _activeMode == 'circle'
        ? (math.pi * math.pow(_circleRadius, 2))
        : _calculatePolygonArea();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 768;
        final sidebar = _buildSidebar(theme, area);
        final mapWidget = _buildMap();

        if (isWide) {
          return Row(
            children: [
              SizedBox(width: 320, child: sidebar),
              const VerticalDivider(width: 1, color: Color(0xFF334155)),
              Expanded(child: mapWidget),
            ],
          );
        } else {
          return Column(
            children: [
              Expanded(child: mapWidget),
              const Divider(height: 1, color: Color(0xFF334155)),
              SizedBox(height: 280, child: sidebar),
            ],
          );
        }
      },
    );
  }

  Widget _buildSidebar(ThemeData theme, double area) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🗺️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Campus Geofence',
                style: AppTypography.h3.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mode selector
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _saveHistoryState();
                      setState(() => _activeMode = 'circle');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _activeMode == 'circle' ? const Color(0xFF4F46E5) : Colors.transparent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      alignment: Alignment.center,
                      child: const Text('⭕ Circle', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _saveHistoryState();
                      setState(() => _activeMode = 'polygon');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _activeMode == 'polygon' ? const Color(0xFF10B981) : Colors.transparent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      alignment: Alignment.center,
                      child: const Text('⬡ Polygon', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_activeMode == 'circle') ...[
            Text('Circle Radius: ${_circleRadius.toStringAsFixed(0)} m', style: const TextStyle(fontSize: 12)),
            Slider(
              min: 10,
              max: 2000,
              value: _circleRadius.clamp(10, 2000),
              activeColor: const Color(0xFF4F46E5),
              inactiveColor: const Color(0xFF334155),
              onChanged: (val) {
                setState(() => _circleRadius = val);
              },
              onChangeEnd: (val) {
                _saveHistoryState();
              },
            ),
          ] else ...[
            Text(
              'Help: Tap on map to add corner points. Tap a green marker to remove it.',
              style: AppTypography.caption.copyWith(color: const Color(0xFF94A3B8)),
            ),
          ],
          const SizedBox(height: 12),
          // Live Statistics Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView(
                children: [
                  _buildStatRow('Mode:', _activeMode == 'circle' ? 'Circle' : 'Polygon'),
                  _buildStatRow('Area:', _formatArea(area)),
                  if (_activeMode == 'circle')
                    _buildStatRow('Radius:', '${_circleRadius.toStringAsFixed(0)} m')
                  else ...[
                    _buildStatRow('Perimeter:', '${_calculatePolygonPerimeter().toStringAsFixed(0)} m'),
                    _buildStatRow('Vertices:', '${_polygonVertices.length}'),
                  ],
                  _buildStatRow(
                    'Center:',
                    _activeMode == 'circle'
                        ? '${_circleCenter.latitude.toStringAsFixed(5)}, ${_circleCenter.longitude.toStringAsFixed(5)}'
                        : _polygonVertices.isEmpty
                            ? 'N/A'
                            : '${_polygonVertices[0].latitude.toStringAsFixed(5)}, ${_polygonVertices[0].longitude.toStringAsFixed(5)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancel',
                  variant: ButtonVariant.outline,
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  text: 'Save',
                  variant: ButtonVariant.primary,
                  onPressed: _saveGeofence,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final markers = <Marker>[];

    if (_activeMode == 'circle') {
      markers.add(
        Marker(
          point: _circleCenter,
          width: 32,
          height: 32,
          child: const Icon(Icons.location_on, color: Color(0xFF4F46E5), size: 32),
        ),
      );
    } else {
      for (int i = 0; i < _polygonVertices.length; i++) {
        final idx = i;
        markers.add(
          Marker(
            point: _polygonVertices[i],
            width: 24,
            height: 24,
            child: GestureDetector(
              onTap: () => _removeVertex(idx),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _circleCenter,
            initialZoom: 15.0,
            onTap: _onMapTap,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.premises.app',
            ),
            if (_activeMode == 'circle')
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _circleCenter,
                    radius: _circleRadius,
                    useRadiusInMeter: true,
                    color: const Color(0xFF4F46E5).withOpacity(0.15),
                    borderColor: const Color(0xFF4F46E5),
                    borderStrokeWidth: 2,
                  ),
                ],
              )
            else if (_polygonVertices.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _polygonVertices,
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderColor: const Color(0xFF10B981),
                    borderStrokeWidth: 2,
                  ),
                ],
              )
            else if (_polygonVertices.length == 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _polygonVertices,
                    color: const Color(0xFF10B981),
                    strokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        // Toolbar Overlay
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: _undoStack.isEmpty ? null : _undo,
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  tooltip: 'Undo',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  onPressed: _redoStack.isEmpty ? null : _redo,
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  tooltip: 'Redo',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
                Container(width: 1, height: 16, color: const Color(0xFF334155)),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.gps_fixed, size: 18),
                  onPressed: _centerMap,
                  color: Colors.white,
                  tooltip: 'Center Map',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _clearShape,
                  color: const Color(0xFFEF4444),
                  tooltip: 'Clear Shape',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

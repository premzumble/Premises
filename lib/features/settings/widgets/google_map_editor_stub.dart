import 'package:flutter/material.dart';

class GoogleMapEditor extends StatefulWidget {
  final String apiKey;
  final double initialLatitude;
  final double initialLongitude;
  final double initialRadius;
  final String initialType;
  final String? initialVerticesJson;
  final Function(Map<String, dynamic> data) onSave;
  final VoidCallback? onChanged;
  final Function(Map<String, dynamic> data)? onChangedData;

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
    this.onChangedData,
  });

  @override
  State<GoogleMapEditor> createState() => _GoogleMapEditorState();
}

class _GoogleMapEditorState extends State<GoogleMapEditor> {
  @override
  Widget build(BuildContext context) {
    throw UnimplementedError('Platform not supported');
  }
}

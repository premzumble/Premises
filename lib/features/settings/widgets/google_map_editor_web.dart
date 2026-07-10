import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

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
  late String _viewId;
  StreamSubscription? _messageSubscription;

  // Guard: true while we're calling onChangedData/onChanged.
  // Prevents didUpdateWidget from reacting to the parent's setState
  // rebuild that our own notification triggered.
  bool _isNotifyingParent = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'google-map-editor-${DateTime.now().millisecondsSinceEpoch}';
    print('[GoogleMapEditorWeb] initState. Initializing platform view with viewId: $_viewId');
    print('[GoogleMapEditorWeb] Received apiKey: "${widget.apiKey}"');

    // Register the custom IFrame platform view
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        print('[GoogleMapEditorWeb] registerViewFactory callback. Generating srcdoc for IFrame. isDark: $isDark');
        final htmlContent = _buildHtmlTemplate(isDark);
        final iframe = html.IFrameElement()
          ..id = _viewId
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..srcdoc = htmlContent;
        return iframe;
      },
    );

    // Listen to messages from the IFrame
    _messageSubscription = html.window.onMessage.listen((event) {
      try {
        final payload = json.decode(event.data);
        if (payload is Map) {
          if (payload['type'] == 'SAVE_GEOFENCE') {
            widget.onSave(Map<String, dynamic>.from(payload['data']));
          } else if (payload['type'] == 'GEOFENCE_CHANGED') {
            // Set guard flag before notifying parent.
            // The parent's onChangedData may call setState, which triggers
            // a rebuild and our didUpdateWidget. The flag tells
            // didUpdateWidget to ignore this rebuild.
            _isNotifyingParent = true;
            if (widget.onChangedData != null && payload['data'] != null) {
              widget.onChangedData!(Map<String, dynamic>.from(payload['data']));
            }
            if (widget.onChanged != null) {
              widget.onChanged!();
            }
            // Clear after the synchronous setState→build→didUpdateWidget cycle.
            _isNotifyingParent = false;
          }
        }
      } catch (_) {
        // Ignore non-json or unrelated messages
      }
    });
  }

  @override
  void didUpdateWidget(covariant GoogleMapEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Skip if this rebuild was triggered by our own notification to the parent.
    if (_isNotifyingParent) return;

    // Only react to meaningful coordinate/type changes (genuine external updates
    // like search or initial fetch, not feedback-loop noise).
    final bool latChanged = (oldWidget.initialLatitude - widget.initialLatitude).abs() > 0.000001;
    final bool lngChanged = (oldWidget.initialLongitude - widget.initialLongitude).abs() > 0.000001;
    final bool radChanged = (oldWidget.initialRadius - widget.initialRadius).abs() > 0.1;
    final bool typeChanged = oldWidget.initialType != widget.initialType;

    if (latChanged || lngChanged || radChanged || typeChanged) {
      // Find IFrame in the DOM and post the SET_LOCATION message
      final iframe = html.document.getElementById(_viewId) as html.IFrameElement?;
      if (iframe != null) {
        iframe.contentWindow?.postMessage(
          json.encode({
            'type': 'SET_LOCATION',
            'latitude': widget.initialLatitude,
            'longitude': widget.initialLongitude,
            'radius': widget.initialRadius,
          }),
          '*',
        );
      }
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('[GoogleMapEditorWeb] build called. rendering HtmlElementView with viewId: $_viewId');
    return HtmlElementView(viewType: _viewId);
  }

  String _buildHtmlTemplate(bool isDark) {
    final String mapStyles = isDark 
        ? '''[
          { elementType: "geometry", stylers: [{ color: "#1e293b" }] },
          { elementType: "labels.text.stroke", stylers: [{ color: "#0f172a" }] },
          { elementType: "labels.text.fill", stylers: [{ color: "#94a3b8" }] },
          { featureType: "administrative", elementType: "geometry", stylers: [{ color: "#334155" }] },
          { featureType: "poi", elementType: "labels.text.fill", stylers: [{ color: "#64748b" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#334155" }] },
          { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#1e293b" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#0f172a" }] }
        ]'''
        : '''[
          { elementType: "geometry", stylers: [{ color: "#f5f5f5" }] },
          { elementType: "labels.text.stroke", stylers: [{ color: "#ffffff" }] },
          { elementType: "labels.text.fill", stylers: [{ color: "#616161" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#ffffff" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#e9e9e9" }] }
        ]''';

    print('[GoogleMapEditorWeb] _buildHtmlTemplate called. Injecting key: "${widget.apiKey}"');

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Google Map Editor</title>
    <style>
    :root {
      --bg-color: ${isDark ? '#0F120F' : '#F9F9F6'};
      --text-color: ${isDark ? '#F1F3F1' : '#1C221C'};
      --sidebar-bg: ${isDark ? '#1B211C' : '#FFFFFF'};
      --border-color: ${isDark ? '#2B342B' : '#E8E8E1'};
      --card-bg: ${isDark ? 'rgba(27, 33, 28, 0.4)' : '#FFFFFF'};
      --text-secondary: ${isDark ? '#A2ABA2' : '#556055'};
      --text-muted: ${isDark ? '#6B756B' : '#98A298'};
      --primary-color: #2E3D30;
      --primary-hover: #1E2B1F;
      --primary-light: #F1F3EE;
      --success-color: #388E3C;
      --danger-color: #D32F2F;
      --warning-color: #F57C00;
      --shadow-sm: ${isDark ? '0 1px 2px rgba(0,0,0,0.3)' : '0 1px 2px rgba(0,0,0,0.03)'};
      --shadow-md: ${isDark ? '0 4px 12px rgba(0,0,0,0.4)' : '0 4px 12px rgba(0,0,0,0.04)'};
      --shadow-lg: ${isDark ? '0 10px 25px rgba(0,0,0,0.5)' : '0 10px 25px rgba(0,0,0,0.05)'};
    }

    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background-color: var(--bg-color);
      color: var(--text-color);
      overflow: hidden;
    }
    
    .gis-container {
      display: flex;
      width: 100%;
      height: 100%;
      position: relative;
    }
    
    /* Collapsible Sidebar Styles */
    .sidebar {
      width: 320px;
      height: 100%;
      background-color: var(--sidebar-bg);
      border-right: 1px solid var(--border-color);
      display: flex;
      flex-direction: column;
      z-index: 10;
      transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      position: absolute;
      left: 0;
      top: 0;
      box-shadow: var(--shadow-lg);
    }
    
    .sidebar.collapsed {
      transform: translateX(-320px);
    }
    
    .sidebar-header {
      padding: 18px 20px;
      border-bottom: 1px solid var(--border-color);
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .sidebar-icon {
      font-size: 20px;
    }
    
    .sidebar-title {
      font-size: 15px;
      font-weight: 700;
      color: var(--text-color);
      letter-spacing: -0.2px;
    }
    
    .collapse-btn {
      background: none;
      border: none;
      color: var(--text-secondary);
      cursor: pointer;
      font-size: 14px;
      padding: 6px;
      border-radius: 6px;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .collapse-btn:hover {
      background: var(--primary-light);
      color: var(--primary-color);
    }

    .expand-btn {
      position: absolute;
      left: 0;
      top: 20px;
      z-index: 20;
      background: var(--sidebar-bg);
      border: 1px solid var(--border-color);
      border-left: none;
      color: var(--text-secondary);
      border-radius: 0 8px 8px 0;
      padding: 14px 10px;
      cursor: pointer;
      box-shadow: var(--shadow-md);
      transition: all 0.2s;
      font-size: 12px;
    }
    .expand-btn:hover {
      color: var(--primary-color);
      background: var(--primary-light);
    }
    
    .sidebar-content {
      flex: 1;
      overflow-y: auto;
      padding: 20px;
      display: flex;
      flex-direction: column;
      gap: 20px;
    }
    
    /* Cards */
    .control-card, .workflow-card, .stats-card {
      background: var(--card-bg);
      border: 1px solid var(--border-color);
      border-radius: 12px;
      padding: 18px;
      box-shadow: var(--shadow-sm);
    }
    
    .card-label {
      font-size: 10px;
      font-weight: 700;
      text-transform: uppercase;
      color: var(--text-muted);
      margin-bottom: 10px;
      display: block;
      letter-spacing: 0.5px;
    }
    
    /* Guided Workflow */
    .workflow-header {
      font-size: 10px;
      font-weight: 800;
      color: var(--primary-color);
      letter-spacing: 1px;
      margin-bottom: 16px;
      text-transform: uppercase;
    }
    
    .steps-container {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    
    .step {
      display: flex;
      align-items: flex-start;
      gap: 12px;
      opacity: 0.4;
      transition: opacity 0.3s;
    }
    
    .step.active {
      opacity: 1;
    }
    
    .step.completed {
      opacity: 0.8;
    }
    
    .step-num {
      width: 20px;
      height: 20px;
      border-radius: 50%;
      background: ${isDark ? '#2B342B' : '#E8E8E1'};
      color: var(--text-muted);
      font-size: 11px;
      font-weight: 700;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.3s;
    }
    
    .step.active .step-num {
      background: var(--primary-color);
      color: #fff;
      box-shadow: 0 0 0 3px ${isDark ? 'rgba(46, 61, 48, 0.4)' : 'rgba(46, 61, 48, 0.15)'};
    }
    
    .step.completed .step-num {
      background: var(--success-color);
      color: #fff;
    }
    
    .step-title {
      font-size: 13px;
      font-weight: 600;
      color: var(--text-secondary);
    }
    .step.active .step-title {
      color: var(--text-color);
    }
    
    .step-desc {
      font-size: 11px;
      color: var(--text-muted);
      margin-top: 2px;
    }
    
    /* Premium Search Box */
    .search-box {
      position: relative;
      display: flex;
      align-items: center;
    }
    
    .search-icon {
      position: absolute;
      left: 12px;
      color: var(--text-muted);
      font-size: 14px;
      display: flex;
      align-items: center;
    }
    
    .search-box input {
      width: 100%;
      padding: 10px 32px 10px 32px;
      background: ${isDark ? '#0F120F' : '#FFFFFF'};
      border: 1px solid var(--border-color);
      border-radius: 8px;
      color: var(--text-color);
      font-size: 13px;
      transition: all 0.2s;
      box-sizing: border-box;
    }
    
    .search-box input:focus {
      outline: none;
      border-color: var(--primary-color);
      box-shadow: 0 0 0 3px ${isDark ? 'rgba(46, 61, 48, 0.4)' : 'rgba(46, 61, 48, 0.15)'};
    }
    
    .clear-search-btn {
      position: absolute;
      right: 12px;
      background: none;
      border: none;
      color: var(--text-muted);
      cursor: pointer;
      font-size: 14px;
      display: flex;
      align-items: center;
      padding: 0;
    }
    .clear-search-btn:hover {
      color: var(--text-color);
    }
    
    .loading-spinner {
      position: absolute;
      right: 32px;
      width: 12px;
      height: 12px;
      border: 2px solid var(--border-color);
      border-top-color: var(--primary-color);
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    
    /* Segmented Mode Selector */
    .mode-selector {
      display: flex;
      background: ${isDark ? '#0F120F' : '#F1F3EE'};
      padding: 4px;
      border-radius: 8px;
      border: 1px solid var(--border-color);
    }
    
    .mode-btn {
      flex: 1;
      background: none;
      border: none;
      color: var(--text-secondary);
      font-size: 13px;
      font-weight: 600;
      padding: 8px 0;
      cursor: pointer;
      border-radius: 6px;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
    }
    
    .mode-btn.active#mode-btn-circle {
      background: var(--primary-color);
      color: #fff;
      box-shadow: var(--shadow-sm);
    }
    
    .mode-btn.active#mode-btn-polygon {
      background: var(--success-color);
      color: #fff;
      box-shadow: var(--shadow-sm);
    }
    
    /* Help Banner */
    .help-tip-banner {
      background: ${isDark ? 'rgba(46, 61, 48, 0.15)' : 'rgba(46, 61, 48, 0.05)'};
      border: 1px dashed ${isDark ? 'rgba(46, 61, 48, 0.3)' : 'rgba(46, 61, 48, 0.2)'};
      border-radius: 8px;
      padding: 12px;
      font-size: 11px;
      line-height: 1.5;
      color: var(--text-secondary);
    }
    
    /* Statistics Card */
    .stats-header {
      font-size: 10px;
      font-weight: 800;
      color: var(--success-color);
      letter-spacing: 1px;
      margin-bottom: 12px;
      text-transform: uppercase;
    }
    
    .stats-grid {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    
    .stat-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 12px;
    }
    
    .stat-label {
      color: var(--text-secondary);
    }
    
    .stat-val {
      font-weight: 600;
      color: var(--text-color);
    }
    
    .stat-val.highlight {
      color: var(--primary-color);
      font-weight: 700;
    }
    
    .badge {
      padding: 4px 8px;
      border-radius: 6px;
      font-size: 10.5px;
      font-weight: 600;
      background: ${isDark ? 'rgba(255,255,255,0.05)' : '#F1F3EE'};
      color: var(--text-secondary);
    }
    .badge.success {
      background: ${isDark ? 'rgba(56, 142, 60, 0.15)' : 'rgba(56, 142, 60, 0.1)'};
      color: var(--success-color);
      border: 1px solid ${isDark ? 'rgba(56, 142, 60, 0.2)' : 'rgba(56, 142, 60, 0.15)'};
    }
    
    /* Warnings Banner */
    .alert-banner {
      display: none;
      background: ${isDark ? 'rgba(211, 47, 47, 0.15)' : 'rgba(211, 47, 47, 0.1)'};
      border: 1px solid ${isDark ? 'rgba(211, 47, 47, 0.2)' : 'rgba(211, 47, 47, 0.15)'};
      color: var(--danger-color);
      border-radius: 8px;
      padding: 12px;
      font-size: 11.5px;
      font-weight: 500;
      line-height: 1.5;
    }
    
    /* Sidebar Footer Button Styles */
    .sidebar-footer {
      padding: 16px 20px;
      border-top: 1px solid var(--border-color);
      background: var(--sidebar-bg);
      display: flex;
      gap: 12px;
    }
    
    .btn {
      flex: 1;
      padding: 10px 16px;
      border: none;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
      text-align: center;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
    }
    
    .btn-secondary {
      background: ${isDark ? 'rgba(255,255,255,0.05)' : '#FFFFFF'};
      color: var(--text-color);
      border: 1px solid var(--border-color);
      box-shadow: var(--shadow-sm);
    }
    .btn-secondary:hover {
      background: var(--primary-light);
    }
    
    .btn-primary {
      background: var(--primary-color);
      color: #fff;
      box-shadow: var(--shadow-sm);
    }
    .btn-primary:hover {
      background: var(--primary-hover);
    }
    
    /* Workspace (Map + Toolbar) */
    .workspace {
      flex: 1;
      height: 100%;
      position: relative;
      margin-left: 320px;
      transition: margin-left 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }
    
    .workspace.full-width {
      margin-left: 0;
    }
    
    #map {
      width: 100%;
      height: 100%;
    }
    
    /* Map Control Toolbar Overlay */
    .map-toolbar {
      position: absolute;
      top: 16px;
      right: 70px; /* Leave space for native map type horizontal bar */
      z-index: 10;
      background: var(--sidebar-bg);
      border: 1px solid var(--border-color);
      border-radius: 8px;
      padding: 5px;
      display: flex;
      align-items: center;
      gap: 4px;
      box-shadow: var(--shadow-md);
    }
    
    .toolbar-item {
      background: none;
      border: none;
      color: var(--text-secondary);
      padding: 6px 12px;
      border-radius: 6px;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      font-weight: 600;
      transition: all 0.2s;
    }
    
    .toolbar-item:hover {
      background: var(--primary-light);
      color: var(--primary-color);
    }
    
    .toolbar-item:disabled {
      opacity: 0.3;
      cursor: not-allowed;
    }
    
    .tb-icon {
      font-size: 14px;
    }
    
    .tb-separator {
      width: 1px;
      height: 18px;
      background: var(--border-color);
      margin: 0 4px;
    }
    
    .btn-danger-text {
      color: var(--danger-color);
    }
    .btn-danger-text:hover {
      background: ${isDark ? 'rgba(211, 47, 47, 0.15)' : 'rgba(211, 47, 47, 0.1)'};
      color: var(--danger-color);
    }
    
    /* Onboarding Tutorial Overlay */
    .onboarding-overlay {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: ${isDark ? 'rgba(15, 18, 15, 0.7)' : 'rgba(249, 249, 246, 0.7)'};
      backdrop-filter: blur(4px);
      z-index: 100;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    
    .onboarding-card {
      background: var(--sidebar-bg);
      border: 1px solid var(--border-color);
      border-radius: 16px;
      padding: 28px;
      width: 380px;
      box-shadow: var(--shadow-lg);
      text-align: center;
      animation: fadeIn 0.4s ease-out;
    }
    
    .onboarding-icon {
      font-size: 40px;
      margin-bottom: 12px;
    }
    
    .onboarding-title {
      font-size: 18px;
      font-weight: 700;
      color: var(--text-color);
      margin-bottom: 8px;
      letter-spacing: -0.2px;
    }
    
    .onboarding-subtitle {
      font-size: 12.5px;
      color: var(--text-secondary);
      line-height: 1.5;
      margin-bottom: 24px;
    }
    
    .onboarding-steps {
      display: flex;
      flex-direction: column;
      gap: 14px;
      text-align: left;
      margin-bottom: 24px;
    }
    
    .obs-item {
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 12.5px;
      color: var(--text-color);
    }
    
    .obs-num {
      width: 22px;
      height: 22px;
      background: var(--primary-color);
      color: #fff;
      font-weight: 700;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 11px;
    }

    /* Google Autocomplete Customization */
    .pac-container {
      background-color: var(--sidebar-bg) !important;
      border: 1px solid var(--border-color) !important;
      border-radius: 10px !important;
      box-shadow: var(--shadow-lg) !important;
      font-family: inherit !important;
      margin-top: 6px !important;
      z-index: 999999 !important;
    }
    
    .pac-item {
      padding: 10px 14px !important;
      font-size: 12.5px !important;
      color: var(--text-secondary) !important;
      border-top: 1px solid var(--border-color) !important;
      cursor: pointer !important;
      display: flex !important;
      align-items: center !important;
      gap: 8px !important;
      line-height: 1.6 !important;
    }
    
    .pac-item:hover {
      background-color: var(--primary-light) !important;
      color: var(--primary-color) !important;
    }
    
    .pac-item-query {
      font-size: 12.5px !important;
      color: var(--text-color) !important;
      font-weight: 600 !important;
    }
    
    .pac-matched {
      color: var(--primary-color) !important;
    }
    
    .pac-icon {
      margin-top: 0 !important;
      background-image: none !important;
      width: 14px !important;
      height: 14px !important;
      display: inline-block !important;
      position: relative !important;
    }
    
    .pac-icon::before {
      content: "📍" !important;
      font-size: 12px !important;
      position: absolute !important;
      top: -1px !important;
      left: 0 !important;
    }
    
    .pac-logo::after {
      display: none !important;
    }
    
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(10px); }
      to { opacity: 1; transform: translateY(0); }
    }
  </style>
</head>
<body>
  <div class="gis-container">
    <!-- Collapsible Sidebar -->
    <div class="sidebar" id="sidebar">
      <div class="sidebar-header">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span class="sidebar-icon">🗺️</span>
          <span class="sidebar-title">Campus Geofence</span>
        </div>
        <button class="collapse-btn" onclick="toggleSidebar()" title="Collapse Panel">◀</button>
      </div>
      
      <div class="sidebar-content">
        <!-- Guided Workflow steps -->
        <div class="workflow-card">
          <div class="workflow-header">Guided Configuration</div>
          <div class="steps-container">
            <div class="step active" id="step-1">
              <span class="step-num">1</span>
              <div class="step-text">
                <div class="step-title">Search Location</div>
                <div class="step-desc">Locate campus coordinates</div>
              </div>
            </div>
            <div class="step" id="step-2">
              <span class="step-num">2</span>
              <div class="step-text">
                <div class="step-title">Choose Shape Mode</div>
                <div class="step-desc">Select Circle or Custom Polygon</div>
              </div>
            </div>
            <div class="step" id="step-3">
              <span class="step-num">3</span>
              <div class="step-text">
                <div class="step-title">Draw Boundary</div>
                <div class="step-desc">Click/drag shape bounds</div>
              </div>
            </div>
            <div class="step" id="step-4">
              <span class="step-num">4</span>
              <div class="step-text">
                <div class="step-title">Review Measurements</div>
                <div class="step-desc">Verify area calculations</div>
              </div>
            </div>
            <div class="step" id="step-5">
              <span class="step-num">5</span>
              <div class="step-text">
                <div class="step-title">Commit Changes</div>
                <div class="step-desc">Save boundary definition</div>
              </div>
            </div>
          </div>
        </div>

        <!-- Places search Autocomplete Box -->
        <div class="control-card">
          <label class="card-label">Step 1: Search Campus Location</label>
          <div class="search-box">
            <span class="search-icon">🔍</span>
            <input type="text" id="search" placeholder="Type campus name, address..." />
            <button class="clear-search-btn" id="clear-search-btn" onclick="clearSearch()" style="display:none;">✕</button>
            <div class="loading-spinner" id="search-spinner" style="display:none;"></div>
          </div>
        </div>

        <!-- Circle / Polygon Mode buttons -->
        <div class="control-card">
          <label class="card-label">Step 2: Choose Boundary Mode</label>
          <div class="mode-selector">
            <button class="mode-btn active" id="mode-btn-circle" onclick="setMode('circle')">
              <span class="mode-icon">⭕</span> Circle
            </button>
            <button class="mode-btn" id="mode-btn-polygon" onclick="setMode('polygon')">
              <span class="mode-icon">⬡</span> Polygon
            </button>
          </div>
        </div>

        <!-- Instruction tips banner -->
        <div class="help-tip-banner" id="help-tip">
          Campus search: Enter your institution's name to pan the camera. Drag the circular pin to relocation.
        </div>

        <!-- Live Statistics Panel -->
        <div class="stats-card">
          <div class="stats-header">Live Boundary Metrics</div>
          <div class="stats-grid">
            <div class="stat-row">
              <span class="stat-label">Active Mode:</span>
              <span class="stat-val badge" id="stat-mode">Circle</span>
            </div>
            <div class="stat-row">
              <span class="stat-label">Status:</span>
              <span class="stat-val badge success" id="stat-status">Active</span>
            </div>
            <div class="stat-row">
              <span class="stat-label">Calculated Area:</span>
              <span class="stat-val highlight" id="stat-area">0 m²</span>
            </div>
            <div class="stat-row" id="stat-row-radius">
              <span class="stat-label">Circle Radius:</span>
              <span class="stat-val" id="stat-radius">0 m</span>
            </div>
            <div class="stat-row" id="stat-row-perimeter" style="display:none;">
              <span class="stat-label">Polygon Perimeter:</span>
              <span class="stat-val" id="stat-perimeter">0 m</span>
            </div>
            <div class="stat-row" id="stat-row-vertices" style="display:none;">
              <span class="stat-label">Vertices Count:</span>
              <span class="stat-val" id="stat-vertices">0</span>
            </div>
            <div class="stat-row">
              <span class="stat-label">Center Coordinate:</span>
              <span class="stat-val" id="stat-center">0.0, 0.0</span>
            </div>
            <div class="stat-row">
              <span class="stat-label">Last Updated:</span>
              <span class="stat-val" id="stat-updated">Just now</span>
            </div>
          </div>
        </div>

        <!-- Geometry warnings alerts -->
        <div class="alert-banner" id="alert-box"></div>

        <!-- Safe Recovery Banner -->
        <div class="recovery-banner" id="recovery-box" style="display:none; margin-top: 12px; padding: 12px; background: rgba(239, 68, 68, 0.15); border: 1px solid #ef4444; border-radius: 8px; text-align: center;">
          <span style="color: #f87171; font-size: 13px; font-weight: 500; display: block; margin-bottom: 8px;" id="recovery-error-msg">⚠️ Polygon rendering error detected.</span>
          <button class="btn btn-secondary" onclick="restoreCurrentGeofence()" style="font-size: 12px; padding: 6px 12px; width: auto; background: rgba(239, 68, 68, 0.2); border-color: #ef4444; color: #f87171; cursor: pointer; border-radius: 4px;">Restore Saved Geofence</button>
        </div>
      </div>
      
      <!-- Action buttons -->
      <div class="sidebar-footer">
        <button class="btn btn-secondary" onclick="cancelChanges()">Cancel</button>
        <button class="btn btn-primary" id="btn-save" onclick="saveGeofence()">Save Geofence</button>
      </div>
    </div>

    <!-- Expand Sidebar button -->
    <button class="expand-btn" id="expand-btn" onclick="toggleSidebar()" style="display:none;">▶</button>

    <!-- Workspace -->
    <div class="workspace" id="workspace">
      <div id="map"></div>
      
      <!-- Toolbar Overlay -->
      <div class="map-toolbar">
        <button class="toolbar-item" id="tb-undo" onclick="undo()" title="Undo Action (Ctrl+Z)">
          <span class="tb-icon">↩</span><span class="tb-text">Undo</span>
        </button>
        <button class="toolbar-item" id="tb-redo" onclick="redo()" title="Redo Action (Ctrl+Y)">
          <span class="tb-icon">↪</span><span class="tb-text">Redo</span>
        </button>
        <div class="tb-separator"></div>
        <button class="toolbar-item" id="tb-center" onclick="centerMap()" title="Center Map on Campus">
          <span class="tb-icon">🎯</span><span class="tb-text">Center</span>
        </button>
        <button class="toolbar-item" id="tb-fit" onclick="fitBoundary()" title="Fit Map to Boundary">
          <span class="tb-icon">🔍</span><span class="tb-text">Fit Bounds</span>
        </button>
        <button class="toolbar-item" id="tb-clear" onclick="clearShape()" title="Clear Boundary Shape">
          <span class="tb-icon">🗑️</span><span class="tb-text">Clear Shape</span>
        </button>
        <button class="toolbar-item btn-danger-text" id="tb-reset" onclick="resetMap()" title="Reset to Saved Config">
          <span class="tb-icon">🔄</span><span class="tb-text">Reset</span>
        </button>
      </div>

      <!-- Onboarding Onscreen Banner -->
      <div class="onboarding-overlay" id="onboarding-overlay" style="display:none;">
        <div class="onboarding-card">
          <div class="onboarding-icon">🗺️</div>
          <div class="onboarding-title">Campus Boundary Setup</div>
          <div class="onboarding-subtitle">Define your campus boundaries to verify faculty attendance check-ins in real time.</div>
          <div class="onboarding-steps">
            <div class="obs-item">
              <span class="obs-num">1</span>
              <span>Search for your campus location in the search bar.</span>
            </div>
            <div class="obs-item">
              <span class="obs-num">2</span>
              <span>Choose Circle or Custom Polygon shape.</span>
            </div>
            <div class="obs-item">
              <span class="obs-num">3</span>
              <span>Position the boundary and click Save Geofence.</span>
            </div>
          </div>
          <button class="btn btn-primary" style="margin-top: 16px; width: 100%;" onclick="dismissOnboarding()">Get Started</button>
        </div>
      </div>
    </div>
  </div>

  <script>
    let map;
    let autocomplete;
    let activeMode = "${widget.initialType}";
    let isDrawing = false;
    let hoverLine = null;
    let isPolygonCustomized = false;

    // Circle config state
    let centerMarker;
    let mapCircle;
    let circleCenter = { lat: ${widget.initialLatitude}, lng: ${widget.initialLongitude} };
    let circleRadius = ${widget.initialRadius};

    // Polygon config state
    let mapPolygon;
    let polygonVertices = [];
    let isUpdatingPath = false;
    let onPathChangedGlobal = null;

    function updatePolygonPath(vertices) {
      try {
        if (!mapPolygon) return;
        let path = mapPolygon.getPath();
        if (!path) {
          const newPath = new google.maps.MVCArray();
          mapPolygon.setPath(newPath);
          path = mapPolygon.getPath();
        }
        if (!path) return;
        isUpdatingPath = true;
        path.clear();
        for (const v of vertices) {
          path.push(new google.maps.LatLng(v.lat, v.lng));
        }
        isUpdatingPath = false;
        if (onPathChangedGlobal) onPathChangedGlobal();
        const recoveryBox = document.getElementById('recovery-box');
        if (recoveryBox) recoveryBox.style.display = 'none';
      } catch (e) {
        console.error("Failed to update polygon path:", e);
        const errorMsg = document.getElementById('recovery-error-msg');
        if (errorMsg) errorMsg.innerText = "⚠️ Path error: " + (e.message || e);
        const recoveryBox = document.getElementById('recovery-box');
        if (recoveryBox) recoveryBox.style.display = 'block';
      }
    }

    // History state stacks for Undo/Redo
    let undoStack = [];
    let redoStack = [];

    // Parse initial coordinates
    try {
      const initVerts = ${widget.initialVerticesJson ?? '[]'};
      if (initVerts && initVerts.length > 0) {
        polygonVertices = initVerts.map(v => {
          const latVal = v.latitude !== undefined ? v.latitude : v.lat;
          const lngVal = v.longitude !== undefined ? v.longitude : v.lng;
          return { lat: parseFloat(latVal), lng: parseFloat(lngVal) };
        }).filter(v => !isNaN(v.lat) && !isNaN(v.lng));
        isPolygonCustomized = true;
      }
    } catch (e) {
      console.error("Error parsing initial vertices", e);
    }

    // Toggle Sidebar collapse
    function toggleSidebar() {
      const sidebar = document.getElementById('sidebar');
      const workspace = document.getElementById('workspace');
      const expandBtn = document.getElementById('expand-btn');
      
      sidebar.classList.toggle('collapsed');
      workspace.classList.toggle('full-width');
      
      if (sidebar.classList.contains('collapsed')) {
        expandBtn.style.display = 'block';
      } else {
        expandBtn.style.display = 'none';
      }
      // Re-layout map
      setTimeout(() => {
        if (map) google.maps.event.trigger(map, 'resize');
      }, 300);
    }

    function initMap() {
      // Create modern Google Map with hybrid map type Horizontal bar, Pegman streetview, scale/zoom controls
      const initialCenter = activeMode === 'polygon' && polygonVertices.length > 0 
        ? calculateCentroid(polygonVertices)
        : circleCenter;

      map = new google.maps.Map(document.getElementById('map'), {
        center: initialCenter,
        zoom: 15,
        mapTypeId: 'roadmap',
        disableDoubleClickZoom: true,
        mapTypeControl: true,
        mapTypeControlOptions: {
          style: google.maps.MapTypeControlStyle.HORIZONTAL_BAR,
          position: google.maps.ControlPosition.TOP_RIGHT
        },
        zoomControl: true,
        zoomControlOptions: {
          position: google.maps.ControlPosition.RIGHT_CENTER
        },
        fullscreenControl: true,
        streetViewControl: true,
        streetViewControlOptions: {
          position: google.maps.ControlPosition.RIGHT_CENTER
        },
        scaleControl: true,
        styles: $mapStyles
      });

      // Autocomplete Search Box
      const searchBox = document.getElementById('search');
      autocomplete = new google.maps.places.Autocomplete(searchBox);
      autocomplete.bindTo('bounds', map);
      autocomplete.addListener('place_changed', onPlaceSelected);

      // Listen to search typing to toggle clear icon
      searchBox.addEventListener('input', function() {
        document.getElementById('clear-search-btn').style.display = this.value ? 'block' : 'none';
      });

      // Init shape instances
      setupCircleElements();
      setupPolygonElements();

      // Click to draw custom polygon
      map.addListener('click', function(e) {
        if (activeMode === 'polygon' && isDrawing) {
          saveHistoryState();
          const clickedLoc = e.latLng.toJSON();
          
          // Check if close to first vertex to close path (within 15 meters)
          if (polygonVertices.length >= 3 && google.maps.geometry) {
            const first = polygonVertices[0];
            const dist = google.maps.geometry.spherical.computeDistanceBetween(
              e.latLng, 
              new google.maps.LatLng(first.lat, first.lng)
            );
            if (dist < 15) {
              completeDrawing();
              return;
            }
          }
          
          polygonVertices.push(clickedLoc);
          drawActivePolygon();
          updateUI();
        }
      });

      // Mousemove for hoverPreview polygon segment lines
      map.addListener('mousemove', function(e) {
        if (activeMode === 'polygon' && isDrawing && polygonVertices.length > 0) {
          const lastPoint = polygonVertices[polygonVertices.length - 1];
          const mouseLoc = e.latLng;
          if (!hoverLine) {
            hoverLine = new google.maps.Polyline({
              strokeColor: '#10b981',
              strokeOpacity: 0.6,
              strokeWeight: 2,
              map: map,
              clickable: false
            });
          }
          hoverLine.setPath([lastPoint, mouseLoc]);
        }
      });

      // Double click listener to complete drawing or relocate/translate active shape
      map.addListener('dblclick', function(e) {
        if (activeMode === 'polygon' && isDrawing) {
          if (polygonVertices.length >= 3) {
            completeDrawing();
          }
          return;
        }

        saveHistoryState();
        const clickedLoc = e.latLng.toJSON();
        if (activeMode === 'circle') {
          circleCenter = clickedLoc;
          centerMarker.setPosition(circleCenter);
          mapCircle.setCenter(circleCenter);
          
          // Re-center polygon vertices around the new center
          if (polygonVertices.length > 0) {
            const centroid = calculateCentroid(polygonVertices);
            const dLat = circleCenter.lat - centroid.lat;
            const dLng = circleCenter.lng - centroid.lng;
            polygonVertices = polygonVertices.map(v => ({
              lat: v.lat + dLat,
              lng: v.lng + dLng
            }));
            updatePolygonPath(polygonVertices);
          } else {
            const offset = 0.001;
            polygonVertices = [
              { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
              { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
              { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
              { lat: circleCenter.lat - offset, lng: circleCenter.lng + offset }
            ];
            updatePolygonPath(polygonVertices);
          }
        } else {
          // Translate polygon vertices around the double-clicked centroid
          if (polygonVertices.length > 0) {
            const centroid = calculateCentroid(polygonVertices);
            const dLat = clickedLoc.lat - centroid.lat;
            const dLng = clickedLoc.lng - centroid.lng;
            polygonVertices = polygonVertices.map(v => ({
              lat: v.lat + dLat,
              lng: v.lng + dLng
            }));
            updatePolygonPath(polygonVertices);
          }
        }
        updateUI();
        notifyChanged();
      });

      // Listen to postMessage location updates from parent Flutter widget
      window.addEventListener('message', function(event) {
        try {
          const payload = JSON.parse(event.data);
          if (payload && payload.type === 'SET_LOCATION') {
            const lat = payload.latitude;
            const lng = payload.longitude;
            const rad = payload.radius;
            const loc = { lat: lat, lng: lng };

            map.setCenter(loc);
            map.setZoom(16);

            saveHistoryState();

             if (activeMode === 'circle') {
              circleCenter = loc;
              circleRadius = rad;
              centerMarker.setPosition(circleCenter);
              mapCircle.setCenter(circleCenter);
              mapCircle.setRadius(circleRadius);

              // Translate polygon vertices around the new center
              if (polygonVertices.length > 0) {
                const centroid = calculateCentroid(polygonVertices);
                const dLat = circleCenter.lat - centroid.lat;
                const dLng = circleCenter.lng - centroid.lng;
                if (Math.abs(dLat) > 1e-9 || Math.abs(dLng) > 1e-9) {
                  polygonVertices = polygonVertices.map(v => ({
                    lat: v.lat + dLat,
                    lng: v.lng + dLng
                  }));
                  updatePolygonPath(polygonVertices);
                }
              } else {
                const offset = 0.001;
                polygonVertices = [
                  { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
                  { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
                  { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
                  { lat: circleCenter.lat - offset, lng: circleCenter.lng + offset }
                ];
                updatePolygonPath(polygonVertices);
              }
            } else {
              // activeMode is polygon
              if (polygonVertices.length > 0) {
                const centroid = calculateCentroid(polygonVertices);
                const dLat = loc.lat - centroid.lat;
                const dLng = loc.lng - centroid.lng;
                if (Math.abs(dLat) > 1e-9 || Math.abs(dLng) > 1e-9) {
                  polygonVertices = polygonVertices.map(v => ({
                    lat: v.lat + dLat,
                    lng: v.lng + dLng
                  }));
                  updatePolygonPath(polygonVertices);
                }
              } else {
                // Place default polygon bounds around coordinate
                const offset = 0.001;
                polygonVertices = [
                  { lat: loc.lat - offset, lng: loc.lng - offset },
                  { lat: loc.lat + offset, lng: loc.lng - offset },
                  { lat: loc.lat + offset, lng: loc.lng + offset },
                  { lat: loc.lat - offset, lng: loc.lng + offset }
                ];
                isDrawing = false;
                mapPolygon.setOptions({
                  clickable: true,
                  editable: true,
                  draggable: true
                });
                updatePolygonPath(polygonVertices);
                mapPolygon.setMap(map);
                isPolygonCustomized = true;
              }
            }
            updateUI();
            notifyChanged();
          }
        } catch (err) {
          // Ignore non-json messages
        }
      });

      // Check onboarding state
      if (${widget.initialLatitude} === 18.403817 && ${widget.initialLongitude} === 76.560943 && polygonVertices.length === 0) {
        document.getElementById('onboarding-overlay').style.display = 'flex';
      }

      setMode(activeMode);
    }

    function dismissOnboarding() {
      document.getElementById('onboarding-overlay').style.display = 'none';
      document.getElementById('step-1').classList.add('active');
    }

    function setupCircleElements() {
      centerMarker = new google.maps.Marker({
        position: circleCenter,
        map: null,
        draggable: true,
        title: "Relocate Geofence center"
      });

      mapCircle = new google.maps.Circle({
        map: null,
        center: circleCenter,
        radius: circleRadius,
        editable: true,
        draggable: true,
        fillColor: '#4f46e5',
        fillOpacity: 0.12,
        strokeColor: '#4f46e5',
        strokeWeight: 2
      });

      // Drag center events
      centerMarker.addListener('dragend', () => {
        saveHistoryState();
        circleCenter = centerMarker.getPosition().toJSON();
        mapCircle.setCenter(circleCenter);
        
        // Translate polygon vertices around the new center
        if (polygonVertices.length > 0) {
          const centroid = calculateCentroid(polygonVertices);
          const dLat = circleCenter.lat - centroid.lat;
          const dLng = circleCenter.lng - centroid.lng;
          if (Math.abs(dLat) > 1e-9 || Math.abs(dLng) > 1e-9) {
            polygonVertices = polygonVertices.map(v => ({
              lat: v.lat + dLat,
              lng: v.lng + dLng
            }));
            updatePolygonPath(polygonVertices);
          }
        } else {
          const offset = 0.001;
          polygonVertices = [
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
            { lat: circleCenter.lat - offset, lng: circleCenter.lng + offset }
          ];
          updatePolygonPath(polygonVertices);
        }
        
        updateUI();
        notifyChanged();
      });

      mapCircle.addListener('center_changed', () => {
        circleCenter = mapCircle.getCenter().toJSON();
        centerMarker.setPosition(circleCenter);
        
        // Translate polygon vertices around the new center
        if (polygonVertices.length > 0) {
          const centroid = calculateCentroid(polygonVertices);
          const dLat = circleCenter.lat - centroid.lat;
          const dLng = circleCenter.lng - centroid.lng;
          if (Math.abs(dLat) > 1e-9 || Math.abs(dLng) > 1e-9) {
            polygonVertices = polygonVertices.map(v => ({
              lat: v.lat + dLat,
              lng: v.lng + dLng
            }));
            updatePolygonPath(polygonVertices);
          }
        } else {
          const offset = 0.001;
          polygonVertices = [
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
            { lat: circleCenter.lat - offset, lng: circleCenter.lng + offset }
          ];
          updatePolygonPath(polygonVertices);
        }
        
        updateUI();
        notifyChanged();
      });

      mapCircle.addListener('radius_changed', () => {
        circleRadius = mapCircle.getRadius();
        updateUI();
        notifyChanged();
      });
    }

    function setupPolygonElements() {
      try {
        const initialPath = new google.maps.MVCArray();
        if (polygonVertices && polygonVertices.length > 0) {
          for (const v of polygonVertices) {
            initialPath.push(new google.maps.LatLng(v.lat, v.lng));
          }
        }

        mapPolygon = new google.maps.Polygon({
          paths: initialPath,
          map: null,
          editable: !isDrawing,
          draggable: !isDrawing,
          clickable: !isDrawing,
          fillColor: '#10b981',
          fillOpacity: 0.12,
          strokeColor: '#10b981',
          strokeWeight: 2
        });

        // Edit handlers
        let path = mapPolygon.getPath();
        if (!path) {
          const newPath = new google.maps.MVCArray();
          mapPolygon.setPath(newPath);
          path = mapPolygon.getPath();
        }
        const onPathChanged = (isFinal) => {
          if (isUpdatingPath) return;
          let rawVertices = [];
          for (let i = 0; i < path.getLength(); i++) {
            const pt = path.getAt(i);
            rawVertices.push({
              lat: typeof pt.lat === 'function' ? pt.lat() : pt.lat,
              lng: typeof pt.lng === 'function' ? pt.lng() : pt.lng
            });
          }
          const cleaned = removeDuplicateVertices(rawVertices);
          
          if (cleaned.length !== rawVertices.length) {
            // Found and removed duplicates, update map path asynchronously
            setTimeout(() => updatePolygonPath(cleaned), 0);
            return;
          }
          
          if (isFinal !== false) {
            saveHistoryState();
          }
          polygonVertices = cleaned;
          isPolygonCustomized = true;
          
          // Sync circle center to polygon centroid
          if (polygonVertices.length > 0) {
            circleCenter = calculateCentroid(polygonVertices);
            centerMarker.setPosition(circleCenter);
            mapCircle.setCenter(circleCenter);
          }
          
          updateUI();
          notifyChanged();
        };
        onPathChangedGlobal = onPathChanged;

        path.addListener('insert_at', onPathChanged);
        path.addListener('remove_at', onPathChanged);
        path.addListener('set_at', onPathChanged);
        
        mapPolygon.addListener('drag', () => {
          onPathChanged(false);
        });

        mapPolygon.addListener('dragend', () => {
          onPathChanged(true);
        });

        // Right-click polygon vertex to delete
        mapPolygon.addListener('rightclick', function(mev) {
          if (mev.vertex !== undefined) {
            saveHistoryState();
            mapPolygon.getPath().removeAt(mev.vertex);
          }
        });
        const recoveryBox = document.getElementById('recovery-box');
        if (recoveryBox) recoveryBox.style.display = 'none';
      } catch (e) {
        console.error("Failed to setup polygon elements:", e);
        const errorMsg = document.getElementById('recovery-error-msg');
        if (errorMsg) errorMsg.innerText = "⚠️ Setup error: " + (e.message || e);
        const recoveryBox = document.getElementById('recovery-box');
        if (recoveryBox) recoveryBox.style.display = 'block';
      }
    }

    function drawActivePolygon() {
      if (polygonVertices.length < 3) {
        // Render polyline
        if (mapPolygon) mapPolygon.setMap(null);
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
      } else {
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
      }
    }

    function removeDuplicateVertices(verts) {
      const clean = [];
      for (const v of verts) {
        if (clean.length === 0) {
          clean.push(v);
        } else {
          const last = clean[clean.length - 1];
          if (Math.abs(last.lat - v.lat) > 1e-7 || Math.abs(last.lng - v.lng) > 1e-7) {
            clean.push(v);
          }
        }
      }
      if (clean.length > 1) {
        const first = clean[0];
        const last = clean[clean.length - 1];
        if (Math.abs(first.lat - last.lat) < 1e-7 && Math.abs(first.lng - last.lng) < 1e-7) {
          clean.pop();
        }
      }
      return clean;
    }

    function completeDrawing() {
      isDrawing = false;
      if (hoverLine) {
        hoverLine.setMap(null);
        hoverLine = null;
      }
      polygonVertices = removeDuplicateVertices(polygonVertices);
      mapPolygon.setOptions({
        clickable: true,
        editable: true,
        draggable: true
      });
      updatePolygonPath(polygonVertices);
      mapPolygon.setMap(map);
      isPolygonCustomized = true;
      updateUI();
    }

    function onPlaceSelected() {
      const place = autocomplete.getPlace();
      if (!place.geometry || !place.geometry.location) {
        return;
      }
      
      const loc = place.geometry.location;
      map.setCenter(loc);
      map.setZoom(16);

      saveHistoryState();

      if (activeMode === 'circle') {
        circleCenter = loc.toJSON();
        centerMarker.setPosition(circleCenter);
        mapCircle.setCenter(circleCenter);

        // Translate polygon vertices around the new center
        if (polygonVertices.length > 0) {
          const centroid = calculateCentroid(polygonVertices);
          const dLat = circleCenter.lat - centroid.lat;
          const dLng = circleCenter.lng - centroid.lng;
          polygonVertices = polygonVertices.map(v => ({
            lat: v.lat + dLat,
            lng: v.lng + dLng
          }));
          updatePolygonPath(polygonVertices);
        } else {
          const offset = 0.001;
          const newC = loc.toJSON();
          polygonVertices = [
            { lat: newC.lat - offset, lng: newC.lng - offset },
            { lat: newC.lat + offset, lng: newC.lng - offset },
            { lat: newC.lat + offset, lng: newC.lng + offset },
            { lat: newC.lat - offset, lng: newC.lng + offset }
          ];
          updatePolygonPath(polygonVertices);
        }
      } else {
        // Place default polygon bounds around searched coordinate
        const offset = 0.001;
        const newC = loc.toJSON();
        polygonVertices = [
          { lat: newC.lat - offset, lng: newC.lng - offset },
          { lat: newC.lat + offset, lng: newC.lng - offset },
          { lat: newC.lat + offset, lng: newC.lng + offset },
          { lat: newC.lat - offset, lng: newC.lng + offset }
        ];
        isDrawing = false;
        mapPolygon.setOptions({
          clickable: true,
          editable: true,
          draggable: true
        });
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
        isPolygonCustomized = true;

        // Sync circle too
        circleCenter = newC;
        centerMarker.setPosition(circleCenter);
        mapCircle.setCenter(circleCenter);
      }
      
      updateUI();
      notifyChanged();
      
      // Update step progress
      document.getElementById('step-1').className = 'step completed';
      document.getElementById('step-2').classList.add('active');
    }

    function clearSearch() {
      document.getElementById('search').value = '';
      document.getElementById('clear-search-btn').style.display = 'none';
    }

    function setMode(mode) {
      activeMode = mode;
      saveHistoryState();

      document.getElementById('mode-btn-circle').className = mode === 'circle' ? 'mode-btn active' : 'mode-btn';
      document.getElementById('mode-btn-polygon').className = mode === 'polygon' ? 'mode-btn active' : 'mode-btn';
      
      document.getElementById('stat-mode').innerText = mode === 'circle' ? 'Circle' : 'Custom Polygon';
      
      if (mode === 'circle') {
        document.getElementById('stat-row-radius').style.display = 'flex';
        document.getElementById('stat-row-perimeter').style.display = 'none';
        document.getElementById('stat-row-vertices').style.display = 'none';
        document.getElementById('help-tip').innerText = 'Step 3 Help: Resize the circle geofence by dragging its outer bounding handles. Drag the center node to relocate.';

        centerMarker.setMap(map);
        mapCircle.setMap(map);
        mapPolygon.setMap(null);
        if (hoverLine) {
          hoverLine.setMap(null);
          hoverLine = null;
        }
      } else {
        document.getElementById('stat-row-radius').style.display = 'none';
        document.getElementById('stat-row-perimeter').style.display = 'flex';
        document.getElementById('stat-row-vertices').style.display = 'flex';
        document.getElementById('help-tip').innerText = 'Step 3 Help: Click locations on the map to add boundary corners. Drag vertices to adjust segments. Right-click points to delete. Double-click to complete.';

        centerMarker.setMap(null);
        mapCircle.setMap(null);
        
        if (polygonVertices.length === 0) {
          const offset = 0.001;
          polygonVertices = [
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
            { lat: circleCenter.lat - offset, lng: circleCenter.lng + offset }
          ];
          isDrawing = false;
          mapPolygon.setOptions({
            clickable: true,
            editable: true,
            draggable: true
          });
          updatePolygonPath(polygonVertices);
          mapPolygon.setMap(map);
          isPolygonCustomized = true;
        } else {
          isDrawing = false;
          mapPolygon.setOptions({
            clickable: true,
            editable: true,
            draggable: true
          });
          updatePolygonPath(polygonVertices);
          mapPolygon.setMap(map);
        }
      }

      updateUI();
      notifyChanged();
      
      document.getElementById('step-2').className = 'step completed';
      document.getElementById('step-3').classList.add('active');
    }

    // Centroid calculation
    function calculateCentroid(points) {
      if (points.length === 0) return circleCenter;
      let latSum = 0;
      let lngSum = 0;
      for (const p of points) {
        latSum += p.lat;
        lngSum += p.lng;
      }
      return { lat: latSum / points.length, lng: lngSum / points.length };
    }

    // Geometry statistics
    function updateUI() {
      const alertBox = document.getElementById('alert-box');
      const saveBtn = document.getElementById('btn-save');
      
      alertBox.style.display = 'none';
      saveBtn.disabled = false;

      // Update Toolbar buttons states
      document.getElementById('tb-undo').disabled = undoStack.length === 0;
      document.getElementById('tb-redo').disabled = redoStack.length === 0;

      if (activeMode === 'circle') {
        const centerStr = circleCenter.lat.toFixed(5) + ", " + circleCenter.lng.toFixed(5);
        document.getElementById('stat-center').innerText = centerStr;
        document.getElementById('stat-radius').innerText = Math.round(circleRadius) + " m";
        
        const area = Math.PI * Math.pow(circleRadius, 2);
        document.getElementById('stat-area').innerText = formatArea(area);

        // Validation
        if (circleRadius < 10 || circleRadius > 10000) {
          alertBox.innerText = "Validation Warning: Circle radius must be between 10m and 10km.";
          alertBox.style.display = 'block';
          saveBtn.disabled = true;
        }
      } else {
        document.getElementById('stat-vertices').innerText = polygonVertices.length;
        
        const centroid = calculateCentroid(polygonVertices);
        document.getElementById('stat-center').innerText = centroid.lat.toFixed(5) + ", " + centroid.lng.toFixed(5);

        // Calculate exact area and perimeter using Maps spherical geometry library
        if (polygonVertices.length >= 3 && google.maps.geometry) {
          const path = polygonVertices.map(v => new google.maps.LatLng(v.lat, v.lng));
          const area = google.maps.geometry.spherical.computeArea(path);
          const perimeter = google.maps.geometry.spherical.computeLength(path);

          document.getElementById('stat-area').innerText = formatArea(area);
          document.getElementById('stat-perimeter').innerText = Math.round(perimeter) + " m";

          // Check consecutive duplicates & degenerate
          let hasDuplicates = false;
          for (let i = 0; i < polygonVertices.length; i++) {
            let p1 = polygonVertices[i];
            let p2 = polygonVertices[(i + 1) % polygonVertices.length];
            if (Math.abs(p1.lat - p2.lat) < 1e-9 && Math.abs(p1.lng - p2.lng) < 1e-9) {
              hasDuplicates = true;
              break;
            }
          }
          let uniquePoints = [];
          for (let p of polygonVertices) {
            if (!uniquePoints.some(up => Math.abs(up.lat - p.lat) < 1e-9 && Math.abs(up.lng - p.lng) < 1e-9)) {
              uniquePoints.push(p);
            }
          }

          if (uniquePoints.length < 3) {
            alertBox.innerText = "Invalid Boundary: Polygon must have at least 3 unique vertices.";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (hasDuplicates) {
            alertBox.innerText = "Invalid Boundary: Duplicate consecutive vertices detected.";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (isSelfIntersecting(polygonVertices)) {
            alertBox.innerText = "Invalid Boundary: Self-intersecting edges detected. Adjust vertices to resolve crossings.";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (area < 100) {
            alertBox.innerText = "Validation Warning: Boundary area is too small (" + Math.round(area) + " m²). Must be at least 100 m².";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (area > 100000000) {
            alertBox.innerText = "Validation Warning: Boundary area is too large. Must be under 100 km².";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          }
        } else {
          document.getElementById('stat-area').innerText = "0 m²";
          document.getElementById('stat-perimeter').innerText = "0 m";
        }
      }

      // Update guided workflow progress indicator
      if (!saveBtn.disabled && (activeMode === 'circle' || polygonVertices.length >= 3)) {
        document.getElementById('step-3').className = 'step completed';
        document.getElementById('step-4').className = 'step active';
      }
    }

    function formatArea(area) {
      if (area >= 1000000) {
        return (area / 1000000).toFixed(2) + " km²";
      }
      return Math.round(area).toLocaleString() + " m²";
    }

    // Geometry Helpers
    function checkOrientation(p, q, r) {
      const val = (q.lng - p.lng) * (r.lat - q.lat) - (q.lat - p.lat) * (r.lng - q.lng);
      if (Math.abs(val) < 1e-9) return 0;
      return val > 0 ? 1 : 2;
    }

    function onSegment(p, q, r) {
      if (q.lat <= Math.max(p.lat, r.lat) && q.lat >= Math.min(p.lat, r.lat) &&
          q.lng <= Math.max(p.lng, r.lng) && q.lng >= Math.min(p.lng, r.lng)) {
        return true;
      }
      return false;
    }

    function doSegmentsIntersect(p1, q1, p2, q2) {
      const o1 = checkOrientation(p1, q1, p2);
      const o2 = checkOrientation(p1, q1, q2);
      const o3 = checkOrientation(p2, q2, p1);
      const o4 = checkOrientation(p2, q2, q1);

      if (o1 !== o2 && o3 !== o4) return true;

      if (o1 === 0 && onSegment(p1, p2, q1)) return true;
      if (o2 === 0 && onSegment(p1, q2, q1)) return true;
      if (o3 === 0 && onSegment(p2, p1, q2)) return true;
      if (o4 === 0 && onSegment(p2, q1, q2)) return true;

      return false;
    }

    function isSelfIntersecting(points) {
      const n = points.length;
      if (n < 4) return false;
      const edges = [];
      for (let i = 0; i < n; i++) {
        edges.push({ p1: points[i], p2: points[(i + 1) % n] });
      }
      for (let i = 0; i < n; i++) {
        for (let j = i + 2; j < n; j++) {
          if (i === 0 && j === n - 1) continue;
          if (doSegmentsIntersect(edges[i].p1, edges[i].p2, edges[j].p1, edges[j].p2)) {
            return true;
          }
        }
      }
      return false;
    }

    // Save history state for Undo/Redo
    function saveHistoryState() {
      const state = {
        mode: activeMode,
        circleCenter: { ...circleCenter },
        circleRadius: circleRadius,
        polygonVertices: [ ...polygonVertices ]
      };
      
      undoStack.push(JSON.stringify(state));
      // Cap undo stack to 20 states
      if (undoStack.length > 20) {
        undoStack.shift();
      }
      redoStack = []; // Clear redo stack on new action
    }

    function undo() {
      if (undoStack.length === 0) return;
      
      const currentState = {
        mode: activeMode,
        circleCenter: { ...circleCenter },
        circleRadius: circleRadius,
        polygonVertices: [ ...polygonVertices ]
      };
      redoStack.push(JSON.stringify(currentState));

      const prevState = JSON.parse(undoStack.pop());
      restoreState(prevState);
    }

    function redo() {
      if (redoStack.length === 0) return;

      const currentState = {
        mode: activeMode,
        circleCenter: { ...circleCenter },
        circleRadius: circleRadius,
        polygonVertices: [ ...polygonVertices ]
      };
      undoStack.push(JSON.stringify(currentState));

      const nextState = JSON.parse(redoStack.pop());
      restoreState(nextState);
    }

    function restoreState(state) {
      activeMode = state.mode;
      circleCenter = state.circleCenter;
      circleRadius = state.circleRadius;
      polygonVertices = state.polygonVertices;

      document.getElementById('mode-btn-circle').className = activeMode === 'circle' ? 'mode-btn active' : 'mode-btn';
      document.getElementById('mode-btn-polygon').className = activeMode === 'polygon' ? 'mode-btn active' : 'mode-btn';

      if (activeMode === 'circle') {
        centerMarker.setPosition(circleCenter);
        mapCircle.setCenter(circleCenter);
        mapCircle.setRadius(circleRadius);
        
        centerMarker.setMap(map);
        mapCircle.setMap(map);
        mapPolygon.setMap(null);
      } else {
        centerMarker.setMap(null);
        mapCircle.setMap(null);
        
        isDrawing = (polygonVertices.length === 0);
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
      }
      
      updateUI();
      notifyChanged();
    }

    // Geolocation My Location tool
    function centerMap() {
      if (activeMode === 'circle') {
        map.setCenter(circleCenter);
      } else if (polygonVertices.length > 0) {
        const centroid = calculateCentroid(polygonVertices);
        map.setCenter(centroid);
      }
      map.setZoom(16);
    }

    function fitBoundary() {
      if (activeMode === 'circle') {
        map.fitBounds(mapCircle.getBounds());
      } else if (polygonVertices.length > 0) {
        const bounds = new google.maps.LatLngBounds();
        for (const p of polygonVertices) {
          bounds.extend(new google.maps.LatLng(p.lat, p.lng));
        }
        map.fitBounds(bounds);
      }
    }

    function clearShape() {
      saveHistoryState();
      if (activeMode === 'circle') {
        circleRadius = 100;
        mapCircle.setRadius(circleRadius);
      } else {
        polygonVertices = [];
        isDrawing = true;
        updatePolygonPath([]);
        if (hoverLine) {
          hoverLine.setMap(null);
          hoverLine = null;
        }
      }
      updateUI();
      notifyChanged();
    }

    function resetMap() {
      if (confirm("Are you sure you want to discard your edits and revert to the saved boundary settings?")) {
        window.location.reload();
      }
    }

    function cancelChanges() {
      if (confirm("Discard all unsaved boundary modifications?")) {
        window.location.reload();
      }
    }

    function saveGeofence() {
      document.getElementById('step-4').className = 'step completed';
      document.getElementById('step-5').className = 'step active';

      const data = {
        geofence_type: activeMode,
        name: 'Campus Boundary',
        is_active: true
      };

      if (activeMode === 'circle') {
        data.latitude = circleCenter.lat;
        data.longitude = circleCenter.lng;
        data.radius_meters = circleRadius;
        data.vertices = null;
      } else {
        data.latitude = null;
        data.longitude = null;
        data.radius_meters = null;
        data.vertices = polygonVertices.map(v => ({
          latitude: v.lat,
          longitude: v.lng
        }));
      }

      // Submit changes
      window.parent.postMessage(JSON.stringify({
        type: 'SAVE_GEOFENCE',
        data: data
      }), '*');
    }

    // Notify Flutter parent widget of dirty changes status
    function notifyChanged() {
      const centroid = calculateCentroid(polygonVertices);
      const data = {
        geofence_type: activeMode,
        latitude: activeMode === 'circle' ? circleCenter.lat : centroid.lat,
        longitude: activeMode === 'circle' ? circleCenter.lng : centroid.lng,
        radius_meters: circleRadius,
        vertices: polygonVertices.map(v => ({ latitude: v.lat, longitude: v.lng }))
      };
      window.parent.postMessage(JSON.stringify({
        type: 'GEOFENCE_CHANGED',
        data: data
      }), '*');
    }

    function restoreCurrentGeofence() {
      try {
        const initVerts = ${widget.initialVerticesJson ?? '[]'};
        polygonVertices = initVerts && initVerts.length > 0 ? initVerts.map(v => {
          const latVal = v.latitude !== undefined ? v.latitude : v.lat;
          const lngVal = v.longitude !== undefined ? v.longitude : v.lng;
          return { lat: parseFloat(latVal), lng: parseFloat(lngVal) };
        }).filter(v => !isNaN(v.lat) && !isNaN(v.lng)) : [];
        activeMode = "${widget.initialType}";
        isDrawing = false;
        
        // Reset center and radius
        circleCenter = { lat: ${widget.initialLatitude}, lng: ${widget.initialLongitude} };
        circleRadius = ${widget.initialRadius};
        
        // Clean map elements
        if (mapCircle) mapCircle.setMap(null);
        if (centerMarker) centerMarker.setMap(null);
        if (mapPolygon) mapPolygon.setMap(null);
        
        setupCircleElements();
        setupPolygonElements();
        
        setMode(activeMode, true);
        
        const recoveryBox = document.getElementById('recovery-box');
        if (recoveryBox) recoveryBox.style.display = 'none';
        updateUI();
        notifyChanged();
      } catch (err) {
        console.error("Failed to restore geofence:", err);
      }
    }
  </script>
  <script src="https://maps.googleapis.com/maps/api/js?key=${widget.apiKey}&libraries=places,geometry&callback=initMap&v=weekly" async defer></script>
</body>
</html>
''';
  }
}

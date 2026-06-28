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
  late String _viewId;
  StreamSubscription? _messageSubscription;

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
        print('[GoogleMapEditorWeb] registerViewFactory callback. Generating srcdoc for IFrame.');
        final htmlContent = _buildHtmlTemplate();
        final iframe = html.IFrameElement()
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
            if (widget.onChanged != null) {
              widget.onChanged!();
            }
          }
        }
      } catch (_) {
        // Ignore non-json or unrelated messages
      }
    });
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

  String _buildHtmlTemplate() {
    print('[GoogleMapEditorWeb] _buildHtmlTemplate called. Injecting key: "${widget.apiKey}"');
    final String verticesJsonEscaped = widget.initialVerticesJson != null
        ? widget.initialVerticesJson!.replaceAll('"', '\\"')
        : '[]';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Google Map Editor</title>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background-color: #0f172a;
      color: #f8fafc;
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
      background-color: #111827;
      border-right: 1px solid #334155;
      display: flex;
      flex-direction: column;
      z-index: 10;
      transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      position: absolute;
      left: 0;
      top: 0;
      box-shadow: 10px 0 30px -5px rgba(0, 0, 0, 0.5);
    }
    
    .sidebar.collapsed {
      transform: translateX(-320px);
    }
    
    .sidebar-header {
      padding: 16px;
      border-bottom: 1px solid #334155;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .sidebar-icon {
      font-size: 20px;
    }
    
    .sidebar-title {
      font-size: 16px;
      font-weight: 700;
      color: #f8fafc;
      letter-spacing: 0.5px;
    }
    
    .collapse-btn {
      background: none;
      border: none;
      color: #94a3b8;
      cursor: pointer;
      font-size: 16px;
      padding: 4px;
      border-radius: 4px;
      transition: all 0.2s;
    }
    .collapse-btn:hover {
      background: rgba(255, 255, 255, 0.05);
      color: #f8fafc;
    }

    .expand-btn {
      position: absolute;
      left: 0;
      top: 20px;
      z-index: 20;
      background: #111827;
      border: 1px solid #334155;
      border-left: none;
      color: #94a3b8;
      border-radius: 0 6px 6px 0;
      padding: 12px 8px;
      cursor: pointer;
      box-shadow: 5px 0 15px rgba(0, 0, 0, 0.3);
      transition: all 0.2s;
    }
    .expand-btn:hover {
      color: #f8fafc;
      background: #1e293b;
    }
    
    .sidebar-content {
      flex: 1;
      overflow-y: auto;
      padding: 16px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    
    /* Cards */
    .control-card, .workflow-card, .stats-card {
      background: rgba(30, 41, 59, 0.4);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 10px;
      padding: 14px;
    }
    
    .card-label {
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      color: #64748b;
      margin-bottom: 8px;
      display: block;
    }
    
    /* Guided Workflow */
    .workflow-header {
      font-size: 10px;
      font-weight: 800;
      color: #4f46e5;
      letter-spacing: 1px;
      margin-bottom: 12px;
      text-transform: uppercase;
    }
    
    .steps-container {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    
    .step {
      display: flex;
      align-items: flex-start;
      gap: 10px;
      opacity: 0.4;
      transition: opacity 0.3s;
    }
    
    .step.active {
      opacity: 1;
    }
    
    .step.completed {
      opacity: 0.7;
    }
    
    .step-num {
      width: 18px;
      height: 18px;
      border-radius: 50%;
      background: #334155;
      color: #94a3b8;
      font-size: 10px;
      font-weight: 700;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.3s;
    }
    
    .step.active .step-num {
      background: #4f46e5;
      color: #fff;
      box-shadow: 0 0 8px rgba(79, 70, 229, 0.6);
    }
    
    .step.completed .step-num {
      background: #10b981;
      color: #fff;
    }
    
    .step-title {
      font-size: 12px;
      font-weight: 700;
      color: #cbd5e1;
    }
    .step.active .step-title {
      color: #fff;
    }
    
    .step-desc {
      font-size: 10px;
      color: #64748b;
      margin-top: 1px;
    }
    
    /* Premium Search Box */
    .search-box {
      position: relative;
      display: flex;
      align-items: center;
    }
    
    .search-icon {
      position: absolute;
      left: 10px;
      color: #64748b;
      font-size: 12px;
    }
    
    .search-box input {
      width: 100%;
      padding: 8px 32px 8px 28px;
      background: #0f172a;
      border: 1px solid #334155;
      border-radius: 20px;
      color: #fff;
      font-size: 12px;
      transition: all 0.2s;
    }
    
    .search-box input:focus {
      outline: none;
      border-color: #4f46e5;
      box-shadow: 0 0 0 2px rgba(79, 70, 229, 0.2);
    }
    
    .clear-search-btn {
      position: absolute;
      right: 10px;
      background: none;
      border: none;
      color: #64748b;
      cursor: pointer;
      font-size: 11px;
    }
    .clear-search-btn:hover {
      color: #cbd5e1;
    }
    
    .loading-spinner {
      position: absolute;
      right: 28px;
      width: 12px;
      height: 12px;
      border: 2px solid rgba(255, 255, 255, 0.2);
      border-top-color: #4f46e5;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    
    /* Segmented Mode Selector */
    .mode-selector {
      display: flex;
      background: #0f172a;
      padding: 3px;
      border-radius: 20px;
      border: 1px solid #334155;
    }
    
    .mode-btn {
      flex: 1;
      background: none;
      border: none;
      color: #94a3b8;
      font-size: 12px;
      font-weight: 600;
      padding: 6px 0;
      cursor: pointer;
      border-radius: 17px;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
    }
    
    .mode-btn.active#mode-btn-circle {
      background: #4f46e5;
      color: #fff;
      box-shadow: 0 2px 8px rgba(79, 70, 229, 0.4);
    }
    
    .mode-btn.active#mode-btn-polygon {
      background: #10b981;
      color: #fff;
      box-shadow: 0 2px 8px rgba(16, 185, 129, 0.4);
    }
    
    /* Help Banner */
    .help-tip-banner {
      background: rgba(79, 70, 229, 0.08);
      border: 1px dashed rgba(79, 70, 229, 0.3);
      border-radius: 8px;
      padding: 10px;
      font-size: 11px;
      line-height: 1.4;
      color: #a5b4fc;
    }
    
    /* Statistics Card */
    .stats-header {
      font-size: 10px;
      font-weight: 800;
      color: #10b981;
      letter-spacing: 1px;
      margin-bottom: 12px;
      text-transform: uppercase;
    }
    
    .stats-grid {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    
    .stat-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 12px;
    }
    
    .stat-label {
      color: #94a3b8;
    }
    
    .stat-val {
      font-weight: 600;
      color: #cbd5e1;
    }
    
    .stat-val.highlight {
      color: #60a5fa;
      font-weight: 700;
    }
    
    .badge {
      padding: 2px 6px;
      border-radius: 4px;
      font-size: 10px;
      background: rgba(255, 255, 255, 0.08);
      color: #cbd5e1;
    }
    .badge.success {
      background: rgba(16, 185, 129, 0.15);
      color: #34d399;
      border: 1px solid rgba(16, 185, 129, 0.2);
    }
    
    /* Warnings Banner */
    .alert-banner {
      display: none;
      background: rgba(239, 68, 68, 0.15);
      border: 1px solid rgba(239, 68, 68, 0.3);
      color: #f87171;
      border-radius: 8px;
      padding: 10px;
      font-size: 11px;
      font-weight: 500;
      line-height: 1.4;
    }
    
    /* Sidebar Footer Button Styles */
    .sidebar-footer {
      padding: 16px;
      border-top: 1px solid #334155;
      background: #111827;
      display: flex;
      gap: 8px;
    }
    
    .btn {
      flex: 1;
      padding: 8px 12px;
      border: none;
      border-radius: 6px;
      font-size: 12px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.2s;
      text-align: center;
    }
    
    .btn-secondary {
      background: rgba(51, 65, 85, 0.8);
      color: #e2e8f0;
      border: 1px solid #334155;
    }
    .btn-secondary:hover {
      background: rgba(71, 85, 105, 0.8);
    }
    
    .btn-primary {
      background: #4f46e5;
      color: #fff;
      box-shadow: 0 4px 12px rgba(79, 70, 229, 0.25);
    }
    .btn-primary:hover {
      background: #4338ca;
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
      background: rgba(17, 24, 39, 0.95);
      border: 1px solid #334155;
      border-radius: 8px;
      padding: 4px;
      display: flex;
      align-items: center;
      gap: 2px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
    }
    
    .toolbar-item {
      background: none;
      border: none;
      color: #94a3b8;
      padding: 6px 10px;
      border-radius: 4px;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
      font-weight: 600;
      transition: all 0.2s;
    }
    
    .toolbar-item:hover {
      background: rgba(255, 255, 255, 0.05);
      color: #f8fafc;
    }
    
    .toolbar-item:disabled {
      opacity: 0.3;
      cursor: not-allowed;
    }
    
    .tb-icon {
      font-size: 13px;
    }
    
    .tb-separator {
      width: 1px;
      height: 16px;
      background: #334155;
      margin: 0 4px;
    }
    
    .btn-danger-text {
      color: #f87171;
    }
    .btn-danger-text:hover {
      background: rgba(239, 68, 68, 0.1);
      color: #fca5a5;
    }
    
    /* Onboarding Tutorial Overlay */
    .onboarding-overlay {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(15, 23, 42, 0.7);
      backdrop-filter: blur(4px);
      z-index: 100;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    
    .onboarding-card {
      background: #111827;
      border: 1px solid #334155;
      border-radius: 12px;
      padding: 24px;
      width: 380px;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5), 0 10px 10px -5px rgba(0, 0, 0, 0.5);
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
      color: #fff;
      margin-bottom: 8px;
    }
    
    .onboarding-subtitle {
      font-size: 12px;
      color: #94a3b8;
      line-height: 1.5;
      margin-bottom: 20px;
    }
    
    .onboarding-steps {
      display: flex;
      flex-direction: column;
      gap: 12px;
      text-align: left;
      margin-bottom: 20px;
    }
    
    .obs-item {
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 12px;
      color: #cbd5e1;
    }
    
    .obs-num {
      width: 20px;
      height: 20px;
      background: #4f46e5;
      color: #fff;
      font-weight: 700;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 11px;
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

    // Circle config state
    let centerMarker;
    let mapCircle;
    let circleCenter = { lat: ${widget.initialLatitude}, lng: ${widget.initialLongitude} };
    let circleRadius = ${widget.initialRadius};

    // Polygon config state
    let mapPolygon;
    let polygonVertices = [];

    // History state stacks for Undo/Redo
    let undoStack = [];
    let redoStack = [];

    // Parse initial coordinates
    try {
      const initVerts = JSON.parse("${verticesJsonEscaped}");
      if (initVerts && initVerts.length > 0) {
        polygonVertices = initVerts.map(v => ({ lat: v.latitude, lng: v.longitude }));
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
        styles: [
          { elementType: "geometry", stylers: [{ color: "#1e293b" }] },
          { elementType: "labels.text.stroke", stylers: [{ color: "#0f172a" }] },
          { elementType: "labels.text.fill", stylers: [{ color: "#94a3b8" }] },
          { featureType: "administrative", elementType: "geometry", stylers: [{ color: "#334155" }] },
          { featureType: "poi", elementType: "labels.text.fill", stylers: [{ color: "#64748b" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#334155" }] },
          { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#1e293b" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#0f172a" }] }
        ]
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

      // Double click to close polygon path
      map.addListener('dblclick', function(e) {
        if (activeMode === 'polygon' && isDrawing) {
          isDrawing = false;
          if (hoverLine) {
            hoverLine.setMap(null);
            hoverLine = null;
          }
          
          if (polygonVertices.length >= 3) {
            mapPolygon.setPath(polygonVertices);
            mapPolygon.setMap(map);
          }
          updateUI();
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
        updateUI();
        notifyChanged();
      });

      mapCircle.addListener('center_changed', () => {
        circleCenter = mapCircle.getCenter().toJSON();
        centerMarker.setPosition(circleCenter);
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
      mapPolygon = new google.maps.Polygon({
        paths: polygonVertices,
        map: null,
        editable: true,
        draggable: true,
        fillColor: '#10b981',
        fillOpacity: 0.12,
        strokeColor: '#10b981',
        strokeWeight: 2
      });

      // Edit handlers
      const path = mapPolygon.getPath();
      const onPathChanged = () => {
        saveHistoryState();
        polygonVertices = [];
        for (let i = 0; i < path.getLength(); i++) {
          polygonVertices.push(path.getAt(i).toJSON());
        }
        updateUI();
        notifyChanged();
      };

      path.addListener('insert_at', onPathChanged);
      path.addListener('remove_at', onPathChanged);
      path.addListener('set_at', onPathChanged);
      
      mapPolygon.addListener('dragend', () => {
        onPathChanged();
      });

      // Right-click polygon vertex to delete
      mapPolygon.addListener('rightclick', function(mev) {
        if (mev.vertex !== undefined) {
          saveHistoryState();
          mapPolygon.getPath().removeAt(mev.vertex);
        }
      });
    }

    function drawActivePolygon() {
      if (polygonVertices.length < 3) {
        // Render polyline
        if (mapPolygon) mapPolygon.setMap(null);
        mapPolygon.setPath(polygonVertices);
        mapPolygon.setMap(map);
      } else {
        mapPolygon.setPath(polygonVertices);
        mapPolygon.setMap(map);
      }
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
      } else {
        // Place default polygon bounds around searched coordinate
        const offset = 0.002;
        const newC = loc.toJSON();
        polygonVertices = [
          { lat: newC.lat - offset, lng: newC.lng - offset },
          { lat: newC.lat + offset, lng: newC.lng - offset },
          { lat: newC.lat + offset, lng: newC.lng + offset },
          { lat: newC.lat - offset, lng: newC.lng + offset }
        ];
        isDrawing = false;
        mapPolygon.setPath(polygonVertices);
        mapPolygon.setMap(map);
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
          isDrawing = true;
        } else {
          isDrawing = false;
          mapPolygon.setPath(polygonVertices);
          mapPolygon.setMap(map);
        }
      }

      updateUI();
      
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

          // Validations
          if (isSelfIntersecting(polygonVertices)) {
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
        mapPolygon.setPath(polygonVertices);
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
        mapPolygon.setPath([]);
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
      window.parent.postMessage(JSON.stringify({
        type: 'GEOFENCE_CHANGED',
        data: { isDirty: true }
      }), '*');
    }
  </script>
  <script src="https://maps.googleapis.com/maps/api/js?key=${widget.apiKey}&libraries=places,geometry&callback=initMap&v=weekly" async defer></script>
</body>
</html>
''';
  }
}

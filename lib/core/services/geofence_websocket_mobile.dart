import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../app_config.dart';
import 'location_service.dart';

class GeofenceWebSocketClient {
  static WebSocket? _socket;
  static bool _shouldReconnect = true;
  static Timer? _reconnectTimer;

  static void connect() async {
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    final String wsUrl = kApiBaseUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://') + '/geofence/ws';
    
    try {
      debugPrint('[WS] Connecting to $wsUrl...');
      _socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      debugPrint('[WS] Connected successfully.');
      
      _socket!.listen(
        (message) {
          debugPrint('[WS] Received message: $message');
          if (message == 'GEOFENCE_UPDATED') {
            debugPrint('[WS] Geofence updated on server. Syncing...');
            LocationService.syncWithServer();
          }
        },
        onDone: () {
          debugPrint('[WS] Connection closed.');
          if (_shouldReconnect) {
            _scheduleReconnect();
          }
        },
        onError: (e) {
          debugPrint('[WS] Error: $e');
          if (_shouldReconnect) {
            _scheduleReconnect();
          }
        },
      );
    } catch (e) {
      debugPrint('[WS] Failed to connect: $e');
      if (_shouldReconnect) {
        _scheduleReconnect();
      }
    }
  }

  static void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect();
    });
  }

  static void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    debugPrint('[WS] Disconnected.');
  }
}

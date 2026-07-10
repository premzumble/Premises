import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../app_config.dart';
import 'location_service.dart';

class GeofenceWebSocketClient {
  static html.WebSocket? _socket;
  static bool _shouldReconnect = true;
  static Timer? _reconnectTimer;

  static void connect() async {
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    final String wsUrl = kApiBaseUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://') + '/geofence/ws';
    
    try {
      debugPrint('[WS Web] Connecting to $wsUrl...');
      _socket = html.WebSocket(wsUrl);
      
      _socket!.onOpen.listen((event) {
        debugPrint('[WS Web] Connected successfully.');
      });
      
      _socket!.onMessage.listen((event) {
        final message = event.data.toString();
        debugPrint('[WS Web] Received message: $message');
        if (message == 'GEOFENCE_UPDATED') {
          debugPrint('[WS Web] Geofence updated on server. Syncing...');
          LocationService.syncWithServer();
        }
      });
      
      _socket!.onClose.listen((event) {
        debugPrint('[WS Web] Connection closed.');
        if (_shouldReconnect) {
          _scheduleReconnect();
        }
      });
      
      _socket!.onError.listen((event) {
        debugPrint('[WS Web] Error occurred.');
        if (_shouldReconnect) {
          _scheduleReconnect();
        }
      });
    } catch (e) {
      debugPrint('[WS Web] Failed to connect: $e');
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
    debugPrint('[WS Web] Disconnected.');
  }
}

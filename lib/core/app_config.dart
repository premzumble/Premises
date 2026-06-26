/// ---------------------------------------------------------------------------
/// App Configuration — Change this file to switch between environments
/// ---------------------------------------------------------------------------
///
/// For LOCAL DEVICE TESTING (physical phone on same Wi-Fi as your PC):
///   Set [backendHost] to your PC's local IP address (e.g. '10.191.94.95').
///   Find it by running: ipconfig  (Windows) or ifconfig (Mac/Linux)
///
/// For WEB / EMULATOR (running on the same machine as the backend):
///   Set [backendHost] to '127.0.0.1'  or  'localhost'
///
/// ---------------------------------------------------------------------------
/// ---------------------------------------------------------------------------
/// App Configuration
/// ---------------------------------------------------------------------------

library app_config;

/// Base API URL
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.68.152:8000/api/v1',
);

/// Backend URL (without /api/v1)
String get kBaseUrl => kApiBaseUrl.replaceFirst('/api/v1', '');

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
library app_config;

/// The IP/hostname of the backend server.
/// Change this to your PC's local IP when testing on a physical device.
const String backendHost = '192.168.68.152';

/// The port the backend FastAPI server listens on.
const int backendPort = 8000;

/// Full base URL — used by all services.
const String kBaseUrl = 'http://$backendHost:$backendPort';

/// Full base API URL — used by ApiService.
const String kApiBaseUrl = '$kBaseUrl/api/v1';

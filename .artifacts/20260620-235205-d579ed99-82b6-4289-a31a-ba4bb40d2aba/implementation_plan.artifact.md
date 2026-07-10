# Implementation Plan - Core Attendance Restoration & Stability

Restore the critical geofence monitoring and attendance workflow while preserving production improvements.

## User Review Required

> [!IMPORTANT]
> - I am separating the **Synchronization State** (Internet) from the **Attendance Monitoring State** (GPS/Geofence) in the UI to provide accurate feedback.
> - `LocationService` will now wait for geofence configuration to arrive from the server instead of defaulting to an "Outside Premises" state.

## Proposed Changes

### Core & Infrastructure

#### [sync_service.dart](file:///E:/Premises/premises/lib/core/services/sync_service.dart)
- Add `_initialized` guard to prevent double stream listeners.
- Only trigger auto-sync if genuinely online.

#### [location_service.dart](file:///E:/Premises/premises/lib/core/services/location_service.dart)
- **State Resilience**: Initialize `isInsideGeofence` as `null`.
- **Logic Fix**: In `_handlePositionUpdate`, if geofence data is missing, set `statusMessage` to "Waiting for organization geofence configuration..." instead of bailing silently.
- **Auto-Recovery**: Add `forceReevaluate()` to be called whenever geofence cache is updated.
- **Redundancy Cleanup**: Remove the redundant 30s background sync timer (already handled by Dashboard and SyncService).

### Backend - Attendance History

#### [faculty_service.py](file:///E:/Premises/premises/backend/app/services/faculty_service.py)
- Audit `list_attendance_history` for multi-tenant isolation logic. Ensure `faculty_id` and `organization_id` lookup is robust.

### UI & Dashboard

#### [faculty_dashboard_screen.dart](file:///E:/Premises/premises/lib/features/faculty/screens/faculty_dashboard_screen.dart)
- **UI Separation**:
    - The **Sync Status Bar** now strictly shows internet/sync status.
    - The **Location Banner** now shows GPS and Geofence specific states.
- **Detailed States**: Display "GPS Accuracy: OK", "Geofence Monitoring: Active" when conditions are met.
- **Refresh Flow**: Ensure `LocationService.forceReevaluate()` is called after `_loadDashboard` finishes caching geofence data.

### Branding Consistency

#### [AndroidManifest.xml](file:///E:/Premises/premises/android/app/src/main/AndroidManifest.xml)
- Double-check every occurrence of "premises" vs "Premises".

---

## Verification Plan

### Manual Verification (Physical Device Simulation)
1. **Startup flow**:
   - Cold start -> Splash -> Login -> Dashboard.
   - Verify banner says "Initializing real-time tracking..." then "Waiting for geofence config..." then "Inside/Outside Campus" in sequence.
2. **Geofence Detection**:
   - Manually update Geofence in Admin.
   - Verify Faculty Dashboard updates the "Outside/Inside" status instantly (within 10s refresh or via manual re-evaluation).
3. **History Load**:
   - Open Attendance History.
   - Verify records are retrieved correctly.
4. **Offline Resilience**:
   - Disconnect internet.
   - Verify Sync Bar says "Working Offline" but Location Banner still says "Inside Campus" (GPS works without data).

### Automated Tests
- `pytest backend/tests/test_main.py`: Verify existing endpoints.
- `flutter analyze`: Ensure zero errors.

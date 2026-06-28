# Implementation Plan - Walkthrough Bug Fixes

Fix critical usability bugs in the Admin Walkthrough and Dashboard notification systems.

## User Review Required

> [!NOTE]
> I am introducing a new persistent flag `admin_org_code_banner_seen` to ensure the post-registration reminder only appears once.

## Proposed Changes

### Core

#### [session_manager.dart](file:///E:/Premises/premises/lib/core/session_manager.dart)
- Remove the in-memory `_bannerDismissed` static flag.
- Add `Future<bool> shouldShowOrgCodeBanner()` and `Future<void> setOrgCodeBannerSeen()`.
- Add `Future<void> triggerOrgCodeBanner()` (called from registration).

### Auth

#### [register_screen.dart](file:///E:/Premises/premises/lib/features/auth/screens/register_screen.dart)
- Call `SessionManager.triggerOrgCodeBanner()` upon successful organization registration.

### Admin Walkthrough

#### [walkthrough_service.dart](file:///E:/Premises/premises/lib/features/admin/walkthrough/services/walkthrough_service.dart)
- No changes needed here, logic is already persistent.

#### [walkthrough_controller.dart](file:///E:/Premises/premises/lib/features/admin/walkthrough/controller/walkthrough_controller.dart)
- Update `startTour()` to accept a `bool isAlreadyOnDashboard` parameter.
- If `isAlreadyOnDashboard` is true, immediately call `onDashboardReady()` logic to avoid showing the "Navigate to Dashboard" hint.

#### [admin_navigation.dart](file:///E:/Premises/premises/lib/features/admin/layouts/admin_navigation.dart)
- Update `_checkWalkthroughStatus()` to only show the Welcome dialog if the tour is NOT completed AND it's the first login.
- Pass the current route status to `startTour()`.

### Admin Dashboard

#### [dashboard_screen.dart](file:///E:/Premises/premises/lib/features/admin/screens/dashboard_screen.dart)
- Replace in-memory `SessionManager.bannerDismissed` check with a call to `SessionManager.shouldShowOrgCodeBanner()`.
- Ensure the banner is dismissed persistently.

---

## Verification Plan

### Manual Verification
1.  **Bug 1 (Welcome Dialog)**:
    - Login as Admin.
    - Dismiss the Welcome dialog (Start or Skip).
    - Logout and Login again.
    - Verify the dialog does NOT appear.
    - Click Help button -> Replay Tour. Verify the dialog APPEARS.

2.  **Bug 2 (Instant Start)**:
    - Login as Admin (First time).
    - In Welcome dialog, click **Start Tour**.
    - Verify Phase 1 (Dashboard showcase) starts immediately without showing the "Navigate to Dashboard" hint.

3.  **Bug 3 (Org Code Banner)**:
    - Register a new Organization.
    - Login.
    - Verify the Org Code reminder banner appears.
    - Dismiss the banner.
    - Logout and Login again.
    - Verify the banner does NOT appear.
    - Verify normal logins (for existing orgs) NEVER show the banner.

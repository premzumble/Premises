# Implementation Plan - Forgot Password & Email OTP (Updated)

Complete implementation of the Forgot Password workflow and a professional Email Service with SMTP integration.

## User Review Required

> [!IMPORTANT]
> - The existing `OtpVerification` model will be modified to include security tracking: `purpose`, `expires_at`, `verified`, `attempt_count`, and `used_at`.
> - Gmail SMTP requires an **App Password** to be set in `.env`.

## Proposed Changes

### Backend - Core & Infrastructure

#### [config.py](file:///E:/Premises/premises/backend/app/core/config.py)
- Add SMTP configuration settings: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`, `SMTP_FROM_NAME`.

#### [NEW] [email_service.py](file:///E:/Premises/premises/backend/app/services/email_service.py)
- Reusable service to send HTML emails using Jinja2 templates.
- Support for `REGISTRATION` and `PASSWORD_RESET` templates.
- Production-ready SMTP connection handling.

---

### Backend - Database & Models

#### [otp.py](file:///E:/Premises/premises/backend/app/models/otp.py)
- Add `purpose` (String) to distinguish between registration and reset.
- Add `expires_at` (DateTime) for fine-grained expiration control (5 minutes).
- Add `verified` (Boolean) and `used_at` (DateTime) to prevent reuse.
- Add `attempt_count` (Integer) to limit verification spam.

#### [Alembic Migration]
- Generate a new migration to update `otp_verifications` table.

---

### Backend - Business Logic & API

#### [auth_service.py](file:///E:/Premises/premises/backend/app/services/auth_service.py)
- Implement rate limiting (3 requests/10 mins per email).
- Implement `initiate_password_reset(email)`: Validates user, generates OTP, sends email.
- Implement `verify_reset_otp(email, otp)`: Validates OTP, purpose, and attempt count.
- Implement `reset_password(email, otp, new_password)`: Verifies OTP again (safety) and updates hash with strong validation.
- Enforce strong password policy: 8+ chars, upper, lower, digit, special.

#### [auth.py](file:///E:/Premises/premises/backend/app/api/auth.py)
- Add endpoints:
    - `POST /auth/forgot-password`
    - `POST /auth/verify-reset-otp`
    - `POST /auth/reset-password`

#### [NEW] [health.py](file:///E:/Premises/premises/backend/app/api/health.py)
- Add endpoint: `GET /health/email` to verify SMTP connectivity.

---

### Flutter - UI & Auth

#### [api_service.dart](file:///E:/Premises/premises/lib/core/api_service.dart)
- Add client methods for forgot password flow.

#### Screens
- [NEW] `forgot_password_screen.dart`
- [NEW] `verify_reset_otp_screen.dart`
- [NEW] `reset_password_screen.dart`
- [NEW] `reset_success_screen.dart`

---

## Verification Plan

### Automated Tests
- `pytest` for OTP expiry, rate limiting, and password strength.
- `flutter analyze` for frontend.

### Manual Verification
1. **Email Health**: Check `GET /health/email` returns success.
2. **Rate Limiting**: Request OTP 4 times within 10 mins; verify the 4th is rejected.
3. **Template**: Verify HTML email looks professional in inbox.
4. **Security**: Try verified OTP again; verify it fails (single-use).
5. **Strength**: Try resetting with "123456"; verify it fails validation.

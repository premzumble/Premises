from typing import Any, Optional
from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.dependencies import get_current_user, get_db
from app.core.exceptions import AuthException
from app.core.security import create_access_token, decode_token
from app.core.limiter import limiter
from app.models.log import AuditLog
from app.models.user import Admin

from app.schemas.auth import (
    AdminRegisterRequest,
    FacultyRegisterRequest,
    LoginRequest,
    PublicOrgDetailsResponse,
    RefreshTokenRequest,
    TokenResponse,
    UserInfo,
    VerifyOtpRequest,
    VerifyOtpResponse,
    ForgotPasswordRequest,
    ResetPasswordRequest,
)
from app.schemas.base import StandardResponse
from app.services.auth_service import AuthService

router = APIRouter()


# ----------------------------------------------------------------------
# POST /auth/register-admin
# Step 1: Admin initiates registration — OTP is sent (printed in dev)
# ----------------------------------------------------------------------
@router.post("/register-admin", response_model=StandardResponse[dict])
async def register_admin(data: AdminRegisterRequest, db: AsyncSession = Depends(get_db)):
    auth_service = AuthService(db)
    await auth_service.initiate_admin_registration(data)
    return StandardResponse(
        success=True,
        message=f"OTP sent to {data.email}. Please verify to complete registration.",
        data={"email": data.email},
    )


# ----------------------------------------------------------------------
# POST /auth/verify-otp
# Step 2: Admin verifies OTP — Organization + Admin account is created
# ----------------------------------------------------------------------
@router.post("/verify-otp", response_model=StandardResponse[VerifyOtpResponse])
@limiter.limit("5/minute")
async def verify_otp(request: Request, data: VerifyOtpRequest, db: AsyncSession = Depends(get_db)):

    auth_service = AuthService(db)
    result = await auth_service.verify_admin_otp(data.email, data.otp)
    return StandardResponse(
        success=True,
        message=result.message,
        data=result,
    )


# ----------------------------------------------------------------------
# GET /auth/org-details?code=ORGCODE
# Public: Fetch org info + departments by organization code (for faculty registration)
# ----------------------------------------------------------------------
@router.get("/org-details", response_model=StandardResponse[PublicOrgDetailsResponse])
async def get_org_details(code: str, db: AsyncSession = Depends(get_db)):
    auth_service = AuthService(db)
    result = await auth_service.get_public_org_details(code)
    return StandardResponse(
        success=True,
        message="Organization details fetched.",
        data=result,
    )


# ----------------------------------------------------------------------
# GET /auth/org-lookup
# Public: Lookup organization by email domain or code (for faculty registration)
# ----------------------------------------------------------------------
@router.get("/org-lookup", response_model=StandardResponse[PublicOrgDetailsResponse])
async def org_lookup(
    email: Optional[str] = None,
    code: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    auth_service = AuthService(db)
    result = await auth_service.lookup_organization(email=email, code=code)
    return StandardResponse(
        success=True,
        message="Organization lookup completed.",
        data=result,
    )


# ----------------------------------------------------------------------
# POST /auth/register
# Faculty Registration: Submit pending request
# ----------------------------------------------------------------------
@router.post("/register", response_model=StandardResponse[UserInfo])
async def register(data: FacultyRegisterRequest, db: AsyncSession = Depends(get_db)):
    auth_service = AuthService(db)
    faculty = await auth_service.register_faculty(data)

    user_info = UserInfo(
        id=faculty.id,
        email=faculty.email,
        full_name=faculty.full_name,
        organization_id=faculty.organization_id,
    )
    return StandardResponse(
        success=True,
        message="Registration submitted successfully. Pending administrator approval.",
        data=user_info,
    )


# ----------------------------------------------------------------------
# POST /auth/login
# Unified login (auto-detects admin vs faculty if role not specified)
# ----------------------------------------------------------------------
@router.post("/login", response_model=StandardResponse[TokenResponse])
@limiter.limit("5/minute")
async def login(request: Request, data: LoginRequest, db: AsyncSession = Depends(get_db)):

    auth_service = AuthService(db)
    access_token, refresh_token, role, user = await auth_service.login(data)

    user_info = UserInfo(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        organization_id=user.organization_id,
    )
    token_response = TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=role,
        user=user_info,
    )
    return StandardResponse(
        success=True,
        message="Login successful.",
        data=token_response,
    )


# ----------------------------------------------------------------------
# POST /auth/refresh
# Refresh access token
# ----------------------------------------------------------------------
@router.post("/refresh", response_model=StandardResponse[dict])
async def refresh_token(data: RefreshTokenRequest):
    try:
        payload = decode_token(data.refresh_token)
        if payload.get("type") != "refresh":
            raise AuthException("Invalid token type. Refresh token required.")

        user_id = payload.get("sub")
        role = payload.get("role")
        org_id = payload.get("org_id")

        new_access_token = create_access_token(user_id, role, org_id)
        return StandardResponse(
            success=True,
            message="Token refreshed successfully.",
            data={"access_token": new_access_token, "token_type": "bearer"},
        )
    except Exception as e:
        raise AuthException(f"Could not refresh access token: {e}")


# ----------------------------------------------------------------------
# GET /auth/me
# Get current authenticated user profile
# ----------------------------------------------------------------------
@router.get("/me", response_model=StandardResponse[UserInfo])
async def get_me(current_user: Any = Depends(get_current_user)):
    user_info = UserInfo(
        id=current_user.id,
        email=current_user.email,
        full_name=current_user.full_name,
        organization_id=current_user.organization_id,
    )
    return StandardResponse(
        success=True,
        message="Profile fetched successfully.",
        data=user_info,
    )


# ----------------------------------------------------------------------
# POST /auth/logout
# ----------------------------------------------------------------------
@router.post("/logout", response_model=StandardResponse[dict])
async def logout(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    actor_type = "ADMIN" if isinstance(current_user, Admin) else "FACULTY"
    
    # Audit log: logout
    logout_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type=actor_type,
        actor_id=current_user.id,
        action="USER_LOGOUT",
        entity_type="USER",
        entity_id=current_user.id,
        new_value={"email": current_user.email},
    )
    db.add(logout_log)
    await db.commit()
    
    return StandardResponse(
        success=True,
        message="Logout successful.",
        data={},
    )


# ----------------------------------------------------------------------
# FORGOT PASSWORD FLOW
# ----------------------------------------------------------------------

@router.post("/forgot-password", response_model=StandardResponse[dict])
@limiter.limit("3/10minutes")
async def forgot_password(request: Request, data: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)):
    auth_service = AuthService(db)
    result = await auth_service.initiate_password_reset(data)
    return StandardResponse(
        success=True,
        message=result["message"],
        data={},
    )


@router.post("/verify-reset-otp", response_model=StandardResponse[dict])
async def verify_reset_otp(data: VerifyOtpRequest, db: AsyncSession = Depends(get_db)):
    auth_service = AuthService(db)
    result = await auth_service.verify_reset_otp(data.email, data.otp)
    return StandardResponse(
        success=True,
        message=result["message"],
        data={},
    )


@router.post("/reset-password", response_model=StandardResponse[dict])
async def reset_password(data: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    auth_service = AuthService(db)
    result = await auth_service.reset_password(data)
    return StandardResponse(
        success=True,
        message=result["message"],
        data={},
    )


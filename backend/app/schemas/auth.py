from typing import Optional
import uuid
from pydantic import BaseModel, EmailStr, Field
from app.core.constants import DevicePlatform, UserRole


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    role: Optional[UserRole] = None
    device_identifier: Optional[str] = None
    device_model: Optional[str] = None
    platform: Optional[str] = None
    os_version: Optional[str] = None
    manufacturer: Optional[str] = None
    otp: Optional[str] = None
    device_swap_reason: Optional[str] = None



class UserInfo(BaseModel):
    id: uuid.UUID
    email: EmailStr
    full_name: str
    organization_id: uuid.UUID
    walkthrough_completed: Optional[bool] = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: UserRole
    user: UserInfo


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class FacultyRegisterRequest(BaseModel):
    full_name: str = Field(..., min_length=2)
    email: EmailStr
    password: str = Field(..., min_length=6)
    organization_code: Optional[str] = None
    department_id: Optional[uuid.UUID] = None
    device_identifier: Optional[str] = None
    device_model: Optional[str] = None
    platform: Optional[DevicePlatform] = None


class AdminRegisterRequest(BaseModel):
    org_name: str = Field(..., min_length=2)
    org_type: str = Field(..., min_length=2)
    admin_name: str = Field(..., min_length=2)
    email: EmailStr
    password: str = Field(..., min_length=6)


class VerifyOtpRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6)


class VerifyOtpResponse(BaseModel):
    organization_id: uuid.UUID
    organization_code: str
    name: str
    message: str


class PublicDepartmentResponse(BaseModel):
    id: uuid.UUID
    name: str


class PublicOrgDetailsResponse(BaseModel):
    organization_id: uuid.UUID
    organization_name: str
    organization_code: str
    departments: list[PublicDepartmentResponse]


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=8)


from datetime import datetime
from typing import Optional
import uuid
from pydantic import BaseModel


class OrganizationBase(BaseModel):
    name: str
    organization_code: str
    type: str
    domain: Optional[str] = None
    logo_url: Optional[str] = None
    website: Optional[str] = None
    address: Optional[str] = None
    contact_number: Optional[str] = None


class OrganizationResponse(OrganizationBase):
    id: uuid.UUID
    status: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class OrganizationSettingsResponse(BaseModel):
    id: uuid.UUID
    organization_id: uuid.UUID
    faculty_registration_mode: str
    allow_external_emails: bool
    require_mfa: bool
    restrict_devices: bool
    log_admin_actions: bool
    notify_on_device_change: bool
    notify_on_exit_violation: bool
    notify_on_approvals: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class OrganizationSettingsUpdate(BaseModel):
    faculty_registration_mode: Optional[str] = None
    allow_external_emails: Optional[bool] = None
    require_mfa: Optional[bool] = None
    restrict_devices: Optional[bool] = None
    log_admin_actions: Optional[bool] = None
    notify_on_device_change: Optional[bool] = None
    notify_on_exit_violation: Optional[bool] = None
    notify_on_approvals: Optional[bool] = None


class OrganizationUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    domain: Optional[str] = None
    logo_url: Optional[str] = None
    website: Optional[str] = None
    address: Optional[str] = None
    contact_number: Optional[str] = None


class DepartmentBase(BaseModel):
    name: str
    description: Optional[str] = None
    is_active: bool = True


class DepartmentCreate(DepartmentBase):
    pass


class DepartmentResponse(DepartmentBase):
    id: uuid.UUID
    organization_id: uuid.UUID
    created_at: datetime

    class Config:
        from_attributes = True

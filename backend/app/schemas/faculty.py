import uuid
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field

class ProfileUpdate(BaseModel):
    phone_number: Optional[str] = Field(None, max_length=30)
    emergency_contact: Optional[str] = Field(None, max_length=255)
    profile_photo_url: Optional[str] = None
    current_password: Optional[str] = None
    new_password: Optional[str] = Field(None, min_length=6)

class ProfileResponse(BaseModel):
    id: uuid.UUID
    full_name: str
    email: str
    phone_number: Optional[str] = None
    emergency_contact: Optional[str] = None
    profile_photo_url: Optional[str] = None
    organization_name: str
    department_name: Optional[str] = None
    registered_device: Optional[str] = None

from app.schemas.geofence import GeofenceVertexResponse

class DashboardSummaryResponse(BaseModel):
    attendance_status: str  # PRESENT, OUTSIDE, ABSENT, NOT_STARTED
    check_in_time: Optional[str] = None
    check_out_time: Optional[str] = None
    working_duration: str  # e.g. "05h 30m"
    campus_status: str  # INSIDE, OUTSIDE
    geofence_latitude: float
    geofence_longitude: float
    geofence_radius: float
    geofence_type: str = "circle"
    geofence_vertices: Optional[List[GeofenceVertexResponse]] = None
    geofence_id: Optional[uuid.UUID] = None
    geofence_updated_at: Optional[datetime] = None
    allowed_outside_minutes: int = 25
    reminder_1_minutes: int = 0
    reminder_2_minutes: int = 0
    reminder_3_minutes: int = 0
    evaluation_minutes: int = 15
    reason_required: bool = False
    reason_status: Optional[str] = None  # PENDING, APPROVED, REJECTED
    warning_message: Optional[str] = None
    policy_start_time: Optional[str] = None
    policy_end_time: Optional[str] = None
    policy_source: Optional[str] = None
    department_name: Optional[str] = None

class ReasonRequestCreate(BaseModel):
    reason_type: str
    notes: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None

class NotificationResponse(BaseModel):
    id: uuid.UUID
    type: str
    title: str
    message: str
    sent_at: datetime
    read_at: Optional[datetime] = None
    acknowledged_at: Optional[datetime] = None

class DeviceHistoryResponse(BaseModel):
    id: uuid.UUID
    device_identifier: str
    device_model: Optional[str] = None
    platform: str
    os_version: Optional[str] = None
    manufacturer: Optional[str] = None
    registered_at: datetime
    is_active: bool

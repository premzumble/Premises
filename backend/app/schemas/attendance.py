from datetime import date, datetime
from typing import List, Optional
import uuid
from pydantic import BaseModel
from app.core.constants import AttendanceStatus, LocationEventType


class LocationEventCreate(BaseModel):
    event_type: LocationEventType
    latitude: float
    longitude: float
    event_time: datetime
    device_identifier: str


class LocationEventResponse(BaseModel):
    id: uuid.UUID
    event_type: LocationEventType
    latitude: float
    longitude: float
    event_time: datetime

    class Config:
        from_attributes = True


class AttendanceRecordResponse(BaseModel):
    id: uuid.UUID
    faculty_id: uuid.UUID
    attendance_date: date
    first_entry_time: Optional[datetime] = None
    last_exit_time: Optional[datetime] = None
    status: AttendanceStatus
    total_inside_minutes: int
    total_outside_minutes: int

    is_overridden: bool = False
    override_status: Optional[str] = None
    override_reason: Optional[str] = None
    override_remarks: Optional[str] = None
    override_by: Optional[uuid.UUID] = None
    override_at: Optional[datetime] = None
    manual_check_in_time: Optional[datetime] = None
    manual_check_out_time: Optional[datetime] = None
    effective_working_hours: Optional[float] = None

    class Config:
        from_attributes = True


class RecentActivityItem(BaseModel):
    name: str
    type: str
    time: datetime


class AttendanceSummary(BaseModel):
    present_count: int
    half_day_count: int
    absent_count: int
    outside_count: int
    pending_requests_count: int
    total_faculty: int
    org_name: str
    org_code: str
    admin_email: str
    org_created_at: datetime
    org_status: str
    today_manual_overrides_count: int = 0
    recent_activities: List[RecentActivityItem] = []


class AttendanceOverrideCreate(BaseModel):
    faculty_id: uuid.UUID
    attendance_date: date
    override_status: str
    override_reason: str
    override_remarks: str
    manual_check_in_time: Optional[datetime] = None
    manual_check_out_time: Optional[datetime] = None
    effective_working_hours: Optional[float] = None
    force_replace: bool = False

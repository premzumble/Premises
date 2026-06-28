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
    recent_activities: List[RecentActivityItem] = []

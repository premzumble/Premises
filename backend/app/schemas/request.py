from datetime import datetime
from typing import Optional
import uuid
from pydantic import BaseModel
from app.core.constants import RequestStatus


class ReasonRequestCreate(BaseModel):
    attendance_record_id: uuid.UUID
    reason_type: str
    notes: Optional[str] = None
    submitted_latitude: Optional[float] = None
    submitted_longitude: Optional[float] = None


class ReasonRequestResponse(BaseModel):
    id: uuid.UUID
    faculty_id: uuid.UUID
    attendance_record_id: Optional[uuid.UUID] = None
    reason_type: str
    notes: Optional[str] = None
    status: RequestStatus
    submitted_at: datetime
    reviewed_by: Optional[uuid.UUID] = None
    reviewed_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class RequestReview(BaseModel):
    status: RequestStatus  # APPROVED or REJECTED


class DeviceChangeRequestCreate(BaseModel):
    new_device_identifier: str
    new_device_model: str


class DeviceChangeRequestResponse(BaseModel):
    id: uuid.UUID
    faculty_id: uuid.UUID
    old_device_id: Optional[uuid.UUID] = None
    new_device_identifier: str
    new_device_model: str
    status: RequestStatus
    created_at: datetime
    reviewed_by: Optional[uuid.UUID] = None
    reviewed_at: Optional[datetime] = None

    class Config:
        from_attributes = True

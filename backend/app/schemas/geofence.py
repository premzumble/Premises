from datetime import datetime, time
from typing import Optional
import uuid
from pydantic import BaseModel, Field


class GeofenceBase(BaseModel):
    name: str
    latitude: float
    longitude: float
    radius_meters: float = Field(..., gt=0)
    is_active: bool = True


class GeofenceCreate(GeofenceBase):
    pass


class GeofenceResponse(GeofenceBase):
    id: uuid.UUID
    organization_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    updated_by: Optional[str] = None

    class Config:
        from_attributes = True


class AttendancePolicyBase(BaseModel):
    allowed_outside_minutes: int = Field(0, ge=0)
    reminder_1_minutes: int = Field(0, ge=0)
    reminder_2_minutes: int = Field(0, ge=0)
    reminder_3_minutes: int = Field(0, ge=0)
    evaluation_minutes: int = Field(15, gt=0)
    start_time: time
    end_time: time
    half_day_cutoff_time: time
    absent_cutoff_time: time


class AttendancePolicyResponse(AttendancePolicyBase):
    id: uuid.UUID
    organization_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class AttendancePolicyUpdate(BaseModel):
    allowed_outside_minutes: Optional[int] = None
    reminder_1_minutes: Optional[int] = None
    reminder_2_minutes: Optional[int] = None
    reminder_3_minutes: Optional[int] = None
    evaluation_minutes: Optional[int] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    half_day_cutoff_time: Optional[time] = None
    absent_cutoff_time: Optional[time] = None

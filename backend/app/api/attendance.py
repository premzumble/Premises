from typing import Any, List
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.dependencies import get_current_user, require_role, get_db
from app.core.constants import UserRole
from app.schemas.base import StandardResponse
from app.schemas.attendance import LocationEventCreate, LocationEventResponse, AttendanceRecordResponse
from app.services.attendance_service import AttendanceService
from app.models.attendance import AttendanceRecord

router = APIRouter()


@router.post("/check-in", response_model=StandardResponse[LocationEventResponse])
async def check_in(
    data: LocationEventCreate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = AttendanceService(db)
    event = await service.register_location_event(current_user.id, current_user.organization_id, data)
    
    event_response = LocationEventResponse(
        id=event.id,
        event_type=event.event_type,
        latitude=event.latitude,
        longitude=event.longitude,
        event_time=event.event_time,
    )
    return StandardResponse(
        success=True,
        message="Location event check logged successfully.",
        data=event_response,
    )


@router.get("/records", response_model=StandardResponse[List[AttendanceRecordResponse]])
async def list_records(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    stmt = select(AttendanceRecord).where(AttendanceRecord.organization_id == current_user.organization_id)
    res = await db.execute(stmt)
    records = res.scalars().all()
    
    record_responses = [AttendanceRecordResponse.model_validate(r) for r in records]
    return StandardResponse(
        success=True,
        message="Organization attendance records loaded.",
        data=record_responses,
    )


@router.get("/records/me", response_model=StandardResponse[List[AttendanceRecordResponse]])
async def get_my_records(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    stmt = select(AttendanceRecord).where(
        AttendanceRecord.organization_id == current_user.organization_id,
        AttendanceRecord.faculty_id == current_user.id
    )
    res = await db.execute(stmt)
    records = res.scalars().all()
    
    record_responses = [AttendanceRecordResponse.model_validate(r) for r in records]
    return StandardResponse(
        success=True,
        message="Personal attendance history loaded.",
        data=record_responses,
    )

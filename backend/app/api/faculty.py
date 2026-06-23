from datetime import datetime, timezone, date
from typing import Any, List, Optional
import uuid
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.dependencies import get_current_user, require_role, get_db
from app.core.constants import UserRole, UserStatus, RequestStatus
from app.core.exceptions import NotFoundException
from app.schemas.base import StandardResponse
from app.schemas.auth import UserInfo
from app.schemas.faculty import (
    ProfileResponse, ProfileUpdate, DashboardSummaryResponse,
    ReasonRequestCreate, NotificationResponse, DeviceHistoryResponse
)
from app.models.user import Faculty
from app.models.request import FacultyRegistrationRequest
from app.repositories.faculty_repo import FacultyRepository
from app.services.faculty_service import FacultyService

import logging

router = APIRouter()
logger = logging.getLogger("app.api.faculty")


@router.get("/", response_model=StandardResponse[List[UserInfo]])
async def list_faculty(
    status: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    repo = FacultyRepository(db)
    faculty_list = await repo.get_multi_by_org(current_user.organization_id, status=status)
    users = [
        UserInfo(
            id=f.id,
            email=f.email,
            full_name=f.full_name,
            organization_id=f.organization_id,
        )
        for f in faculty_list
    ]
    return StandardResponse(
        success=True,
        message="Faculty roster fetched successfully.",
        data=users,
    )


@router.post("/approve-registration/{request_id}", response_model=StandardResponse[dict])
async def approve_registration(
    request_id: uuid.UUID,
    status: RequestStatus = Query(...),
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    req_stmt = select(FacultyRegistrationRequest).where(
        FacultyRegistrationRequest.id == request_id,
        FacultyRegistrationRequest.organization_id == current_user.organization_id
    )
    req_res = await db.execute(req_stmt)
    req = req_res.scalars().first()
    if not req:
        raise NotFoundException("Faculty registration request not found.")

    req.status = status.value
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    db.add(req)

    if status == RequestStatus.APPROVED:
        logger.info(f"Admin '{current_user.email}' approved faculty registration request {request_id} for faculty ID {req.faculty_id}")
        await db.execute(
            update(Faculty)
            .where(Faculty.id == req.faculty_id)
            .values(status=UserStatus.ACTIVE.value, registered_at=datetime.now(timezone.utc))
        )
    elif status == RequestStatus.REJECTED:
        logger.info(f"Admin '{current_user.email}' rejected faculty registration request {request_id} for faculty ID {req.faculty_id}")
        await db.execute(
            update(Faculty)
            .where(Faculty.id == req.faculty_id)
            .values(status=UserStatus.INACTIVE.value)
        )

    await db.commit()
    return StandardResponse(
        success=True,
        message=f"Faculty registration request {status.value.lower()} successfully.",
        data={},
    )


# ----------------------------------------------------------------------
# Faculty Module Endpoints
# ----------------------------------------------------------------------

@router.get("/profile", response_model=StandardResponse[ProfileResponse])
async def get_profile(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    profile = await service.get_profile(current_user.id)
    return StandardResponse(
        success=True,
        message="Profile details fetched successfully.",
        data=profile,
    )


@router.put("/profile", response_model=StandardResponse[ProfileResponse])
async def update_profile(
    data: ProfileUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    profile = await service.update_profile(current_user.id, data)
    return StandardResponse(
        success=True,
        message="Profile updated successfully.",
        data=profile,
    )


@router.get("/dashboard-summary", response_model=StandardResponse[DashboardSummaryResponse])
async def get_dashboard_summary(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    summary = await service.get_dashboard_summary(current_user.id)
    return StandardResponse(
        success=True,
        message="Dashboard summary fetched successfully.",
        data=summary,
    )


@router.post("/reason-requests", response_model=StandardResponse[dict])
async def submit_reason(
    data: ReasonRequestCreate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    res = await service.submit_reason_request(current_user.id, data)
    return StandardResponse(
        success=True,
        message=res["message"],
        data={},
    )


@router.get("/notifications", response_model=StandardResponse[List[NotificationResponse]])
async def list_notifications(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    notifications = await service.list_notifications(current_user.id)
    return StandardResponse(
        success=True,
        message="Notifications fetched successfully.",
        data=notifications,
    )


@router.post("/notifications/{notification_id}/read", response_model=StandardResponse[dict])
async def mark_read(
    notification_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    res = await service.mark_notification_as_read(current_user.id, notification_id)
    return StandardResponse(
        success=True,
        message=res["message"],
        data={},
    )


@router.post("/notifications/mark-all-read", response_model=StandardResponse[dict])
async def mark_all_read(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    res = await service.mark_all_notifications_as_read(current_user.id)
    return StandardResponse(
        success=True,
        message=res["message"],
        data={},
    )


@router.get("/attendance-history", response_model=StandardResponse[dict])
async def get_history(
    range_type: str = Query("month"),
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    page: int = Query(1),
    limit: int = Query(10),
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    history = await service.list_attendance_history(
        current_user.id, range_type, start_date, end_date, page, limit
    )
    return StandardResponse(
        success=True,
        message="Attendance history fetched successfully.",
        data=history,
    )


@router.get("/devices", response_model=StandardResponse[List[DeviceHistoryResponse]])
async def get_devices(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.FACULTY.value])),
):
    service = FacultyService(db)
    devices = await service.list_devices(current_user.id)
    return StandardResponse(
        success=True,
        message="Device history fetched successfully.",
        data=devices,
    )


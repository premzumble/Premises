from datetime import date, datetime, timezone, timedelta
from typing import Any, Optional, List
import uuid
from fastapi import APIRouter, Depends, Query, Body
from sqlalchemy import select, func, update, desc
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.dependencies import (
    get_current_user, require_role, get_db,
    verify_department_owner, verify_faculty_owner, verify_device_owner,
    verify_excusal_owner, verify_registration_request_owner, verify_device_swap_request_owner
)
from app.core.constants import UserRole, UserStatus, RequestStatus
from app.core.exceptions import NotFoundException, ValidationException
from app.schemas.base import StandardResponse
from app.schemas.attendance import AttendanceSummary, AttendanceOverrideCreate, AttendanceRecordResponse
from app.repositories.attendance_repo import AttendanceRepository
from app.models.user import Faculty
from app.models.organization import Department, Organization
from app.models.request import FacultyRegistrationRequest, DeviceChangeRequest, ReasonRequest, Device
from app.models.notification import Notification
from app.models.attendance import AttendanceRecord
from app.models.log import AuditLog
from pydantic import BaseModel


router = APIRouter()


@router.get("/dashboard-summary", response_model=StandardResponse[AttendanceSummary])
async def get_dashboard_summary(
    target_date: Optional[date] = None,
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    query_date = target_date or datetime.now(timezone.utc).date()
    # Auto-close expired records before fetching dashboard summary
    from app.services.attendance_service import AttendanceService
    attendance_service = AttendanceService(db)
    await attendance_service.close_all_expired_records(current_user.organization_id)

    repo = AttendanceRepository(db)
    summary = await repo.get_dashboard_summary(current_user.organization_id, query_date)
    return StandardResponse(
        success=True,
        message="Dashboard attendance summary loaded successfully.",
        data=AttendanceSummary(**summary),
    )


# ----------------------------------------------------------------------
# POST /admin/walkthrough/complete
# Mark the walkthrough as completed for the authenticated admin
# ----------------------------------------------------------------------
@router.post("/walkthrough/complete", response_model=StandardResponse[dict])
async def complete_walkthrough(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    if not hasattr(current_user, "walkthrough_completed"):
        raise ValidationException("Invalid user type for this operation.")
        
    current_user.walkthrough_completed = True
    db.add(current_user)
    await db.commit()
    return StandardResponse(success=True, message="Walkthrough marked as completed.", data={})


# ----------------------------------------------------------------------
# GET /admin/pending-counts
# Returns counts for registrations, device swaps, excusals, unread notifications
# ----------------------------------------------------------------------
class PendingCounts(BaseModel):
    registrations: int
    device_swaps: int
    excusals: int
    unread_notifications: int

@router.get("/pending-counts", response_model=StandardResponse[PendingCounts])
async def get_pending_counts(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id

    # 1. Registrations count
    reg_stmt = select(func.count()).select_from(FacultyRegistrationRequest).where(
        FacultyRegistrationRequest.organization_id == org_id,
        FacultyRegistrationRequest.status == "PENDING"
    )
    reg_res = await db.execute(reg_stmt)
    reg_count = reg_res.scalar() or 0

    # 2. Device swaps count
    dev_stmt = select(func.count()).select_from(DeviceChangeRequest).where(
        DeviceChangeRequest.organization_id == org_id,
        DeviceChangeRequest.status == "PENDING"
    )
    dev_res = await db.execute(dev_stmt)
    dev_count = dev_res.scalar() or 0

    # 3. Excusals count
    exc_stmt = select(func.count()).select_from(ReasonRequest).where(
        ReasonRequest.organization_id == org_id,
        ReasonRequest.status == "PENDING"
    )
    exc_res = await db.execute(exc_stmt)
    exc_count = exc_res.scalar() or 0

    # 4. Unread admin notifications count
    notif_stmt = select(func.count()).select_from(Notification).where(
        Notification.organization_id == org_id,
        Notification.read_at == None,
        Notification.recipient_role == "ADMIN"
    )
    notif_res = await db.execute(notif_stmt)
    notif_count = notif_res.scalar() or 0

    return StandardResponse(
        success=True,
        message="Pending counts loaded successfully.",
        data=PendingCounts(
            registrations=reg_count,
            device_swaps=dev_count,
            excusals=exc_count,
            unread_notifications=notif_count
        )
    )


# ----------------------------------------------------------------------
# GET /admin/pending-registrations
# ----------------------------------------------------------------------
class PendingRegistrationItem(BaseModel):
    id: uuid.UUID
    name: str
    email: str
    dept: str
    time: datetime
    org_name: str
    status: str

@router.get("/pending-registrations", response_model=StandardResponse[List[PendingRegistrationItem]])
async def get_pending_registrations(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id

    stmt = (
        select(FacultyRegistrationRequest, Faculty, Department, Organization)
        .join(Faculty, FacultyRegistrationRequest.faculty_id == Faculty.id)
        .join(Department, Faculty.department_id == Department.id)
        .join(Organization, FacultyRegistrationRequest.organization_id == Organization.id)
        .where(
            FacultyRegistrationRequest.organization_id == org_id,
            FacultyRegistrationRequest.status == "PENDING"
        )
        .order_by(FacultyRegistrationRequest.created_at.desc())
    )
    res = await db.execute(stmt)
    results = res.all()

    items = []
    for req, fac, dept, org in results:
        items.append(
            PendingRegistrationItem(
                id=req.id,
                name=fac.full_name,
                email=fac.email,
                dept=dept.name,
                time=req.created_at,
                org_name=org.name,
                status=req.status
            )
        )

    return StandardResponse(
        success=True,
        message="Pending registrations loaded.",
        data=items
    )


# ----------------------------------------------------------------------
# GET /admin/pending-device-swaps
# ----------------------------------------------------------------------
class PendingDeviceSwapItem(BaseModel):
    id: uuid.UUID
    faculty_name: str
    email: str
    old_device: Optional[str] = None
    new_device: str
    reason: Optional[str] = None
    time: datetime

@router.get("/pending-device-swaps", response_model=StandardResponse[List[PendingDeviceSwapItem]])
async def get_pending_device_swaps(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id

    stmt = (
        select(DeviceChangeRequest, Faculty)
        .join(Faculty, DeviceChangeRequest.faculty_id == Faculty.id)
        .where(
            DeviceChangeRequest.organization_id == org_id,
            DeviceChangeRequest.status == "PENDING"
        )
        .order_by(DeviceChangeRequest.created_at.desc())
    )
    res = await db.execute(stmt)
    results = res.all()

    items = []
    for req, fac in results:
        # Resolve old device name if present
        old_device_name = "Unknown Device"
        if req.old_device_id:
            old_dev_stmt = select(Device).where(Device.id == req.old_device_id)
            old_dev_res = await db.execute(old_dev_stmt)
            old_dev = old_dev_res.scalars().first()
            if old_dev:
                old_device_name = f"{old_dev.device_model} ({old_dev.platform})"

        items.append(
            PendingDeviceSwapItem(
                id=req.id,
                faculty_name=fac.full_name,
                email=fac.email,
                old_device=old_device_name,
                new_device=req.new_device_model,
                reason=req.reason,
                time=req.created_at
            )
        )

    return StandardResponse(
        success=True,
        message="Pending device swaps loaded.",
        data=items
    )


# ----------------------------------------------------------------------
# GET /admin/pending-excusals
# ----------------------------------------------------------------------
class PendingExcusalItem(BaseModel):
    id: uuid.UUID
    faculty_name: str
    email: str
    date: date
    reason_type: str
    notes: Optional[str] = None
    time: datetime

@router.get("/pending-excusals", response_model=StandardResponse[List[PendingExcusalItem]])
async def get_pending_excusals(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id

    stmt = (
        select(ReasonRequest, Faculty, AttendanceRecord)
        .join(Faculty, ReasonRequest.faculty_id == Faculty.id)
        .join(AttendanceRecord, ReasonRequest.attendance_record_id == AttendanceRecord.id)
        .where(
            ReasonRequest.organization_id == org_id,
            ReasonRequest.status == "PENDING"
        )
        .order_by(ReasonRequest.submitted_at.desc())
    )
    res = await db.execute(stmt)
    results = res.all()

    items = []
    for req, fac, att in results:
        items.append(
            PendingExcusalItem(
                id=req.id,
                faculty_name=fac.full_name,
                email=fac.email,
                date=att.attendance_date,
                reason_type=req.reason_type,
                notes=req.notes,
                time=req.submitted_at
            )
        )

    return StandardResponse(
        success=True,
        message="Pending geofence excusals loaded.",
        data=items
    )


# ----------------------------------------------------------------------
# Approve / Reject actions
# ----------------------------------------------------------------------
class ActionRequest(BaseModel):
    rejection_reason: Optional[str] = None

@router.post("/approve-registration/{request_id}", response_model=StandardResponse[dict])
async def approve_registration(
    request_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_registration_request_owner(db, request_id, current_user.organization_id)
    stmt = select(FacultyRegistrationRequest).where(
        FacultyRegistrationRequest.id == request_id,
        FacultyRegistrationRequest.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    req = res.scalars().first()
    if not req:
        raise NotFoundException("Registration request not found.")

    req.status = "APPROVED"
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    db.add(req)

    # Activate Faculty
    await db.execute(
        update(Faculty)
        .where(Faculty.id == req.faculty_id, Faculty.organization_id == current_user.organization_id)
        .values(status=UserStatus.ACTIVE.value, registered_at=datetime.now(timezone.utc))
    )

    # Create Faculty Notification
    approved_notification = Notification(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        type="REGISTRATION_APPROVED",
        title="Registration Approved",
        message="Your faculty registration request has been approved. Welcome to the campus portal!",
        recipient_role="FACULTY",
        recipient_id=req.faculty_id
    )
    db.add(approved_notification)

    # Audit log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="FACULTY_REGISTRATION_APPROVED",
        entity_type="FACULTY_REGISTRATION_REQUEST",
        entity_id=req.id,
        new_value={"faculty_id": str(req.faculty_id), "status": "APPROVED"}
    )
    db.add(audit_log)

    await db.commit()
    return StandardResponse(success=True, message="Faculty registration request approved successfully.", data={})



@router.post("/reject-registration/{request_id}", response_model=StandardResponse[dict])
async def reject_registration(
    request_id: uuid.UUID,
    data: ActionRequest = Body(...),
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_registration_request_owner(db, request_id, current_user.organization_id)
    stmt = select(FacultyRegistrationRequest).where(
        FacultyRegistrationRequest.id == request_id,
        FacultyRegistrationRequest.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    req = res.scalars().first()
    if not req:
        raise NotFoundException("Registration request not found.")

    req.status = "REJECTED"
    req.rejection_reason = data.rejection_reason
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    db.add(req)

    # Deactivate Faculty
    await db.execute(
        update(Faculty)
        .where(Faculty.id == req.faculty_id, Faculty.organization_id == current_user.organization_id)
        .values(status=UserStatus.INACTIVE.value)
    )

    # Create Faculty Notification
    rejected_notification = Notification(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        type="REGISTRATION_REJECTED",
        title="Registration Rejected",
        message=f"Your faculty registration request has been rejected. Reason: {data.rejection_reason or 'No reason specified'}.",
        recipient_role="FACULTY",
        recipient_id=req.faculty_id
    )
    db.add(rejected_notification)

    # Audit log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="FACULTY_REGISTRATION_REJECTED",
        entity_type="FACULTY_REGISTRATION_REQUEST",
        entity_id=req.id,
        new_value={"faculty_id": str(req.faculty_id), "status": "REJECTED", "rejection_reason": data.rejection_reason}
    )
    db.add(audit_log)

    await db.commit()
    return StandardResponse(success=True, message="Faculty registration request rejected successfully.", data={})



@router.post("/approve-device-swap/{request_id}", response_model=StandardResponse[dict])
async def approve_device_swap(
    request_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_device_swap_request_owner(db, request_id, current_user.organization_id)
    stmt = select(DeviceChangeRequest).where(
        DeviceChangeRequest.id == request_id,
        DeviceChangeRequest.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    req = res.scalars().first()
    if not req:
        raise NotFoundException("Device swap request not found.")

    req.status = "APPROVED"
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    db.add(req)

    # Deactivate old devices for this faculty
    await db.execute(
        update(Device)
        .where(Device.faculty_id == req.faculty_id, Device.organization_id == current_user.organization_id)
        .values(is_active=False)
    )

    # Register and activate the new device
    new_device = Device(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        device_identifier=req.new_device_identifier,
        device_model=req.new_device_model,
        platform="ANDROID", # default
        is_active=True
    )
    db.add(new_device)

    # Create security alert notification for the faculty member
    security_notification = Notification(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        type="SECURITY",
        title="Device Changed Approved",
        message=f"Your device change request for {req.new_device_model} has been approved by the administrator.",
        recipient_role="FACULTY",
        recipient_id=req.faculty_id
    )
    db.add(security_notification)

    # Audit log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="DEVICE_SWAP_APPROVED",
        entity_type="DEVICE_CHANGE_REQUEST",
        entity_id=req.id,
        new_value={
            "faculty_id": str(req.faculty_id),
            "status": "APPROVED",
            "new_device_identifier": req.new_device_identifier,
            "new_device_model": req.new_device_model
        }
    )
    db.add(audit_log)

    await db.commit()
    return StandardResponse(success=True, message="Device change request approved successfully.", data={})



@router.post("/reject-device-swap/{request_id}", response_model=StandardResponse[dict])
async def reject_device_swap(
    request_id: uuid.UUID,
    data: ActionRequest = Body(...),
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_device_swap_request_owner(db, request_id, current_user.organization_id)
    stmt = select(DeviceChangeRequest).where(
        DeviceChangeRequest.id == request_id,
        DeviceChangeRequest.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    req = res.scalars().first()
    if not req:
        raise NotFoundException("Device swap request not found.")

    req.status = "REJECTED"
    req.rejection_reason = data.rejection_reason
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    db.add(req)

    # Create security alert notification for the faculty member
    security_notification = Notification(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        type="SECURITY",
        title="Device Change Rejected",
        message=f"Your device change request for {req.new_device_model} has been rejected: {data.rejection_reason or 'No reason specified'}.",
        recipient_role="FACULTY",
        recipient_id=req.faculty_id
    )
    db.add(security_notification)

    # Audit log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="DEVICE_SWAP_REJECTED",
        entity_type="DEVICE_CHANGE_REQUEST",
        entity_id=req.id,
        new_value={
            "faculty_id": str(req.faculty_id),
            "status": "REJECTED",
            "rejection_reason": data.rejection_reason
        }
    )
    db.add(audit_log)

    await db.commit()
    return StandardResponse(success=True, message="Device change request rejected successfully.", data={})



@router.post("/approve-excusal/{request_id}", response_model=StandardResponse[dict])
async def approve_excusal(
    request_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_excusal_owner(db, request_id, current_user.organization_id)
    stmt = select(ReasonRequest).where(
        ReasonRequest.id == request_id,
        ReasonRequest.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    req = res.scalars().first()
    if not req:
        raise NotFoundException("Geofence excusal request not found.")

    req.status = "APPROVED"
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    db.add(req)

    # Recalculate and update the associated attendance record status
    if req.attendance_record_id:
        rec_stmt = select(AttendanceRecord).where(
            AttendanceRecord.id == req.attendance_record_id,
            AttendanceRecord.organization_id == current_user.organization_id
        )
        rec_res = await db.execute(rec_stmt)
        record = rec_res.scalars().first()
        if record:
            from app.repositories.geofence_repo import GeofenceRepository
            geofence_repo = GeofenceRepository(db)
            policy = await geofence_repo.get_policy_by_org(current_user.organization_id)
            if policy:
                from app.services.attendance_service import AttendanceService
                att_service = AttendanceService(db)
                tz = record.first_entry_time.tzinfo if (record.first_entry_time and record.first_entry_time.tzinfo) else timezone.utc
                shift_end_dt = datetime.combine(record.attendance_date, policy.end_time).replace(tzinfo=tz)
                now_dt = datetime.now(tz)
                
                if record.last_exit_time is not None or now_dt >= shift_end_dt:
                    # Record is closed or past shift end, force closure/re-evaluation
                    # Clear last_exit_time temporarily to allow evaluate_and_close_record to run
                    orig_exit = record.last_exit_time
                    record.last_exit_time = None
                    await att_service.evaluate_and_close_record(record, policy)
                    # If evaluate_and_close_record didn't set a last_exit_time, restore the original one
                    if record.last_exit_time is None:
                        record.last_exit_time = orig_exit
                else:
                    await att_service.recalculate_record_durations(record, policy)
                    base_status = att_service.get_evaluated_status(record, policy)
                    record.status = base_status
                db.add(record)

    # Create Faculty Notification
    excusal_notification = Notification(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        type="EXCUSAL_APPROVED",
        title="Excusal Approved",
        message="Your geofence excusal request has been approved.",
        recipient_role="FACULTY",
        recipient_id=req.faculty_id
    )
    db.add(excusal_notification)

    # Audit log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="EXCUSAL_APPROVED",
        entity_type="REASON_REQUEST",
        entity_id=req.id,
        new_value={
            "faculty_id": str(req.faculty_id),
            "status": "APPROVED",
            "attendance_record_id": str(req.attendance_record_id) if req.attendance_record_id else None
        }
    )
    db.add(audit_log)

    await db.commit()
    return StandardResponse(success=True, message="Geofence excusal approved successfully.", data={})



@router.post("/reject-excusal/{request_id}", response_model=StandardResponse[dict])
async def reject_excusal(
    request_id: uuid.UUID,
    data: ActionRequest = Body(...),
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_excusal_owner(db, request_id, current_user.organization_id)
    res = await db.execute(stmt)
    req = res.scalars().first()
    if not req:
        raise NotFoundException("Geofence excusal request not found.")

    req.status = "REJECTED"
    req.rejection_reason = data.rejection_reason
    req.reviewed_by = current_user.id
    # Create Faculty Notification
    excusal_notification = Notification(
        organization_id=current_user.organization_id,
        faculty_id=req.faculty_id,
        type="EXCUSAL_REJECTED",
        title="Excusal Rejected",
        message=f"Your geofence excusal request has been rejected. Reason: {data.rejection_reason or 'No reason specified'}.",
        recipient_role="FACULTY",
        recipient_id=req.faculty_id
    )
    db.add(excusal_notification)

    # Audit log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="EXCUSAL_REJECTED",
        entity_type="REASON_REQUEST",
        entity_id=req.id,
        new_value={
            "faculty_id": str(req.faculty_id),
            "status": "REJECTED",
            "rejection_reason": data.rejection_reason
        }
    )
    db.add(audit_log)

    await db.commit()
    return StandardResponse(success=True, message="Geofence excusal rejected successfully.", data={})



# ----------------------------------------------------------------------
# Admin notifications endpoints
# ----------------------------------------------------------------------
class AdminNotificationItem(BaseModel):
    id: uuid.UUID
    type: str
    title: str
    message: str
    sent_at: datetime
    read: bool

@router.get("/notifications", response_model=StandardResponse[List[AdminNotificationItem]])
async def list_notifications(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id
    stmt = (
        select(Notification)
        .where(
            Notification.organization_id == org_id,
            Notification.recipient_role == "ADMIN"
        )
        .order_by(Notification.sent_at.desc())
    )
    res = await db.execute(stmt)
    notifications = res.scalars().all()

    items = [
        AdminNotificationItem(
            id=n.id,
            type=n.type,
            title=n.title,
            message=n.message,
            sent_at=n.sent_at,
            read=n.read_at is not None
        )
        for n in notifications
    ]
    return StandardResponse(
        success=True,
        message="Admin notifications fetched successfully.",
        data=items
    )


@router.post("/notifications/mark-all-read", response_model=StandardResponse[dict])
async def mark_all_notifications_read(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id
    await db.execute(
        update(Notification)
        .where(
            Notification.organization_id == org_id,
            Notification.read_at == None,
            Notification.recipient_role == "ADMIN"
        )
        .values(read_at=datetime.now(timezone.utc))
    )
    await db.commit()
    return StandardResponse(success=True, message="All admin notifications marked as read.", data={})


# ----------------------------------------------------------------------
# GET /admin/faculty-roster
# ----------------------------------------------------------------------
class FacultyRosterItem(BaseModel):
    id: uuid.UUID
    name: str
    email: str
    dept: str
    status: str
    attendance: str
    device: str

@router.get("/faculty-roster", response_model=StandardResponse[List[FacultyRosterItem]])
async def get_faculty_roster(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    org_id = current_user.organization_id
    # Auto-close expired records before fetching roster
    from app.services.attendance_service import AttendanceService
    attendance_service = AttendanceService(db)
    await attendance_service.close_all_expired_records(org_id)
    
    # 1. Fetch all faculty members in this organization
    stmt = (
        select(Faculty, Department)
        .outerjoin(Department, Faculty.department_id == Department.id)
        .where(Faculty.organization_id == org_id)
        .order_by(Faculty.full_name)
    )
    res = await db.execute(stmt)
    results = res.all()

    # 2. Fetch today's attendance records
    today = datetime.now().astimezone().date()
    rec_stmt = select(AttendanceRecord).where(
        AttendanceRecord.organization_id == org_id,
        AttendanceRecord.attendance_date == today
    )
    rec_res = await db.execute(rec_stmt)
    records = {r.faculty_id: r for r in rec_res.scalars().all()}

    # 3. Fetch latest location event today for each faculty to determine INSIDE/OUTSIDE
    tz = datetime.now().astimezone().tzinfo
    day_start = datetime.combine(today, datetime.min.time()).replace(tzinfo=tz)
    from app.models.attendance import LocationEvent
    evt_stmt = select(LocationEvent).where(
        LocationEvent.organization_id == org_id,
        LocationEvent.event_time >= day_start
    ).order_by(LocationEvent.event_time.desc())
    evt_res = await db.execute(evt_stmt)
    events = evt_res.scalars().all()
    
    latest_events = {}
    for e in events:
        if e.faculty_id not in latest_events:
            latest_events[e.faculty_id] = e

    # 4. Fetch active device for each faculty
    dev_stmt = select(Device).where(
        Device.organization_id == org_id,
        Device.is_active == True
    )
    dev_res = await db.execute(dev_stmt)
    devices = {d.faculty_id: d for d in dev_res.scalars().all()}

    roster = []
    for fac, dept in results:
        record = records.get(fac.id)
        latest_evt = latest_events.get(fac.id)
        dev = devices.get(fac.id)

        # Presence State
        attendance_state = "ABSENT"
        if record:
            attendance_state = record.status
            # If status is not ABSENT, refine to INSIDE/OUTSIDE based on latest event
            if latest_evt:
                if latest_evt.event_type in ["ENTER_CAMPUS", "RETURN_CAMPUS", "CHECK_IN"]:
                    attendance_state = "PRESENT"
                else:
                    attendance_state = "OUTSIDE"

        device_name = "No device bound"
        if fac.status == "PENDING_APPROVAL":
            device_name = "Awaiting Registration"
        elif dev:
            device_name = f"{dev.device_model} ({dev.platform})"

        roster.append(
            FacultyRosterItem(
                id=fac.id,
                name=fac.full_name,
                email=fac.email,
                dept=dept.name if dept else "No Department",
                status=fac.status,
                attendance=attendance_state,
                device=device_name
            )
        )

    return StandardResponse(
        success=True,
        message="Faculty roster fetched successfully.",
        data=roster
    )


# ----------------------------------------------------------------------
# POST /admin/toggle-faculty-status/{faculty_id}
# ----------------------------------------------------------------------
@router.post("/toggle-faculty-status/{faculty_id}", response_model=StandardResponse[dict])
async def toggle_faculty_status(
    faculty_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_faculty_owner(db, faculty_id, current_user.organization_id)
    stmt = select(Faculty).where(
        Faculty.id == faculty_id,
        Faculty.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    faculty = res.scalars().first()
    if not faculty:
        raise NotFoundException("Faculty member not found.")

    if faculty.status == "ACTIVE":
        faculty.status = "INACTIVE"
        # Deactivate devices
        await db.execute(
            update(Device)
            .where(Device.faculty_id == faculty_id, Device.organization_id == current_user.organization_id)
            .values(is_active=False)
        )
        msg = f"Faculty {faculty.full_name} deactivated successfully."
    else:
        faculty.status = "ACTIVE"
        msg = f"Faculty {faculty.full_name} activated successfully."

    db.add(faculty)
    await db.commit()
    return StandardResponse(success=True, message=msg, data={})


# ----------------------------------------------------------------------
# GET /admin/audit-logs
# ----------------------------------------------------------------------
class AuditLogItem(BaseModel):
    id: uuid.UUID
    time: datetime
    actor: str
    actor_type: str
    action: str
    details: str
    entity_type: Optional[str] = None
    entity_id: Optional[uuid.UUID] = None
    old_value: Optional[dict] = None
    new_value: Optional[dict] = None

@router.get("/audit-logs", response_model=StandardResponse[List[AuditLogItem]])
async def get_audit_logs(
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    from app.models.log import AuditLog
    from app.models.user import Admin
    org_id = current_user.organization_id
    
    stmt = select(AuditLog).where(AuditLog.organization_id == org_id).order_by(AuditLog.created_at.desc()).limit(200)
    res = await db.execute(stmt)
    logs = res.scalars().all()

    admin_ids = {l.actor_id for l in logs if l.actor_type == "ADMIN" and l.actor_id}
    faculty_ids = {l.actor_id for l in logs if l.actor_type == "FACULTY" and l.actor_id}

    admin_names = {}
    if admin_ids:
        adm_stmt = select(Admin.id, Admin.full_name).where(Admin.id.in_(admin_ids))
        adm_res = await db.execute(adm_stmt)
        admin_names = dict(adm_res.all())

    faculty_names = {}
    if faculty_ids:
        fac_stmt = select(Faculty.id, Faculty.full_name).where(Faculty.id.in_(faculty_ids))
        fac_res = await db.execute(fac_stmt)
        faculty_names = dict(fac_res.all())

    items = []
    for l in logs:
        actor_name = "System"
        if l.actor_type == "ADMIN":
            actor_name = admin_names.get(l.actor_id, "Unknown Admin")
        elif l.actor_type == "FACULTY":
            actor_name = faculty_names.get(l.actor_id, "Unknown Faculty")
        elif l.actor_type == "SYSTEM":
            actor_name = "System Scheduler"

        details = f"Entity: {l.entity_type} (ID: {l.entity_id})."
        if l.new_value:
            details += f" Details: {l.new_value}"

        items.append(
            AuditLogItem(
                id=l.id,
                time=l.created_at,
                actor=actor_name,
                actor_type=l.actor_type,
                action=l.action,
                details=details,
                entity_type=l.entity_type,
                entity_id=l.entity_id,
                old_value=l.old_value,
                new_value=l.new_value
            )
        )

    return StandardResponse(
        success=True,
        message="Audit logs loaded.",
        data=items
    )


# GET /admin/export-report
# ----------------------------------------------------------------------
@router.get("/export-report")
async def export_report(
    report_type: str = Query("Daily Attendance Summary"),
    format: str = Query("CSV"),
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    department_id: Optional[uuid.UUID] = Query(None),
    faculty_id: Optional[uuid.UUID] = Query(None),
    attendance_status: Optional[str] = Query(None),
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    from fastapi.responses import StreamingResponse
    import io
    import csv
    org_id = current_user.organization_id
    await verify_department_owner(db, department_id, org_id)
    await verify_faculty_owner(db, faculty_id, org_id)
    
    # Base query for Attendance Records vs Devices vs Faculty Directory
    if "Device" in report_type:
        from app.models.request import Device
        stmt = (
            select(Device, Faculty, Department)
            .join(Faculty, Device.faculty_id == Faculty.id)
            .outerjoin(Department, Faculty.department_id == Department.id)
            .where(Device.organization_id == org_id)
        )
        if department_id:
            stmt = stmt.where(Faculty.department_id == department_id)
        if faculty_id:
            stmt = stmt.where(Faculty.id == faculty_id)
        stmt = stmt.order_by(Faculty.full_name)
        
    elif "Faculty-wise" not in report_type and "Directory" not in report_type and "Logs" not in report_type:
        stmt = (
            select(AttendanceRecord, Faculty, Department)
            .join(Faculty, AttendanceRecord.faculty_id == Faculty.id)
            .outerjoin(Department, Faculty.department_id == Department.id)
            .where(AttendanceRecord.organization_id == org_id)
        )
        
        # Apply filters
        if start_date:
            stmt = stmt.where(AttendanceRecord.attendance_date >= start_date)
        if end_date:
            stmt = stmt.where(AttendanceRecord.attendance_date <= end_date)
        if not start_date and not end_date:
            # Default behavior if dates are not specified
            if "Daily" in report_type:
                today = datetime.now().astimezone().date()
                stmt = stmt.where(AttendanceRecord.attendance_date == today)
            elif "Weekly" in report_type or "Audits" in report_type:
                end_dt = datetime.now().astimezone().date()
                start_dt = end_dt - timedelta(days=7)
                stmt = stmt.where(AttendanceRecord.attendance_date.between(start_dt, end_dt))
            elif "Monthly" in report_type:
                end_dt = datetime.now().astimezone().date()
                start_dt = end_dt - timedelta(days=30)
                stmt = stmt.where(AttendanceRecord.attendance_date.between(start_dt, end_dt))
                
        if department_id:
            stmt = stmt.where(Faculty.department_id == department_id)
        if faculty_id:
            stmt = stmt.where(Faculty.id == faculty_id)
            
        # Specific filters for Overrides and Exceptions
        if "Override" in report_type:
            stmt = stmt.where(AttendanceRecord.is_overridden == True)
        elif "Exception" in report_type or "Geofence" in report_type:
            stmt = stmt.where(AttendanceRecord.status.in_(["OUTSIDE", "ABSENT"]))
            
        if attendance_status and attendance_status != "All":
            stmt = stmt.where(AttendanceRecord.status == attendance_status)
            
        stmt = stmt.order_by(AttendanceRecord.attendance_date.desc(), Faculty.full_name.asc())
    else:
        # Directory / Faculty list report
        stmt = (
            select(Faculty, Department)
            .outerjoin(Department, Faculty.department_id == Department.id)
            .where(Faculty.organization_id == org_id)
        )
        if department_id:
            stmt = stmt.where(Faculty.department_id == department_id)
        if faculty_id:
            stmt = stmt.where(Faculty.id == faculty_id)
        if attendance_status and attendance_status != "All":
            stmt = stmt.where(Faculty.status == attendance_status)
            
        stmt = stmt.order_by(Faculty.full_name)

    filename = f"{report_type.replace(' ', '_').lower()}.csv"

    async def csv_generator():
        # Yield UTF-8 BOM so Excel opens it correctly with formatting
        yield b"\xef\xbb\xbf"
        
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        
        if "Device" in report_type:
            writer.writerow(["Faculty Name", "Email Address", "Department", "Device Model", "Platform", "OS Version", "Manufacturer", "Is Active", "Registered Date"])
            yield buffer.getvalue().encode("utf-8")
            buffer.seek(0)
            buffer.truncate(0)
            
            result_stream = await db.stream(stmt)
            async for row in result_stream:
                dev, fac, dept = row
                writer.writerow([
                    fac.full_name,
                    fac.email,
                    dept.name if dept else "No Department",
                    dev.device_model or "-",
                    dev.platform,
                    dev.os_version or "-",
                    dev.manufacturer or "-",
                    "Active" if dev.is_active else "Inactive",
                    dev.registered_at.isoformat() if dev.registered_at else "-"
                ])
                yield buffer.getvalue().encode("utf-8")
                buffer.seek(0)
                buffer.truncate(0)
                
        elif "Faculty-wise" not in report_type and "Directory" not in report_type and "Logs" not in report_type:
            writer.writerow(["Faculty Name", "Email Address", "Department", "Date", "Check In", "Check Out", "Status", "Inside Minutes", "Outside Minutes", "Override Type", "Override Details", "Working Hours"])
            yield buffer.getvalue().encode("utf-8")
            buffer.seek(0)
            buffer.truncate(0)
            
            result_stream = await db.stream(stmt)
            async for row in result_stream:
                r, fac, dept = row
                override_type = "Manual Override" if r.is_overridden else "Automatic Geofence"
                override_details = f"{r.override_status} ({r.override_reason}) - {r.override_remarks}" if r.is_overridden else "-"
                if r.is_overridden and r.effective_working_hours is not None:
                    working_hours = f"{r.effective_working_hours:.2f} hours"
                elif r.total_inside_minutes > 0:
                    working_hours = f"{r.total_inside_minutes / 60.0:.2f} hours"
                else:
                    working_hours = "-"
                
                writer.writerow([
                    fac.full_name,
                    fac.email,
                    dept.name if dept else "No Department",
                    r.attendance_date.isoformat(),
                    r.first_entry_time.isoformat() if r.first_entry_time else "-",
                    r.last_exit_time.isoformat() if r.last_exit_time else "-",
                    r.status,
                    r.total_inside_minutes,
                    r.total_outside_minutes,
                    override_type,
                    override_details,
                    working_hours
                ])
                yield buffer.getvalue().encode("utf-8")
                buffer.seek(0)
                buffer.truncate(0)
        else:
            writer.writerow(["Faculty Name", "Email Address", "Department", "Account Status", "Registered Date"])
            yield buffer.getvalue().encode("utf-8")
            buffer.seek(0)
            buffer.truncate(0)
            
            result_stream = await db.stream(stmt)
            async for row in result_stream:
                fac, dept = row
                writer.writerow([
                    fac.full_name,
                    fac.email,
                    dept.name if dept else "No Department",
                    fac.status,
                    fac.registered_at.isoformat() if fac.registered_at else "-"
                ])
                yield buffer.getvalue().encode("utf-8")
                buffer.seek(0)
                buffer.truncate(0)

    return StreamingResponse(
        csv_generator(),
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Type": "text/csv",
        }
    )




# ----------------------------------------------------------------------
# GET /admin/attendance-logs
# ----------------------------------------------------------------------
class DailyTimelineEvent(BaseModel):
    time: datetime
    event: str
    location: str

class DailyAttendanceItem(BaseModel):
    name: str
    email: str
    status: str
    first_entry: str
    last_exit: str
    inside_mins: int
    outside_mins: int
    timeline: List[DailyTimelineEvent]
    is_overridden: bool = False
    override_status: Optional[str] = None
    override_reason: Optional[str] = None
    override_remarks: Optional[str] = None
    manual_check_in_time: Optional[datetime] = None
    manual_check_out_time: Optional[datetime] = None
    effective_working_hours: Optional[float] = None
    faculty_id: str = ""
    acknowledged_at: Optional[datetime] = None

@router.get("/attendance-logs", response_model=StandardResponse[dict])
async def get_attendance_logs(
    target_date: Optional[date] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    search_query: Optional[str] = Query(None),
    department_id: Optional[uuid.UUID] = Query(None),
    status: Optional[str] = Query(None),
    is_overridden: Optional[bool] = Query(None),
    campus_status: Optional[str] = Query(None),
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    query_date = target_date or datetime.now(timezone.utc).date()
    org_id = current_user.organization_id
    await verify_department_owner(db, department_id, org_id)
    
    from app.services.attendance_service import AttendanceService
    attendance_service = AttendanceService(db)
    await attendance_service.close_all_expired_records(org_id)

    from app.models.attendance import AttendanceRecord
    from sqlalchemy import or_, and_

    # Base count and list select statements
    # Join AttendanceRecord if we need to filter by status / is_overridden / campus_status
    need_join = status is not None or is_overridden is not None or campus_status is not None
    if need_join:
        count_stmt = select(func.count(Faculty.id)).outerjoin(
            AttendanceRecord,
            and_(
                Faculty.id == AttendanceRecord.faculty_id,
                AttendanceRecord.attendance_date == query_date
            )
        ).where(
            Faculty.organization_id == org_id,
            Faculty.status == "ACTIVE"
        )
        fac_stmt = select(Faculty).outerjoin(
            AttendanceRecord,
            and_(
                Faculty.id == AttendanceRecord.faculty_id,
                AttendanceRecord.attendance_date == query_date
            )
        ).where(
            Faculty.organization_id == org_id,
            Faculty.status == "ACTIVE"
        )
        
        # Apply filters
        if status:
            if status == "ABSENT":
                # ABSENT means record has status ABSENT or no record exists
                fac_stmt = fac_stmt.where(or_(AttendanceRecord.status == "ABSENT", AttendanceRecord.id == None))
                count_stmt = count_stmt.where(or_(AttendanceRecord.status == "ABSENT", AttendanceRecord.id == None))
            else:
                fac_stmt = fac_stmt.where(AttendanceRecord.status == status)
                count_stmt = count_stmt.where(AttendanceRecord.status == status)
                
        if is_overridden is not None:
            fac_stmt = fac_stmt.where(AttendanceRecord.is_overridden == is_overridden)
            count_stmt = count_stmt.where(AttendanceRecord.is_overridden == is_overridden)
            
        if campus_status:
            if campus_status == "INSIDE":
                fac_stmt = fac_stmt.where(AttendanceRecord.status == "INSIDE")
                count_stmt = count_stmt.where(AttendanceRecord.status == "INSIDE")
            elif campus_status == "OUTSIDE":
                fac_stmt = fac_stmt.where(or_(AttendanceRecord.status == "OUTSIDE", AttendanceRecord.id == None))
                count_stmt = count_stmt.where(or_(AttendanceRecord.status == "OUTSIDE", AttendanceRecord.id == None))
    else:
        count_stmt = select(func.count(Faculty.id)).where(
            Faculty.organization_id == org_id,
            Faculty.status == "ACTIVE"
        )
        fac_stmt = select(Faculty).where(
            Faculty.organization_id == org_id,
            Faculty.status == "ACTIVE"
        )

    # Apply search filter: name, email, or phone
    if search_query:
        search_filter = or_(
            Faculty.full_name.ilike(f"%{search_query}%"),
            Faculty.email.ilike(f"%{search_query}%"),
            Faculty.phone_number.ilike(f"%{search_query}%")
        )
        fac_stmt = fac_stmt.where(search_filter)
        count_stmt = count_stmt.where(search_filter)

    # Department filter
    if department_id:
        fac_stmt = fac_stmt.where(Faculty.department_id == department_id)
        count_stmt = count_stmt.where(Faculty.department_id == department_id)

    # Run queries
    count_res = await db.execute(count_stmt)
    total_items = count_res.scalar() or 0

    fac_stmt = fac_stmt.order_by(Faculty.full_name).offset((page - 1) * page_size).limit(page_size)
    fac_res = await db.execute(fac_stmt)
    faculty_list = fac_res.scalars().all()

    faculty_ids = [fac.id for fac in faculty_list]

    if not faculty_ids:
        return StandardResponse(
            success=True,
            message="Daily attendance logs fetched.",
            data={
                "items": [],
                "page": page,
                "page_size": page_size,
                "total": total_items
            }
        )

    # 3. Fetch today's records for these faculty
    rec_stmt = select(AttendanceRecord).where(
        AttendanceRecord.organization_id == org_id,
        AttendanceRecord.attendance_date == query_date,
        AttendanceRecord.faculty_id.in_(faculty_ids)
    )
    rec_res = await db.execute(rec_stmt)
    records = {r.faculty_id: r for r in rec_res.scalars().all()}

    # 3b. Fetch override notifications for these faculty today
    notif_stmt = select(Notification).where(
        Notification.organization_id == org_id,
        Notification.faculty_id.in_(faculty_ids),
        Notification.type == "ATTENDANCE_OVERRIDE"
    )
    notif_res = await db.execute(notif_stmt)
    notifications = {n.faculty_id: n for n in notif_res.scalars().all()}

    # 4. Fetch location events for these faculty
    day_start = datetime.combine(query_date, datetime.min.time(), tzinfo=timezone.utc)
    day_end = datetime.combine(query_date, datetime.max.time(), tzinfo=timezone.utc)
    from app.models.attendance import LocationEvent
    evt_stmt = select(LocationEvent).where(
        LocationEvent.organization_id == org_id,
        LocationEvent.faculty_id.in_(faculty_ids),
        LocationEvent.event_time.between(day_start, day_end)
    ).order_by(LocationEvent.event_time.asc())
    evt_res = await db.execute(evt_stmt)
    events = evt_res.scalars().all()

    faculty_events = {}
    for e in events:
        faculty_events.setdefault(e.faculty_id, []).append(e)

    logs = []
    for fac in faculty_list:
        record = records.get(fac.id)
        fac_evts = faculty_events.get(fac.id, [])

        timeline = []
        for e in fac_evts:
            timeline.append(
                DailyTimelineEvent(
                    time=e.event_time,
                    event=e.event_type,
                    location=f"GPS: {e.latitude:.4f}, {e.longitude:.4f}"
                )
            )

        status = "ABSENT"
        first_entry = "-"
        last_exit = "-"
        inside_mins = 0
        outside_mins = 0
        
        is_overridden = False
        override_status = None
        override_reason = None
        override_remarks = None
        manual_check_in_time = None
        manual_check_out_time = None
        effective_working_hours = None
        acknowledged_at = None

        if record:
            status = record.status
            if record.first_entry_time:
                first_entry = record.first_entry_time.isoformat()
            if record.last_exit_time:
                last_exit = record.last_exit_time.isoformat()
            inside_mins = record.total_inside_minutes
            outside_mins = record.total_outside_minutes
            
            is_overridden = record.is_overridden
            override_status = record.override_status
            override_reason = record.override_reason
            override_remarks = record.override_remarks
            manual_check_in_time = record.manual_check_in_time
            manual_check_out_time = record.manual_check_out_time
            effective_working_hours = record.effective_working_hours
            
            notif = notifications.get(fac.id)
            if notif:
                acknowledged_at = notif.acknowledged_at

        logs.append(
            DailyAttendanceItem(
                name=fac.full_name,
                email=fac.email,
                status=status,
                first_entry=first_entry,
                last_exit=last_exit,
                inside_mins=inside_mins,
                outside_mins=outside_mins,
                timeline=timeline,
                is_overridden=is_overridden,
                override_status=override_status,
                override_reason=override_reason,
                override_remarks=override_remarks,
                manual_check_in_time=manual_check_in_time,
                manual_check_out_time=manual_check_out_time,
                effective_working_hours=effective_working_hours,
                faculty_id=str(fac.id),
                acknowledged_at=acknowledged_at
            )
        )

    # Calculate daily KPI summaries
    kpi_present = await db.scalar(select(func.count(AttendanceRecord.id)).where(AttendanceRecord.organization_id == org_id, AttendanceRecord.attendance_date == query_date, AttendanceRecord.status == "PRESENT")) or 0
    kpi_half_day = await db.scalar(select(func.count(AttendanceRecord.id)).where(AttendanceRecord.organization_id == org_id, AttendanceRecord.attendance_date == query_date, AttendanceRecord.status == "HALF_DAY")) or 0
    kpi_overrides = await db.scalar(select(func.count(AttendanceRecord.id)).where(AttendanceRecord.organization_id == org_id, AttendanceRecord.attendance_date == query_date, AttendanceRecord.is_overridden == True)) or 0
    kpi_inside = await db.scalar(select(func.count(AttendanceRecord.id)).where(AttendanceRecord.organization_id == org_id, AttendanceRecord.attendance_date == query_date, AttendanceRecord.status == "INSIDE")) or 0
    kpi_outside = await db.scalar(select(func.count(AttendanceRecord.id)).where(AttendanceRecord.organization_id == org_id, AttendanceRecord.attendance_date == query_date, AttendanceRecord.status == "OUTSIDE")) or 0
    
    total_active_faculty = await db.scalar(select(func.count(Faculty.id)).where(Faculty.organization_id == org_id, Faculty.status == "ACTIVE")) or 0
    kpi_absent = total_active_faculty - (kpi_present + kpi_half_day + kpi_inside + kpi_outside)
    if kpi_absent < 0:
        kpi_absent = 0

    return StandardResponse(
        success=True,
        message="Daily attendance logs fetched.",
        data={
            "items": logs,
            "page": page,
            "page_size": page_size,
            "total": total_items,
            "kpis": {
                "present": kpi_present,
                "absent": kpi_absent,
                "half_day": kpi_half_day,
                "overrides": kpi_overrides,
                "inside": kpi_inside,
                "outside": kpi_outside
            }
        }
    )


@router.post("/attendance/override", response_model=StandardResponse[dict])
async def override_attendance(
    data: AttendanceOverrideCreate,
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_faculty_owner(db, data.faculty_id, current_user.organization_id)
    from app.models.user import Admin
    # 1. Fetch Target Faculty
    fac_stmt = select(Faculty).where(
        Faculty.id == data.faculty_id,
        Faculty.organization_id == current_user.organization_id
    )
    fac_res = await db.execute(fac_stmt)
    faculty = fac_res.scalar_one_or_none()
    if not faculty:
        raise NotFoundException("Faculty member not found.")

    # 2. Check if already overridden
    stmt = select(AttendanceRecord).where(
        AttendanceRecord.faculty_id == data.faculty_id,
        AttendanceRecord.attendance_date == data.attendance_date,
        AttendanceRecord.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    record = res.scalar_one_or_none()

    if record and record.is_overridden and not data.force_replace:
        return StandardResponse(
            success=False,
            message="This attendance has already been manually overridden.",
            data={"already_overridden": True}
        )

    # Fetch Admin Name
    admin_stmt = select(Admin).where(Admin.id == current_user.id)
    admin_res = await db.execute(admin_stmt)
    admin = admin_res.scalar_one_or_none()
    admin_name = admin.full_name if admin else "Admin"

    previous_status = record.status if record else "ABSENT"

    # Map override_status parameter to database status value
    db_status = "ABSENT"
    if data.override_status in ["Full Day Present", "PRESENT"]:
        db_status = "PRESENT"
    elif data.override_status in ["Half Day Present", "Half Day Absent", "HALF_DAY"]:
        db_status = "HALF_DAY"

    # 3. Create or Update record
    if not record:
        record = AttendanceRecord(
            organization_id=current_user.organization_id,
            faculty_id=data.faculty_id,
            attendance_date=data.attendance_date,
            status=db_status,
            first_entry_time=data.manual_check_in_time,
            last_exit_time=data.manual_check_out_time,
            total_inside_minutes=480 if db_status == "PRESENT" else (240 if db_status == "HALF_DAY" else 0),
            is_overridden=True,
            override_status=data.override_status,
            override_reason=data.override_reason,
            override_remarks=data.override_remarks,
            override_by=current_user.id,
            override_at=datetime.now(timezone.utc),
            manual_check_in_time=data.manual_check_in_time,
            manual_check_out_time=data.manual_check_out_time,
            effective_working_hours=data.effective_working_hours
        )
        db.add(record)
    else:
        record.status = db_status
        record.is_overridden = True
        record.override_status = data.override_status
        record.override_reason = data.override_reason
        record.override_remarks = data.override_remarks
        record.override_by = current_user.id
        record.override_at = datetime.now(timezone.utc)
        record.manual_check_in_time = data.manual_check_in_time
        record.manual_check_out_time = data.manual_check_out_time
        record.effective_working_hours = data.effective_working_hours
        if data.manual_check_in_time:
            record.first_entry_time = data.manual_check_in_time
        if data.manual_check_out_time:
            record.last_exit_time = data.manual_check_out_time

    await db.flush()

    # 4. Detailed polymorphic Audit Log
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="ATTENDANCE_OVERRIDE",
        entity_type="ATTENDANCE_RECORD",
        entity_id=record.id,
        old_value={"status": previous_status},
        new_value={
            "admin_name": admin_name,
            "admin_id": str(current_user.id),
            "faculty_name": faculty.full_name,
            "faculty_id": str(faculty.id),
            "previous_status": previous_status,
            "new_status": data.override_status,
            "override_reason": data.override_reason,
            "remarks": data.override_remarks,
            "date": str(data.attendance_date),
            "time": datetime.now(timezone.utc).isoformat(),
            "manual_check_in": data.manual_check_in_time.isoformat() if data.manual_check_in_time else None,
            "manual_check_out": data.manual_check_out_time.isoformat() if data.manual_check_out_time else None,
            "effective_working_hours": data.effective_working_hours,
            "source": "Admin Portal"
        }
    )
    db.add(audit_log)

    # 5. Create Notification for Faculty
    notif = Notification(
        organization_id=current_user.organization_id,
        faculty_id=data.faculty_id,
        type="ATTENDANCE_OVERRIDE",
        title="Attendance Updated",
        message=(
            f"Your attendance for {data.attendance_date} has been manually updated by your administrator.\n\n"
            f"Status: {data.override_status}\n"
            f"Reason: {data.override_reason}\n"
            f"Remarks: {data.override_remarks}"
        ),
        status="SENT",
        recipient_role="FACULTY",
        recipient_id=data.faculty_id
    )
    db.add(notif)

    # 6. Dispatch Email notification
    from app.services.email_service import EmailService
    await EmailService.send_override_email(
        db=db,
        email=faculty.email,
        faculty_name=faculty.full_name,
        attendance_date=str(data.attendance_date),
        override_status=data.override_status,
        override_reason=data.override_reason,
        override_remarks=data.override_remarks,
        organization_id=current_user.organization_id,
        user_id=current_user.id
    )

    await db.commit()

    return StandardResponse(
        success=True,
        message="Attendance record manually overridden and logged successfully.",
        data={"record_id": str(record.id)}
    )


@router.get("/attendance/overrides", response_model=StandardResponse[List[dict]])
async def get_manual_overrides(
    target_date: Optional[date] = Query(None),
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    query_date = target_date or datetime.now(timezone.utc).date()
    from app.models.user import Faculty
    from app.models.notification import Notification
    
    stmt = select(AttendanceRecord, Faculty.full_name).join(
        Faculty, Faculty.id == AttendanceRecord.faculty_id
    ).where(
        AttendanceRecord.organization_id == current_user.organization_id,
        AttendanceRecord.attendance_date == query_date,
        AttendanceRecord.is_overridden == True
    ).order_by(AttendanceRecord.updated_at.desc())
    
    res = await db.execute(stmt)
    results = res.all()
    
    faculty_ids = [r[0].faculty_id for r in results]
    notifications = {}
    if faculty_ids:
        notif_stmt = select(Notification).where(
            Notification.organization_id == current_user.organization_id,
            Notification.faculty_id.in_(faculty_ids),
            Notification.type == "ATTENDANCE_OVERRIDE"
        )
        notif_res = await db.execute(notif_stmt)
        notifications = {n.faculty_id: n.acknowledged_at for n in notif_res.scalars().all()}
    
    data = []
    for record, full_name in results:
        data.append({
            "id": str(record.id),
            "faculty_id": str(record.faculty_id),
            "faculty_name": full_name,
            "attendance_date": record.attendance_date.isoformat(),
            "status": record.status,
            "override_status": record.override_status,
            "override_reason": record.override_reason,
            "override_remarks": record.override_remarks,
            "override_at": record.override_at.isoformat() if record.override_at else None,
            "manual_check_in_time": record.manual_check_in_time.isoformat() if record.manual_check_in_time else None,
            "manual_check_out_time": record.manual_check_out_time.isoformat() if record.manual_check_out_time else None,
            "effective_working_hours": record.effective_working_hours,
            "acknowledged_at": notifications.get(record.faculty_id).isoformat() if notifications.get(record.faculty_id) else None
        })
        
    return StandardResponse(
        success=True,
        message="Manual overrides loaded successfully.",
        data=data
    )


class AttendanceSimulationCreate(BaseModel):
    faculty_id: uuid.UUID
    is_entry: bool
    event_time: Optional[datetime] = None


@router.get("/faculty", response_model=StandardResponse[List[dict]])
async def get_simulator_faculty(
    status: Optional[str] = Query(None),
    limit: int = Query(100),
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    # Map APPROVED to ACTIVE if sent by simulator
    db_status = "ACTIVE"
    if status == "APPROVED":
        db_status = "ACTIVE"
    elif status:
        db_status = status

    from app.repositories.faculty_repo import FacultyRepository
    repo = FacultyRepository(db)
    faculty_list = await repo.get_multi_by_org(current_user.organization_id, status=db_status, limit=limit)
    
    results = []
    for f in faculty_list:
        dept_name = "No Department"
        if f.department_id:
            dept_stmt = select(Department.name).where(Department.id == f.department_id)
            dept_res = await db.execute(dept_stmt)
            dept_name = dept_res.scalar() or "No Department"
            
        results.append({
            "id": str(f.id),
            "first_name": f.full_name,
            "last_name": "",
            "email": f.email,
            "department": dept_name,
        })
        
    return StandardResponse(
        success=True,
        message="Faculty fetched for simulator.",
        data=results
    )


@router.post("/attendance/simulate-event", response_model=StandardResponse[dict])
async def simulate_event(
    data: AttendanceSimulationCreate,
    current_user: Any = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _role_guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    await verify_faculty_owner(db, data.faculty_id, current_user.organization_id)
    
    from app.services.attendance_service import AttendanceService
    from app.schemas.attendance import LocationEventCreate
    from app.core.constants import LocationEventType
    
    att_service = AttendanceService(db)
    geofences = await att_service.geofence_repo.get_active_by_org(current_user.organization_id)
    
    # Default to Stanford Quad coords if no active geofence
    latitude = 37.4275
    longitude = -122.1697
    
    if data.is_entry:
        if geofences:
            gf = geofences[0]
            if gf.geofence_type == "circle":
                latitude = gf.latitude or 37.4275
                longitude = gf.longitude or -122.1697
            elif gf.geofence_type == "polygon" and gf.vertices:
                latitude = gf.vertices[0].latitude
                longitude = gf.vertices[0].longitude
    else:
        if geofences:
            gf = geofences[0]
            if gf.geofence_type == "circle":
                latitude = (gf.latitude or 37.4275) + 0.1
                longitude = (gf.longitude or -122.1697) + 0.1
            elif gf.geofence_type == "polygon" and gf.vertices:
                latitude = gf.vertices[0].latitude + 0.1
                longitude = gf.vertices[0].longitude + 0.1
        else:
            latitude = 38.4275
            longitude = -121.1697

    active_device = await att_service.faculty_repo.get_active_device(data.faculty_id)
    device_id = active_device.device_identifier if active_device else "SIMULATED_DEVICE"
    
    evt_time = data.event_time or datetime.now(timezone.utc)
    
    evt_data = LocationEventCreate(
        event_type=LocationEventType.ENTER_CAMPUS if data.is_entry else LocationEventType.EXIT_CAMPUS,
        latitude=latitude,
        longitude=longitude,
        event_time=evt_time,
        device_identifier=device_id
    )
    
    event = await att_service.register_location_event(data.faculty_id, current_user.organization_id, evt_data)
    
    # Recalculate working hours for response
    record = await att_service.attendance_repo.get_record(data.faculty_id, evt_time.astimezone().date())
    
    return StandardResponse(
        success=True,
        message="Simulated location event processed successfully.",
        data={
            "id": str(event.id) if event else None,
            "event_type": event.event_type if event else None,
            "latitude": latitude,
            "longitude": longitude,
            "event_time": evt_time.isoformat(),
            "working_hours": record.total_inside_minutes / 60.0 if record else 0.0,
            "status": record.status if record else "ABSENT"
        }
    )


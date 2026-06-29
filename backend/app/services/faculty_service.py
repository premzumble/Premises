import uuid
from datetime import datetime, date, timedelta, timezone
from typing import List, Optional
from sqlalchemy import select, update, desc, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.exceptions import NotFoundException, ValidationException, ConflictException
from app.models.user import Faculty
from app.models.organization import Organization, Department
from app.models.request import Device, ReasonRequest
from app.models.attendance import AttendanceRecord, LocationEvent
from app.models.notification import Notification
from app.models.geofence import Geofence, AttendancePolicy
from app.schemas.faculty import (
    ProfileResponse, ProfileUpdate, DashboardSummaryResponse,
    ReasonRequestCreate, NotificationResponse, DeviceHistoryResponse
)


class FacultyService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_profile(self, faculty_id: uuid.UUID) -> ProfileResponse:
        stmt = select(Faculty).where(Faculty.id == faculty_id)
        res = await self.db.execute(stmt)
        faculty = res.scalars().first()
        if not faculty:
            raise NotFoundException("Faculty profile not found.")

        # Get organization name
        org_stmt = select(Organization).where(Organization.id == faculty.organization_id)
        org_res = await self.db.execute(org_stmt)
        org = org_res.scalars().first()
        org_name = org.name if org else "Unknown Organization"

        # Get department name
        dept_name = None
        if faculty.department_id:
            dept_stmt = select(Department).where(Department.id == faculty.department_id)
            dept_res = await self.db.execute(dept_stmt)
            dept = dept_res.scalars().first()
            dept_name = dept.name if dept else None

        # Get active device details
        device_stmt = select(Device).where(Device.faculty_id == faculty_id, Device.is_active == True)
        device_res = await self.db.execute(device_stmt)
        device = device_res.scalars().first()
        registered_device = f"{device.device_model} ({device.platform})" if device else "No active device bound"

        return ProfileResponse(
            id=faculty.id,
            full_name=faculty.full_name,
            email=faculty.email,
            phone_number=faculty.phone_number,
            emergency_contact=faculty.emergency_contact,
            profile_photo_url=faculty.profile_photo_url,
            organization_name=org_name,
            department_name=dept_name,
            registered_device=registered_device
        )

    async def update_profile(self, faculty_id: uuid.UUID, data: ProfileUpdate) -> ProfileResponse:
        stmt = select(Faculty).where(Faculty.id == faculty_id)
        res = await self.db.execute(stmt)
        faculty = res.scalars().first()
        if not faculty:
            raise NotFoundException("Faculty profile not found.")

        if data.phone_number is not None:
            faculty.phone_number = data.phone_number
        if data.emergency_contact is not None:
            faculty.emergency_contact = data.emergency_contact
        if data.profile_photo_url is not None:
            faculty.profile_photo_url = data.profile_photo_url

        if data.new_password is not None:
            if not data.current_password:
                raise ValidationException("Current password is required to set a new password.")

            from app.core.security import verify_password, get_password_hash
            if not verify_password(data.current_password, faculty.password_hash):
                raise ValidationException("Invalid current password.")

            faculty.password_hash = get_password_hash(data.new_password)

        self.db.add(faculty)
        await self.db.commit()
        return await self.get_profile(faculty_id)

    async def get_dashboard_summary(self, faculty_id: uuid.UUID) -> DashboardSummaryResponse:
        stmt = select(Faculty).where(Faculty.id == faculty_id)
        res = await self.db.execute(stmt)
        faculty = res.scalars().first()
        if not faculty:
            raise NotFoundException("Faculty profile not found.")

        # Geofence details
        from sqlalchemy.orm import selectinload
        gf_stmt = (
            select(Geofence)
            .where(Geofence.organization_id == faculty.organization_id, Geofence.is_active == True)
            .options(selectinload(Geofence.vertices))
        )
        gf_res = await self.db.execute(gf_stmt)
        geofence = gf_res.scalars().first()

        geofence_lat = 0.0
        geofence_lng = 0.0
        geofence_rad = 0.0
        geofence_type = "circle"
        geofence_vertices = None

        if geofence:
            geofence_type = geofence.geofence_type
            if geofence_type == "circle":
                geofence_lat = geofence.latitude if geofence.latitude is not None else 0.0
                geofence_lng = geofence.longitude if geofence.longitude is not None else 0.0
                geofence_rad = geofence.radius_meters if geofence.radius_meters is not None else 0.0
            elif geofence_type == "polygon":
                geofence_vertices = geofence.vertices
                if geofence_vertices:
                    geofence_lat = sum(v.latitude for v in geofence_vertices) / len(geofence_vertices)
                    geofence_lng = sum(v.longitude for v in geofence_vertices) / len(geofence_vertices)
                    geofence_rad = 0.0

            import logging
            logger = logging.getLogger("premises.geofence")
            logger.warning(f"[GEOFENCE DEBUG] type={geofence_type}, lat={geofence_lat}, lng={geofence_lng}, rad={geofence_rad}")
            logger.warning(f"[GEOFENCE DEBUG] vertices count={len(geofence_vertices) if geofence_vertices else 0}")
            if geofence_vertices:
                for i, v in enumerate(geofence_vertices):
                    logger.warning(f"[GEOFENCE DEBUG]   vertex[{i}] lat={v.latitude}, lng={v.longitude}")

        # Policy details
        from app.repositories.geofence_repo import GeofenceRepository
        gf_repo = GeofenceRepository(self.db)
        policy = await gf_repo.get_policy_by_dept(faculty.organization_id, faculty.department_id)
        allowed_outside = policy.allowed_outside_minutes if policy else 0

        # Today's attendance record
        today = datetime.now().astimezone().date()
        tz = datetime.now().astimezone().tzinfo
        day_start = datetime.combine(today, datetime.min.time()).replace(tzinfo=tz)
        rec_stmt = select(AttendanceRecord).where(
            AttendanceRecord.faculty_id == faculty_id,
            AttendanceRecord.attendance_date == today
        )
        rec_res = await self.db.execute(rec_stmt)
        record = rec_res.scalars().first()

        # Campus status determination (query latest LocationEvent today)
        evt_stmt = select(LocationEvent).where(
            LocationEvent.faculty_id == faculty_id,
            LocationEvent.event_time >= day_start
        ).order_by(desc(LocationEvent.event_time))
        evt_res = await self.db.execute(evt_stmt)
        latest_event = evt_res.scalars().first()

        campus_status = "OUTSIDE"
        if latest_event:
            if latest_event.event_type in ["ENTER_CAMPUS", "RETURN_CAMPUS", "CHECK_IN"]:
                campus_status = "INSIDE"

        attendance_status = "NOT_STARTED"
        check_in = None
        check_out = None
        working_dur = "00h 00m"
        reason_req = False
        reason_status = None
        warning_msg = None

        # Determine if current time is past the working hours' end_time
        shift_ended = False
        if policy and policy.end_time:
            tz = datetime.now().astimezone().tzinfo
            policy_end_dt = datetime.combine(today, policy.end_time).replace(tzinfo=tz)
            now_dt = datetime.now(tz)
            if now_dt > policy_end_dt:
                shift_ended = True

        if record:
            # Close attendance record at the end of shift
            if shift_ended and record.last_exit_time is None:
                from app.services.attendance_service import AttendanceService
                attendance_service = AttendanceService(self.db)
                await attendance_service.evaluate_and_close_record(record, policy)
                await self.db.commit()
                await self.db.refresh(record)

            attendance_status = record.status
            if record.first_entry_time:
                check_in = record.first_entry_time.isoformat()
            if record.last_exit_time:
                check_out = record.last_exit_time.isoformat()
            
            # Format working duration
            total_inside = record.total_inside_minutes
            total_outside = record.total_outside_minutes

            if record.first_entry_time is not None and record.last_exit_time is None and not shift_ended:
                # User has checked in today, not checked out, and shift is still active.
                # Compute running time segment since latest event
                if latest_event:
                    tz = latest_event.event_time.tzinfo or timezone.utc
                    now_dt = datetime.now(tz)
                    running_mins = (now_dt - latest_event.event_time).total_seconds() / 60.0
                    
                    if campus_status == "INSIDE":
                        total_inside += running_mins
                    elif campus_status == "OUTSIDE":
                        total_outside += running_mins

            hours = int(round(total_inside)) // 60
            mins = int(round(total_inside)) % 60
            working_dur = f"{hours:02d}h {mins:02d}m"

            # If faculty has already checked out, their day is DONE.
            # Override campus_status to COMPLETED and suppress all warnings.
            if record.last_exit_time is not None:
                campus_status = "COMPLETED"
                warning_msg = None

            # If the shift has ended and they are outside, consider it completed for the day.
            elif shift_ended and campus_status == "OUTSIDE":
                campus_status = "COMPLETED"
                warning_msg = None
                reason_req = False

            # Only warn about being outside if:
            # - They checked IN today (first_entry_time set)
            # - They have NOT checked out yet (last_exit_time is None)
            # - Current campus_status is OUTSIDE (latest event was an exit)
            elif campus_status == "OUTSIDE" and record.first_entry_time is not None:
                warning_msg = "You are currently outside the campus geofence. Please return to resume attendance."
                
                # Check if total outside minutes exceeded allowed
                if total_outside > allowed_outside:
                    reason_req = True

                # Check if they have already submitted a reason for today's record
                reason_stmt = select(ReasonRequest).where(ReasonRequest.attendance_record_id == record.id).order_by(desc(ReasonRequest.created_at))
                reason_res = await self.db.execute(reason_stmt)
                latest_reason = reason_res.scalars().first()
                if latest_reason:
                    reason_status = latest_reason.status
                    reason_req = False  # Submitted, so no longer "required" to submit another
        else:
            if shift_ended:
                attendance_status = "ABSENT"
                warning_msg = None
            elif campus_status == "OUTSIDE":
                warning_msg = "Waiting for campus entry."

        return DashboardSummaryResponse(
            attendance_status=attendance_status,
            check_in_time=check_in,
            check_out_time=check_out,
            working_duration=working_dur,
            campus_status=campus_status,
            geofence_latitude=geofence_lat,
            geofence_longitude=geofence_lng,
            geofence_radius=geofence_rad,
            geofence_type=geofence_type,
            geofence_vertices=geofence_vertices,
            allowed_outside_minutes=allowed_outside,
            reminder_1_minutes=policy.reminder_1_minutes if policy else 0,
            reminder_2_minutes=policy.reminder_2_minutes if policy else 0,
            reminder_3_minutes=policy.reminder_3_minutes if policy else 0,
            evaluation_minutes=policy.evaluation_minutes if policy else 15,
            reason_required=reason_req,
            reason_status=reason_status,
            warning_message=warning_msg
        )

    async def submit_reason_request(self, faculty_id: uuid.UUID, data: ReasonRequestCreate) -> dict:
        today = datetime.now().astimezone().date()
        rec_stmt = select(AttendanceRecord).where(
            AttendanceRecord.faculty_id == faculty_id,
            AttendanceRecord.attendance_date == today
        )
        rec_res = await self.db.execute(rec_stmt)
        record = rec_res.scalars().first()
        if not record:
            raise ValidationException("No attendance record found for today. You must check in at campus first.")

        # Check for existing pending reason
        exist_stmt = select(ReasonRequest).where(
            ReasonRequest.attendance_record_id == record.id,
            ReasonRequest.status == "PENDING"
        )
        exist_res = await self.db.execute(exist_stmt)
        if exist_res.scalars().first():
            raise ConflictException("A reason excusal request is already pending review.")

        new_reason = ReasonRequest(
            organization_id=record.organization_id,
            faculty_id=faculty_id,
            attendance_record_id=record.id,
            reason_type=data.reason_type,
            notes=data.notes,
            submitted_latitude=data.latitude,
            submitted_longitude=data.longitude,
            status="PENDING"
        )
        self.db.add(new_reason)

        # Get faculty details for notification
        from app.models.user import Faculty
        fac_stmt = select(Faculty).where(Faculty.id == faculty_id)
        fac_res = await self.db.execute(fac_stmt)
        faculty = fac_res.scalars().first()

        # Create Admin notification
        if faculty:
            admin_notification = Notification(
                organization_id=record.organization_id,
                faculty_id=faculty_id,
                type="ADMIN_GEOFENCE_EXCUSAL",
                title="Geofence Excusal Request",
                message=f"{faculty.full_name} has submitted a geofence excusal request.",
                recipient_role="ADMIN",
                recipient_id=None
            )
            self.db.add(admin_notification)

        await self.db.commit()
        return {"message": "Excusal reason submitted successfully. Admin review is pending."}

    async def list_notifications(self, faculty_id: uuid.UUID) -> List[NotificationResponse]:
        stmt = (
            select(Notification)
            .where(
                Notification.faculty_id == faculty_id,
                Notification.recipient_role == "FACULTY",
                Notification.recipient_id == faculty_id
            )
            .order_by(desc(Notification.sent_at))
        )
        res = await self.db.execute(stmt)
        notifications = res.scalars().all()
        return [
            NotificationResponse(
                id=n.id,
                type=n.type,
                title=n.title,
                message=n.message,
                sent_at=n.sent_at,
                read_at=n.read_at
            )
            for n in notifications
        ]

    async def mark_notification_as_read(self, faculty_id: uuid.UUID, notification_id: uuid.UUID) -> dict:
        stmt = select(Notification).where(
            Notification.id == notification_id,
            Notification.faculty_id == faculty_id,
            Notification.recipient_role == "FACULTY",
            Notification.recipient_id == faculty_id
        )
        res = await self.db.execute(stmt)
        notif = res.scalars().first()
        if not notif:
            raise NotFoundException("Notification not found.")

        notif.read_at = datetime.utcnow()
        notif.status = "READ"
        self.db.add(notif)
        await self.db.commit()
        return {"message": "Notification marked as read."}

    async def mark_all_notifications_as_read(self, faculty_id: uuid.UUID) -> dict:
        stmt = update(Notification).where(
            Notification.faculty_id == faculty_id,
            Notification.recipient_role == "FACULTY",
            Notification.recipient_id == faculty_id,
            Notification.read_at == None
        ).values(read_at=datetime.utcnow(), status="READ")
        await self.db.execute(stmt)
        await self.db.commit()
        return {"message": "All notifications marked as read."}

    async def list_attendance_history(
        self, faculty_id: uuid.UUID, range_type: str,
        start_date: Optional[date] = None, end_date: Optional[date] = None,
        page: int = 1, limit: int = 10
    ) -> dict:
        today = datetime.now().astimezone().date()
        stmt = select(AttendanceRecord).where(AttendanceRecord.faculty_id == faculty_id)

        # Filters
        if range_type == "today":
            stmt = stmt.where(AttendanceRecord.attendance_date == today)
        elif range_type == "week":
            stmt = stmt.where(AttendanceRecord.attendance_date >= today - timedelta(days=7))
        elif range_type == "month":
            stmt = stmt.where(AttendanceRecord.attendance_date >= today - timedelta(days=30))
        elif range_type == "custom" and start_date and end_date:
            stmt = stmt.where(AttendanceRecord.attendance_date.between(start_date, end_date))

        # Sort desc by date
        stmt = stmt.order_by(desc(AttendanceRecord.attendance_date))

        # Count total
        count_stmt = select(func.count()).select_from(stmt.subquery())
        count_res = await self.db.execute(count_stmt)
        total = count_res.scalar() or 0

        # Pagination
        offset = (page - 1) * limit
        stmt = stmt.offset(offset).limit(limit)
        res = await self.db.execute(stmt)
        records = res.scalars().all()

        record_list = []
        for r in records:
            # Check for reason requests associated
            reason_stmt = select(ReasonRequest).where(ReasonRequest.attendance_record_id == r.id).order_by(desc(ReasonRequest.created_at))
            reason_res = await self.db.execute(reason_stmt)
            reason = reason_res.scalars().first()

            hours = r.total_inside_minutes // 60
            mins = r.total_inside_minutes % 60
            duration_str = f"{hours:02d}h {mins:02d}m"

            record_list.append({
                "id": str(r.id),
                "date": r.attendance_date.isoformat(),
                "check_in": r.first_entry_time.isoformat() if r.first_entry_time else None,
                "check_out": r.last_exit_time.isoformat() if r.last_exit_time else None,
                "working_duration": duration_str,
                "status": r.status,
                "reason_submitted": reason.reason_type if reason else None,
                "admin_decision": reason.status if reason else None
            })

        return {
            "total": total,
            "page": page,
            "limit": limit,
            "records": record_list
        }

    async def list_devices(self, faculty_id: uuid.UUID) -> List[DeviceHistoryResponse]:
        stmt = select(Device).where(Device.faculty_id == faculty_id).order_by(desc(Device.registered_at))
        res = await self.db.execute(stmt)
        devices = res.scalars().all()
        return [
            DeviceHistoryResponse(
                id=d.id,
                device_identifier=d.device_identifier,
                device_model=d.device_model,
                platform=d.platform,
                os_version=d.os_version,
                manufacturer=d.manufacturer,
                registered_at=d.registered_at,
                is_active=d.is_active
            )
            for d in devices
        ]

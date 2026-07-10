from datetime import date, datetime
from typing import List, Optional
import uuid
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.attendance import AttendanceRecord, LocationEvent
from app.models.user import Faculty
from app.repositories.base import BaseRepository


class AttendanceRepository(BaseRepository[AttendanceRecord]):
    def __init__(self, db: AsyncSession):
        super().__init__(AttendanceRecord, db)

    async def get_record(self, faculty_id: uuid.UUID, attendance_date: date) -> Optional[AttendanceRecord]:
        stmt = select(AttendanceRecord).where(
            AttendanceRecord.faculty_id == faculty_id,
            AttendanceRecord.attendance_date == attendance_date
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def create_location_event(self, event_data: dict) -> LocationEvent:
        event = LocationEvent(**event_data)
        self.db.add(event)
        await self.db.flush()
        return event

    async def get_dashboard_summary(self, organization_id: uuid.UUID, target_date: date) -> dict:
        from app.models.organization import Organization
        from app.models.request import FacultyRegistrationRequest, DeviceChangeRequest, ReasonRequest
        from app.models.user import Admin

        # 1. Fetch organization details
        org_stmt = select(Organization).where(Organization.id == organization_id)
        org_res = await self.db.execute(org_stmt)
        organization = org_res.scalars().first()
        org_name = organization.name if organization else "Organization"
        org_code = organization.organization_code if organization else ""
        org_created_at = organization.created_at if organization else datetime.now(timezone.utc)
        org_status = organization.status if organization else "ACTIVE"

        # 1b. Fetch admin email
        admin_stmt = select(Admin.email).where(Admin.organization_id == organization_id).limit(1)
        admin_res = await self.db.execute(admin_stmt)
        admin_email = admin_res.scalar() or ""

        # 2. Total active faculty count
        faculty_stmt = select(Faculty.id).where(
            Faculty.organization_id == organization_id,
            Faculty.status == "ACTIVE"
        )
        faculty_res = await self.db.execute(faculty_stmt)
        active_faculties = faculty_res.scalars().all()
        total_faculty = len(active_faculties)

        # 3. Status counts
        stmt = select(
            AttendanceRecord.status,
            func.count(AttendanceRecord.id)
        ).where(
            AttendanceRecord.organization_id == organization_id,
            AttendanceRecord.attendance_date == target_date
        ).group_by(AttendanceRecord.status)
        
        result = await self.db.execute(stmt)
        status_counts = dict(result.all())

        present = status_counts.get("PRESENT", 0)
        half_day = status_counts.get("HALF_DAY", 0)
        marked_absent = status_counts.get("ABSENT", 0)
        
        total_marked = present + half_day + marked_absent
        unmarked = max(0, total_faculty - total_marked)
        absent = marked_absent + unmarked

        # 4. Outside count calculation (faculty whose latest event today is EXIT_CAMPUS)
        # Query all events today for this organization
        day_start = datetime.combine(target_date, datetime.min.time())
        evt_stmt = select(
            LocationEvent.faculty_id,
            LocationEvent.event_type
        ).where(
            LocationEvent.organization_id == organization_id,
            LocationEvent.event_time >= day_start
        ).order_by(LocationEvent.faculty_id, LocationEvent.event_time.desc())
        
        evt_res = await self.db.execute(evt_stmt)
        events = evt_res.all()
        
        latest_status = {}
        for fac_id, ev_type in events:
            if fac_id not in latest_status:
                latest_status[fac_id] = ev_type
        
        outside_count = sum(1 for ev in latest_status.values() if ev in ["EXIT_CAMPUS", "CHECK_OUT"])

        # 5. Pending requests counts
        reg_stmt = select(func.count()).select_from(FacultyRegistrationRequest).where(
            FacultyRegistrationRequest.organization_id == organization_id,
            FacultyRegistrationRequest.status == "PENDING"
        )
        reg_res = await self.db.execute(reg_stmt)
        reg_count = reg_res.scalar() or 0

        dev_stmt = select(func.count()).select_from(DeviceChangeRequest).where(
            DeviceChangeRequest.organization_id == organization_id,
            DeviceChangeRequest.status == "PENDING"
        )
        dev_res = await self.db.execute(dev_stmt)
        dev_count = dev_res.scalar() or 0

        exc_stmt = select(func.count()).select_from(ReasonRequest).where(
            ReasonRequest.organization_id == organization_id,
            ReasonRequest.status == "PENDING"
        )
        exc_res = await self.db.execute(exc_stmt)
        exc_count = exc_res.scalar() or 0
        
        pending_requests_count = reg_count + dev_count + exc_count

        # 6. Fetch 3 most recent activities
        # registrations
        act_reg_stmt = select(FacultyRegistrationRequest, Faculty).join(
            Faculty, FacultyRegistrationRequest.faculty_id == Faculty.id
        ).where(
            FacultyRegistrationRequest.organization_id == organization_id,
            FacultyRegistrationRequest.status == "PENDING"
        ).order_by(FacultyRegistrationRequest.created_at.desc()).limit(3)
        act_reg_res = await self.db.execute(act_reg_stmt)
        act_regs = act_reg_res.all()

        # swaps
        act_dev_stmt = select(DeviceChangeRequest, Faculty).join(
            Faculty, DeviceChangeRequest.faculty_id == Faculty.id
        ).where(
            DeviceChangeRequest.organization_id == organization_id,
            DeviceChangeRequest.status == "PENDING"
        ).order_by(DeviceChangeRequest.created_at.desc()).limit(3)
        act_dev_res = await self.db.execute(act_dev_stmt)
        act_devs = act_dev_res.all()

        # excusals
        act_exc_stmt = select(ReasonRequest, Faculty).join(
            Faculty, ReasonRequest.faculty_id == Faculty.id
        ).where(
            ReasonRequest.organization_id == organization_id,
            ReasonRequest.status == "PENDING"
        ).order_by(ReasonRequest.submitted_at.desc()).limit(3)
        act_exc_res = await self.db.execute(act_exc_stmt)
        act_excs = act_exc_res.all()

        activities = []
        for req, fac in act_regs:
            activities.append({
                "name": fac.full_name,
                "type": "Faculty Registration",
                "time": req.created_at
            })
        for req, fac in act_devs:
            activities.append({
                "name": fac.full_name,
                "type": "Device Swap Request",
                "time": req.created_at
            })
        for req, fac in act_excs:
            activities.append({
                "name": fac.full_name,
                "type": "Geofence Excusal Request",
                "time": req.submitted_at
            })
            
        activities.sort(key=lambda x: x["time"], reverse=True)
        recent_activities = activities[:3]

        # 7. Count today's manual overrides
        override_stmt = select(func.count(AttendanceRecord.id)).where(
            AttendanceRecord.organization_id == organization_id,
            AttendanceRecord.attendance_date == target_date,
            AttendanceRecord.is_overridden == True
        )
        override_res = await self.db.execute(override_stmt)
        today_manual_overrides_count = override_res.scalar() or 0

        return {
            "present_count": present + half_day,
            "half_day_count": half_day,
            "absent_count": absent,
            "outside_count": outside_count,
            "pending_requests_count": pending_requests_count,
            "total_faculty": total_faculty,
            "org_name": org_name,
            "org_code": org_code,
            "admin_email": admin_email,
            "org_created_at": org_created_at,
            "org_status": org_status,
            "today_manual_overrides_count": today_manual_overrides_count,
            "recent_activities": recent_activities
        }

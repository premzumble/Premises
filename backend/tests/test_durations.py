import pytest
import uuid
from datetime import datetime, date, time, timezone, timedelta
from sqlalchemy import select
from app.database.database import AsyncSessionLocal, init_db
from app.models.organization import Organization, Department
from app.models.user import Faculty
from app.models.geofence import Geofence, AttendancePolicy
from app.models.attendance import AttendanceRecord, LocationEvent
from app.models.request import ReasonRequest
from app.services.attendance_service import AttendanceService
from app.core.constants import AttendanceStatus, LocationEventType

@pytest.mark.asyncio
async def test_timeline_duration_calculations():
    await init_db()

    async with AsyncSessionLocal() as db:
        org = Organization(
            name="Duration Test University",
            organization_code="DURTEST123",
            type="University",
            status="ACTIVE"
        )
        db.add(org)
        await db.flush()

        policy = AttendancePolicy(
            organization_id=org.id,
            allowed_outside_minutes=25,
            start_time=time(9, 0, 0),
            end_time=time(17, 0, 0),
            half_day_cutoff_time=time(14, 30, 0),
            absent_cutoff_time=time(14, 30, 0)
        )
        db.add(policy)

        dept = Department(
            organization_id=org.id,
            name="Physics",
            is_active=True
        )
        db.add(dept)
        await db.flush()

        faculty = Faculty(
            organization_id=org.id,
            department_id=dept.id,
            full_name="Duration Faculty",
            email="dur_fac@durtest.edu",
            password_hash="fakehash",
            status="ACTIVE"
        )
        db.add(faculty)
        await db.flush()

        today = date.today()
        tz = timezone(timedelta(hours=5, minutes=30))
        
        t1 = datetime.combine(today, time(9, 0, 0)).replace(tzinfo=tz)
        t2 = datetime.combine(today, time(12, 0, 0)).replace(tzinfo=tz)
        t3 = datetime.combine(today, time(13, 0, 0)).replace(tzinfo=tz)
        t4 = datetime.combine(today, time(16, 0, 0)).replace(tzinfo=tz)

        record = AttendanceRecord(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_date=today,
            first_entry_time=t1,
            status=AttendanceStatus.PRESENT.value,
            total_inside_minutes=0,
            total_outside_minutes=0
        )
        db.add(record)
        await db.flush()

        e1 = LocationEvent(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_record_id=record.id,
            event_type=LocationEventType.ENTER_CAMPUS.value,
            latitude=20.0,
            longitude=76.0,
            event_time=t1
        )
        e2 = LocationEvent(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_record_id=record.id,
            event_type=LocationEventType.EXIT_CAMPUS.value,
            latitude=20.05,
            longitude=76.05,
            event_time=t2
        )
        e3 = LocationEvent(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_record_id=record.id,
            event_type=LocationEventType.RETURN_CAMPUS.value,
            latitude=20.0,
            longitude=76.0,
            event_time=t3
        )
        e4 = LocationEvent(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_record_id=record.id,
            event_type=LocationEventType.EXIT_CAMPUS.value,
            latitude=20.05,
            longitude=76.05,
            event_time=t4
        )
        db.add_all([e1, e2, e3, e4])
        await db.flush()

        att_service = AttendanceService(db)
        await att_service.recalculate_record_durations(record, policy, end_eval_time=t4)

        assert record.total_inside_minutes == 360
        assert record.total_outside_minutes == 60

        await db.delete(e4)
        await db.delete(e3)
        await db.delete(e2)
        await db.delete(e1)
        await db.delete(record)
        await db.delete(faculty)
        await db.delete(dept)
        await db.delete(policy)
        await db.delete(org)
        await db.commit()

@pytest.mark.asyncio
async def test_auto_close_and_status_evaluation():
    await init_db()

    async with AsyncSessionLocal() as db:
        # Create organization, policy, department, faculty
        org = Organization(name="Evaluation University", organization_code="EVAL123", type="University", status="ACTIVE")
        db.add(org)
        await db.flush()

        policy = AttendancePolicy(
            organization_id=org.id,
            allowed_outside_minutes=25,
            start_time=time(9, 0, 0),
            end_time=time(17, 0, 0),
            half_day_cutoff_time=time(14, 30, 0),
            absent_cutoff_time=time(14, 30, 0)
        )
        db.add(policy)

        dept = Department(organization_id=org.id, name="Chemistry", is_active=True)
        db.add(dept)
        await db.flush()

        faculty = Faculty(
            organization_id=org.id,
            department_id=dept.id,
            full_name="Evaluation Faculty",
            email="eval_fac@evaltest.edu",
            password_hash="fakehash",
            status="ACTIVE"
        )
        db.add(faculty)
        await db.flush()

        today = date.today() - timedelta(days=1)
        tz = timezone(timedelta(hours=5, minutes=30))
        
        t_entry = datetime.combine(today, time(9, 0, 0)).replace(tzinfo=tz)
        t_exit = datetime.combine(today, time(10, 0, 0)).replace(tzinfo=tz)
        t_end = datetime.combine(today, time(17, 0, 0)).replace(tzinfo=tz)

        # ----------------------------------------------------
        # Scenario 1: Exceed limit, no approved reason request
        # ----------------------------------------------------
        record1 = AttendanceRecord(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_date=today,
            first_entry_time=t_entry,
            status=AttendanceStatus.PRESENT.value,
            total_inside_minutes=0,
            total_outside_minutes=0
        )
        db.add(record1)
        await db.flush()

        e_entry = LocationEvent(
            organization_id=org.id, faculty_id=faculty.id, attendance_record_id=record1.id,
            event_type=LocationEventType.ENTER_CAMPUS.value, latitude=20.0, longitude=76.0, event_time=t_entry
        )
        e_exit = LocationEvent(
            organization_id=org.id, faculty_id=faculty.id, attendance_record_id=record1.id,
            event_type=LocationEventType.EXIT_CAMPUS.value, latitude=20.05, longitude=76.05, event_time=t_exit
        )
        db.add_all([e_entry, e_exit])
        await db.flush()

        att_service = AttendanceService(db)
        # Force evaluation & close at t_end (shift end)
        await att_service.evaluate_and_close_record(record1, policy)

        # Asserts:
        assert record1.last_exit_time == t_exit, "Should close at last exit time since they ended shift outside"
        # Inside time: 9am - 10am = 60 mins. Outside time: 10am - 5pm = 420 mins.
        assert record1.total_inside_minutes == 60
        assert record1.total_outside_minutes == 420
        assert record1.status == AttendanceStatus.ABSENT.value, "Status should be ABSENT since they exceeded limit without approved reason"

        # Clean up scenario 1
        await db.delete(e_exit)
        await db.delete(e_entry)
        await db.delete(record1)
        await db.flush()

        # ----------------------------------------------------
        # Scenario 2: Exceed limit, but has APPROVED reason request
        # ----------------------------------------------------
        record2 = AttendanceRecord(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_date=today,
            first_entry_time=t_entry,
            status=AttendanceStatus.PRESENT.value,
            total_inside_minutes=0,
            total_outside_minutes=0
        )
        db.add(record2)
        await db.flush()

        e_entry2 = LocationEvent(
            organization_id=org.id, faculty_id=faculty.id, attendance_record_id=record2.id,
            event_type=LocationEventType.ENTER_CAMPUS.value, latitude=20.0, longitude=76.0, event_time=t_entry
        )
        e_exit2 = LocationEvent(
            organization_id=org.id, faculty_id=faculty.id, attendance_record_id=record2.id,
            event_type=LocationEventType.EXIT_CAMPUS.value, latitude=20.05, longitude=76.05, event_time=t_exit
        )
        db.add_all([e_entry2, e_exit2])
        await db.flush()

        reason = ReasonRequest(
            organization_id=org.id,
            faculty_id=faculty.id,
            attendance_record_id=record2.id,
            reason_type="Official Outing",
            status="APPROVED",
            submitted_at=t_exit
        )
        db.add(reason)
        await db.flush()

        await att_service.evaluate_and_close_record(record2, policy)

        # Asserts:
        assert record2.last_exit_time == t_exit
        assert record2.status == AttendanceStatus.PRESENT.value, "Status should remain PRESENT because there is an approved reason request"

        # Clean up scenario 2 and basic structures
        await db.delete(reason)
        await db.delete(e_exit2)
        await db.delete(e_entry2)
        await db.delete(record2)
        await db.delete(faculty)
        await db.delete(dept)
        await db.delete(policy)
        await db.delete(org)
        await db.commit()

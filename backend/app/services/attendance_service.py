from datetime import date, datetime, timezone, time
import math
import uuid
from typing import List, Optional, Tuple
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.constants import AttendanceStatus, LocationEventType, DevicePlatform
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.geofence import Geofence, AttendancePolicy
from app.models.attendance import AttendanceRecord, LocationEvent
from app.models.request import Device
from app.schemas.attendance import LocationEventCreate
from app.repositories.attendance_repo import AttendanceRepository
from app.repositories.faculty_repo import FacultyRepository
from app.repositories.geofence_repo import GeofenceRepository


class AttendanceService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.attendance_repo = AttendanceRepository(db)
        self.faculty_repo = FacultyRepository(db)
        self.geofence_repo = GeofenceRepository(db)

    @staticmethod
    def calculate_haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        # Earth radius in meters
        R = 6371000.0
        
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)
        
        a = math.sin(delta_phi / 2.0) ** 2 + \
            math.cos(phi1) * math.cos(phi2) * \
            math.sin(delta_lambda / 2.0) ** 2
        c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
        
        return R * c

    @staticmethod
    def _is_point_in_polygon(lat: float, lng: float, polygon: List[Tuple[float, float]]) -> bool:
        num_vertices = len(polygon)
        if num_vertices < 3:
            return False
        inside = False
        p1lat, p1lng = polygon[0]
        for i in range(1, num_vertices + 1):
            p2lat, p2lng = polygon[i % num_vertices]
            if lng > min(p1lng, p2lng):
                if lng <= max(p1lng, p2lng):
                    if lat <= max(p1lat, p2lat):
                        if p1lng != p2lng:
                            xinters = (lng - p1lng) * (p2lat - p1lat) / (p2lng - p1lng) + p1lat
                        if p1lat == p2lat or lat <= xinters:
                            inside = not inside
            p1lat, p1lng = p2lat, p2lng
        return inside

    @staticmethod
    def _distance_point_to_segment_meters(lat_p: float, lng_p: float, lat_a: float, lng_a: float, lat_b: float, lng_b: float) -> float:
        R = 6371000.0
        lat_center_rad = math.radians(lat_p)
        cos_lat = math.cos(lat_center_rad)
        
        # Project relative to P at (0, 0)
        ax = math.radians(lng_a - lng_p) * R * cos_lat
        ay = math.radians(lat_a - lat_p) * R
        bx = math.radians(lng_b - lng_p) * R * cos_lat
        by = math.radians(lat_b - lat_p) * R
        
        dx = bx - ax
        dy = by - ay
        lensq = dx * dx + dy * dy
        
        if lensq == 0.0:
            return math.sqrt(ax * ax + ay * ay)
            
        t = ((0.0 - ax) * dx + (0.0 - ay) * dy) / lensq
        t = max(0.0, min(1.0, t))
        
        cx = ax + t * dx
        cy = ay + t * dy
        return math.sqrt(cx * cx + cy * cy)

    def _distance_point_to_polygon_meters(self, lat_p: float, lng_p: float, polygon: List[Tuple[float, float]]) -> float:
        n = len(polygon)
        if n == 0:
            return float("inf")
        min_dist = float("inf")
        for i in range(n):
            lat_a, lng_a = polygon[i]
            lat_b, lng_b = polygon[(i + 1) % n]
            dist = self._distance_point_to_segment_meters(lat_p, lng_p, lat_a, lng_a, lat_b, lng_b)
            if dist < min_dist:
                min_dist = dist
        return min_dist

    async def check_geofence_status(self, organization_id: uuid.UUID, lat: float, lng: float) -> Tuple[bool, float, Optional[Geofence]]:
        geofences = await self.geofence_repo.get_active_by_org(organization_id)
        if not geofences:
            return True, 0.0, None # If no geofences defined, default to inside for safety

        inside_geofences = []
        outside_distances = []

        for gf in geofences:
            if gf.geofence_type == "circle":
                # Ensure we have valid circle values
                gf_lat = gf.latitude if gf.latitude is not None else 0.0
                gf_lng = gf.longitude if gf.longitude is not None else 0.0
                gf_rad = gf.radius_meters if gf.radius_meters is not None else 0.0
                
                dist = self.calculate_haversine_distance(lat, lng, gf_lat, gf_lng)
                if dist <= gf_rad:
                    inside_geofences.append((dist, gf))
                else:
                    outside_distances.append((dist, gf))
            elif gf.geofence_type == "polygon" and gf.vertices:
                poly_points = [(v.latitude, v.longitude) for v in gf.vertices]
                is_inside = self._is_point_in_polygon(lat, lng, poly_points)
                if is_inside:
                    inside_geofences.append((0.0, gf))
                else:
                    dist = self._distance_point_to_polygon_meters(lat, lng, poly_points)
                    outside_distances.append((dist, gf))
            else:
                # Fallback / active but empty geofence is treated as outside
                outside_distances.append((float("inf"), gf))

        if inside_geofences:
            # If inside any, return the closest matching inside geofence
            inside_geofences.sort(key=lambda x: x[0])
            closest_inside = inside_geofences[0]
            return True, closest_inside[0], closest_inside[1]

        if outside_distances:
            # If outside all, return the closest outside geofence
            outside_distances.sort(key=lambda x: x[0])
            closest_outside = outside_distances[0]
            return False, closest_outside[0], closest_outside[1]

        return False, float("inf"), None

    def get_evaluated_status(self, record: AttendanceRecord, policy: AttendancePolicy) -> str:
        if not record.first_entry_time:
            return AttendanceStatus.ABSENT.value
        
        # Check if first entry time was late
        half_day_cutoff = policy.half_day_cutoff_time if policy else time(14, 30)
        
        # Convert first_entry_time to local timezone before extracting time part
        first_entry_local_time = record.first_entry_time.astimezone().time()
        
        base_status = AttendanceStatus.PRESENT.value if first_entry_local_time < half_day_cutoff else AttendanceStatus.HALF_DAY.value
        return base_status

    async def recalculate_record_durations(self, record: AttendanceRecord, policy: AttendancePolicy, end_eval_time: Optional[datetime] = None) -> None:
        # Fetch all location events for the record sorted by event_time asc
        stmt = select(LocationEvent).where(
            LocationEvent.attendance_record_id == record.id
        ).order_by(LocationEvent.event_time.asc())
        result = await self.db.execute(stmt)
        events = result.scalars().all()

        if not events:
            record.total_inside_minutes = 0
            record.total_outside_minutes = 0
            return

        total_inside = 0.0
        total_outside = 0.0
        state = None # 'INSIDE' or 'OUTSIDE'
        last_time = None

        entry_types = {LocationEventType.ENTER_CAMPUS.value, LocationEventType.RETURN_CAMPUS.value, "CHECK_IN"}
        exit_types = {LocationEventType.EXIT_CAMPUS.value, "CHECK_OUT"}

        for event in events:
            # If we have an end_eval_time and this event is past it, we truncate the timeline at end_eval_time
            if end_eval_time and event.event_time > end_eval_time:
                # Add remainder segment up to end_eval_time
                if last_time and state:
                    delta = (end_eval_time - last_time).total_seconds() / 60.0
                    if state == "INSIDE":
                        total_inside += delta
                    elif state == "OUTSIDE":
                        total_outside += delta
                last_time = end_eval_time
                state = None
                break

            if event.event_type in entry_types:
                if state is None:
                    # Initial entry of the day
                    state = "INSIDE"
                    last_time = event.event_time
                elif state == "OUTSIDE":
                    # Transition from OUTSIDE to INSIDE
                    delta = (event.event_time - last_time).total_seconds() / 60.0
                    total_outside += delta
                    state = "INSIDE"
                    last_time = event.event_time
            elif event.event_type in exit_types:
                if state == "INSIDE":
                    # Transition from INSIDE to OUTSIDE
                    delta = (event.event_time - last_time).total_seconds() / 60.0
                    total_inside += delta
                    state = "OUTSIDE"
                    last_time = event.event_time

        # Handle the remaining time segment if we didn't hit end_eval_time
        if last_time and state:
            eval_limit = end_eval_time or datetime.now(last_time.tzinfo)
            if eval_limit > last_time:
                delta = (eval_limit - last_time).total_seconds() / 60.0
                if state == "INSIDE":
                    total_inside += delta
                elif state == "OUTSIDE":
                    total_outside += delta

        record.total_inside_minutes = int(round(total_inside))
        record.total_outside_minutes = int(round(total_outside))

    async def evaluate_and_close_record(self, record: AttendanceRecord, policy: AttendancePolicy) -> None:
        if not policy or not policy.end_time:
            return

        # Check if record has already been closed/finalized
        if record.last_exit_time is not None:
            return

        # Shift end datetime in the server local timezone
        tz = datetime.now().astimezone().tzinfo
        shift_end_dt = datetime.combine(record.attendance_date, policy.end_time).replace(tzinfo=tz)

        now_dt = datetime.now(tz)
        if now_dt < shift_end_dt:
            # Shift has not ended yet
            return

        # Shift has ended! Let's close and evaluate the record.
        # Fetch the latest location event to see if the user was inside or outside when the shift ended
        stmt = select(LocationEvent).where(
            LocationEvent.attendance_record_id == record.id
        ).order_by(LocationEvent.event_time.desc())
        result = await self.db.execute(stmt)
        latest_event = result.scalars().first()

        entry_types = {LocationEventType.ENTER_CAMPUS.value, LocationEventType.RETURN_CAMPUS.value, "CHECK_IN"}

        # Determine last exit time and campus status at shift end
        if latest_event:
            if latest_event.event_time > shift_end_dt:
                # Find the last event before or equal to shift_end_dt
                stmt_prev = select(LocationEvent).where(
                    LocationEvent.attendance_record_id == record.id,
                    LocationEvent.event_time <= shift_end_dt
                ).order_by(LocationEvent.event_time.desc())
                res_prev = await self.db.execute(stmt_prev)
                event_at_end = res_prev.scalars().first()
                if event_at_end and event_at_end.event_type in entry_types:
                    record.last_exit_time = shift_end_dt
                else:
                    record.last_exit_time = event_at_end.event_time if event_at_end else record.first_entry_time or shift_end_dt
            else:
                # Latest event is before or at shift_end_dt
                if latest_event.event_type in entry_types:
                    record.last_exit_time = shift_end_dt
                else:
                    record.last_exit_time = latest_event.event_time
        else:
            # No events logged
            record.last_exit_time = record.first_entry_time or shift_end_dt

        # Recalculate up to shift_end_dt
        await self.recalculate_record_durations(record, policy, end_eval_time=shift_end_dt)

        # Policy checks for status update
        allowed_outside = policy.allowed_outside_minutes
        
        # Check if they have an approved reason request for today
        from app.models.request import ReasonRequest
        reason_stmt = select(ReasonRequest).where(
            ReasonRequest.attendance_record_id == record.id,
            ReasonRequest.status == "APPROVED"
        )
        reason_res = await self.db.execute(reason_stmt)
        approved_reason = reason_res.scalars().first()

        if record.total_outside_minutes > allowed_outside and not approved_reason:
            record.status = AttendanceStatus.ABSENT.value

        self.db.add(record)

    async def close_all_expired_records(self, organization_id: uuid.UUID) -> None:
        policy = await self.geofence_repo.get_policy_by_org(organization_id)
        if not policy or not policy.end_time:
            return

        today = datetime.now().astimezone().date()
        
        stmt = select(AttendanceRecord).where(
            AttendanceRecord.organization_id == organization_id,
            AttendanceRecord.last_exit_time == None,
            AttendanceRecord.attendance_date <= today
        )
        result = await self.db.execute(stmt)
        records = result.scalars().all()

        for record in records:
            await self.evaluate_and_close_record(record, policy)
        
        await self.db.commit()

    async def register_location_event(self, faculty_id: uuid.UUID, organization_id: uuid.UUID, data: LocationEventCreate) -> LocationEvent:
        # Enforce Hardware Device Lock Binding
        active_device = await self.faculty_repo.get_active_device(faculty_id)
        if active_device and active_device.device_identifier != data.device_identifier:
            raise ForbiddenException("Device verification failed. Attendance reports are bound to your active registered hardware device.")

        # Check if inside/outside geofence
        is_inside, distance, geofence = await self.check_geofence_status(organization_id, data.latitude, data.longitude)

        # Get or create today's record from the local date of the event
        local_event_time = data.event_time.astimezone()
        today = local_event_time.date()
        record = await self.attendance_repo.get_record(faculty_id, today)
        policy = await self.geofence_repo.get_policy_by_org(organization_id)
        
        # Default policy times if none exist
        start_time = policy.start_time if policy else time(9, 0)
        half_day_cutoff = policy.half_day_cutoff_time if policy else time(14, 30)

        now_time = local_event_time.time()

        if not record:
            # First check-in of the day
            initial_status = AttendanceStatus.PRESENT.value if now_time < half_day_cutoff else AttendanceStatus.HALF_DAY.value
            record_data = {
                "organization_id": organization_id,
                "faculty_id": faculty_id,
                "attendance_date": today,
                "first_entry_time": data.event_time if is_inside else None,
                "last_exit_time": None if is_inside else data.event_time,
                "status": initial_status if is_inside else AttendanceStatus.ABSENT.value,
                "total_inside_minutes": 0,
                "total_outside_minutes": 0,
            }
            record = await self.attendance_repo.create(obj_in_data=record_data)
        else:
            # Update existing record parameters
            if is_inside:
                if not record.first_entry_time:
                    record.first_entry_time = data.event_time
                    record.status = AttendanceStatus.PRESENT.value if now_time < half_day_cutoff else AttendanceStatus.HALF_DAY.value
            self.db.add(record)

        # Log Location Event
        event_type = data.event_type.value
        # Override event type based on actual Haversine geofence calculation
        if is_inside:
            event_type = LocationEventType.ENTER_CAMPUS.value if record.first_entry_time == data.event_time else LocationEventType.RETURN_CAMPUS.value
        else:
            event_type = LocationEventType.EXIT_CAMPUS.value

        event_data = {
            "organization_id": organization_id,
            "faculty_id": faculty_id,
            "attendance_record_id": record.id,
            "event_type": event_type,
            "latitude": data.latitude,
            "longitude": data.longitude,
            "event_time": data.event_time,
        }
        event = await self.attendance_repo.create_location_event(event_data)
        
        # Recalculate durations and status using all logged events
        if policy:
            await self.recalculate_record_durations(record, policy)
            allowed_outside = policy.allowed_outside_minutes
            from app.models.request import ReasonRequest
            reason_stmt = select(ReasonRequest).where(
                ReasonRequest.attendance_record_id == record.id,
                ReasonRequest.status == "APPROVED"
            )
            reason_res = await self.db.execute(reason_stmt)
            approved_reason = reason_res.scalars().first()

            base_status = self.get_evaluated_status(record, policy)
            if record.total_outside_minutes > allowed_outside and not approved_reason:
                record.status = AttendanceStatus.ABSENT.value
            else:
                record.status = base_status
            
            self.db.add(record)

        # Create check-in or check-out notification for faculty
        from app.models.notification import Notification
        if event_type in [LocationEventType.ENTER_CAMPUS.value, LocationEventType.RETURN_CAMPUS.value]:
            notif = Notification(
                organization_id=organization_id,
                faculty_id=faculty_id,
                type="CHECK_IN_SUCCESS",
                title="Check-In Successful",
                message="Attendance registered successfully.",
                recipient_role="FACULTY",
                recipient_id=faculty_id
            )
            self.db.add(notif)
        elif event_type == LocationEventType.EXIT_CAMPUS.value:
            hours = record.total_inside_minutes // 60
            mins = record.total_inside_minutes % 60
            working_dur = f"{hours:02d}h {mins:02d}m"
            notif = Notification(
                organization_id=organization_id,
                faculty_id=faculty_id,
                type="CHECK_OUT_SUCCESS",
                title="Check-Out Successful",
                message=f"Check-Out recorded. Working duration: {working_dur}.",
                recipient_role="FACULTY",
                recipient_id=faculty_id
            )
            self.db.add(notif)

        await self.db.commit()
        await self.db.refresh(event)
        return event

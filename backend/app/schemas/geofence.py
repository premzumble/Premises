from typing import Optional, List
from datetime import datetime, time
import uuid
from pydantic import BaseModel, Field, model_validator

# ─── Geometric Validation Helpers ──────────────────────────────────────────

def _orientation(p, q, r):
    val = (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])
    if abs(val) < 1e-9:
        return 0
    return 1 if val > 0 else 2

def _on_segment(p, q, r):
    if (q[0] <= max(p[0], r[0]) and q[0] >= min(p[0], r[0]) and
        q[1] <= max(p[1], r[1]) and q[1] >= min(p[1], r[1])):
        return True
    return False

def _do_segments_intersect(p1, q1, p2, q2):
    o1 = _orientation(p1, q1, p2)
    o2 = _orientation(p1, q1, q2)
    o3 = _orientation(p2, q2, p1)
    o4 = _orientation(p2, q2, q1)

    # General case
    if o1 != o2 and o3 != o4:
        return True

    # Special Cases
    if o1 == 0 and _on_segment(p1, p2, q1):
        return True
    if o2 == 0 and _on_segment(p1, q2, q1):
        return True
    if o3 == 0 and _on_segment(p2, p1, q2):
        return True
    if o4 == 0 and _on_segment(p2, q1, q2):
        return True

    return False

def _is_self_intersecting(vertices: List[tuple]) -> bool:
    n = len(vertices)
    if n < 4:
        return False

    edges = []
    for i in range(n):
        edges.append((vertices[i], vertices[(i + 1) % n]))

    for i in range(n):
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            
            p1, q1 = edges[i]
            p2, q2 = edges[j]
            
            # Non-consecutive edges should not intersect
            if _do_segments_intersect(p1, q1, p2, q2):
                return True
    return False

def _calculate_polygon_area(vertices: List[tuple]) -> float:
    n = len(vertices)
    if n < 3:
        return 0.0
    
    lat_center = sum(v[0] for v in vertices) / n
    lng_center = sum(v[1] for v in vertices) / n
    
    R = 6371000.0
    lat_center_rad = math.radians(lat_center)
    cos_lat = math.cos(lat_center_rad)
    
    import math as pymath
    projected = []
    for lat, lng in vertices:
        x = pymath.radians(lng) * R * cos_lat
        y = pymath.radians(lat) * R
        projected.append((x, y))
        
    area = 0.0
    for i in range(n):
        x1, y1 = projected[i]
        x2, y2 = projected[(i + 1) % n]
        area += x1 * y2 - x2 * y1
        
    return abs(area) * 0.5

# ─── Schemas ───────────────────────────────────────────────────────────────

import math

class GeofenceVertexBase(BaseModel):
    latitude: float
    longitude: float

class GeofenceVertexResponse(GeofenceVertexBase):
    id: uuid.UUID
    geofence_id: uuid.UUID

    class Config:
        from_attributes = True

class GeofenceBase(BaseModel):
    name: str
    geofence_type: str = "circle"
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    radius_meters: Optional[float] = None
    vertices: Optional[List[GeofenceVertexBase]] = None
    is_active: bool = True

    @model_validator(mode="after")
    def validate_geofence(self) -> 'GeofenceBase':
        if self.geofence_type == "circle":
            if self.latitude is None or self.longitude is None or self.radius_meters is None:
                raise ValueError("latitude, longitude, and radius_meters are required for circle geofences.")
            if self.radius_meters < 10.0 or self.radius_meters > 10000.0:
                raise ValueError("Circle radius must be between 10m and 10,000m.")
        elif self.geofence_type == "polygon":
            if not self.vertices or len(self.vertices) < 3:
                raise ValueError("A polygon geofence must have at least 3 vertices.")
            
            points = [(v.latitude, v.longitude) for v in self.vertices]
            if _is_self_intersecting(points):
                raise ValueError("Self-intersecting polygon boundaries are invalid. Edges cannot cross.")
                
            area = _calculate_polygon_area(points)
            if area < 100.0:
                raise ValueError(f"Geofence area is too small ({area:.1f} m²). Must be at least 100 m².")
            if area > 100000000.0:
                raise ValueError(f"Geofence area is too large ({area/1e6:.1f} km²). Must be under 100 km².")
        else:
            raise ValueError(f"Unsupported geofence type: {self.geofence_type}")
        return self


class GeofenceCreate(GeofenceBase):
    pass


class GeofenceResponse(GeofenceBase):
    id: uuid.UUID
    organization_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    updated_by: Optional[str] = None
    vertices: Optional[List[GeofenceVertexResponse]] = None

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

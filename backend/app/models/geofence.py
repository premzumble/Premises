from datetime import datetime, time
import uuid
from sqlalchemy import String, Text, Boolean, ForeignKey, DateTime, UniqueConstraint, Double, Integer, Time, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


from typing import Optional, List

class Geofence(Base):
    __tablename__ = "geofences"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    geofence_type: Mapped[str] = mapped_column(String(50), nullable=False, default="circle")
    latitude: Mapped[Optional[float]] = mapped_column(Double, nullable=True)
    longitude: Mapped[Optional[float]] = mapped_column(Double, nullable=True)
    radius_meters: Mapped[Optional[float]] = mapped_column(Double, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)
    updated_by: Mapped[str] = mapped_column(String(255), nullable=True)

    organization = relationship("Organization")
    vertices = relationship(
        "GeofenceVertex",
        back_populates="geofence",
        order_by="GeofenceVertex.sequence_order",
        cascade="all, delete-orphan",
        lazy="selectin"
    )


class GeofenceVertex(Base):
    __tablename__ = "geofence_vertices"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    geofence_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("geofences.id", ondelete="CASCADE"), nullable=False)
    sequence_order: Mapped[int] = mapped_column(Integer, nullable=False)
    latitude: Mapped[float] = mapped_column(Double, nullable=False)
    longitude: Mapped[float] = mapped_column(Double, nullable=False)

    geofence = relationship("Geofence", back_populates="vertices")


class AttendancePolicy(Base):
    __tablename__ = "attendance_policies"
    __table_args__ = (
        UniqueConstraint("organization_id", "department_id", name="uniq_org_dept_policy"),
        UniqueConstraint("organization_id", "id", name="uniq_org_policy_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    department_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid, ForeignKey("departments.id", ondelete="CASCADE"), nullable=True)
    allowed_outside_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reminder_1_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reminder_2_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reminder_3_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    evaluation_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=15)
    start_time: Mapped[time] = mapped_column(Time, nullable=False, default=time(9, 0, 0))
    end_time: Mapped[time] = mapped_column(Time, nullable=False, default=time(17, 0, 0))
    half_day_cutoff_time: Mapped[time] = mapped_column(Time, nullable=False, default=time(14, 30, 0))
    absent_cutoff_time: Mapped[time] = mapped_column(Time, nullable=False, default=time(14, 30, 0))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")

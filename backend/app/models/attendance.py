from datetime import datetime, date
import uuid
from sqlalchemy import String, ForeignKey, DateTime, UniqueConstraint, ForeignKeyConstraint, Double, Integer, Date, Uuid, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


class AttendanceRecord(Base):
    __tablename__ = "attendance_records"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_record_faculty",
            ondelete="CASCADE",
        ),
        UniqueConstraint("faculty_id", "attendance_date", name="uniq_faculty_attendance_date"),
        UniqueConstraint("organization_id", "id", name="uniq_org_record_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    attendance_date: Mapped[date] = mapped_column(Date, nullable=False)
    first_entry_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    last_exit_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="ABSENT")
    total_inside_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_outside_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")
    events = relationship("LocationEvent", back_populates="attendance_record", cascade="all, delete-orphan")


class LocationEvent(Base):
    __tablename__ = "location_events"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_event_faculty",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["organization_id", "attendance_record_id"],
            ["attendance_records.organization_id", "attendance_records.id"],
            name="fk_event_record",
            ondelete="CASCADE",
        ),
        # Performance indexes for per-faculty timeline lookups
        Index("ix_location_events_faculty_time", "faculty_id", "event_time"),
        Index("ix_location_events_org_id", "organization_id"),
        Index("ix_location_events_event_time", "event_time"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    attendance_record_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    event_type: Mapped[str] = mapped_column(String(20), nullable=False)
    latitude: Mapped[float] = mapped_column(Double, nullable=False)
    longitude: Mapped[float] = mapped_column(Double, nullable=False)
    event_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    organization = relationship("Organization")
    attendance_record = relationship("AttendanceRecord", back_populates="events")

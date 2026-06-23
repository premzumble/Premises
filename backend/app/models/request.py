from datetime import datetime
import uuid
from typing import Optional
from sqlalchemy import String, Text, Boolean, ForeignKey, DateTime, UniqueConstraint, ForeignKeyConstraint, Double, Uuid, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_device_faculty",
            ondelete="CASCADE",
        ),
        # Performance index: look up all devices for a given faculty quickly
        Index("ix_devices_faculty_id", "faculty_id"),
        Index("ix_devices_org_id", "organization_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    device_identifier: Mapped[str] = mapped_column(Text, nullable=False)
    device_model: Mapped[str] = mapped_column(Text, nullable=True)
    platform: Mapped[str] = mapped_column(String(10), nullable=False)
    os_version: Mapped[str] = mapped_column(Text, nullable=True)
    manufacturer: Mapped[str] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    registered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    faculty = relationship("Faculty", back_populates="devices")


class ReasonRequest(Base):
    __tablename__ = "reason_requests"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_reason_faculty",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["organization_id", "attendance_record_id"],
            ["attendance_records.organization_id", "attendance_records.id"],
            name="fk_reason_record",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["reviewed_by"],
            ["admins.id"],
            name="fk_reason_reviewer",
            ondelete="SET NULL",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    attendance_record_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    reason_type: Mapped[str] = mapped_column(String(50), nullable=False)
    notes: Mapped[str] = mapped_column(Text, nullable=True)
    submitted_latitude: Mapped[float] = mapped_column(Double, nullable=True)
    submitted_longitude: Mapped[float] = mapped_column(Double, nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")
    reviewed_by: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    rejection_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")
    faculty = relationship("Faculty")
    attendance_record = relationship("AttendanceRecord")
    reviewer = relationship("Admin")


class FacultyRegistrationRequest(Base):
    __tablename__ = "faculty_registration_requests"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_reg_faculty",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["reviewed_by"],
            ["admins.id"],
            name="fk_reg_reviewer",
            ondelete="SET NULL",
        ),
        UniqueConstraint("organization_id", "status", "id", name="uniq_faculty_reg_requests_org"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")
    reviewed_by: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    rejection_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")
    faculty = relationship("Faculty")
    reviewer = relationship("Admin")


class DeviceChangeRequest(Base):
    __tablename__ = "device_change_requests"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_dev_faculty",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["old_device_id"],
            ["devices.id"],
            name="fk_dev_old_device",
            ondelete="SET NULL",
        ),
        ForeignKeyConstraint(
            ["reviewed_by"],
            ["admins.id"],
            name="fk_dev_reviewer",
            ondelete="SET NULL",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    old_device_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    new_device_identifier: Mapped[str] = mapped_column(Text, nullable=False)
    new_device_model: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")
    reviewed_by: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    rejection_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")
    faculty = relationship("Faculty")
    old_device = relationship("Device")
    reviewer = relationship("Admin")

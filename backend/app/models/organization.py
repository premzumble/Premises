from datetime import datetime
import uuid
from sqlalchemy import String, Text, Boolean, ForeignKey, DateTime, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


class Organization(Base):
    __tablename__ = "organizations"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    organization_code: Mapped[str] = mapped_column(String(50), nullable=False, unique=True)
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    domain: Mapped[str] = mapped_column(Text, nullable=True, unique=True)
    logo_url: Mapped[str] = mapped_column(Text, nullable=True)
    website: Mapped[str] = mapped_column(Text, nullable=True)
    address: Mapped[str] = mapped_column(Text, nullable=True)
    contact_number: Mapped[str] = mapped_column(String(30), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="ACTIVE")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    settings = relationship("OrganizationSettings", back_populates="organization", uselist=False, cascade="all, delete-orphan")
    departments = relationship("Department", back_populates="organization", cascade="all, delete-orphan")


class OrganizationSettings(Base):
    __tablename__ = "organization_settings"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False, unique=True)
    faculty_registration_mode: Mapped[str] = mapped_column(String(20), nullable=False, default="ADMIN_APPROVAL")
    allow_external_emails: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    
    # Security Settings
    require_mfa: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    restrict_devices: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    log_admin_actions: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    # Notification Settings
    notify_on_device_change: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notify_on_exit_violation: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notify_on_approvals: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization", back_populates="settings")


class Department(Base):
    __tablename__ = "departments"
    __table_args__ = (
        UniqueConstraint("organization_id", "name", name="uniq_org_dept_name"),
        UniqueConstraint("organization_id", "id", name="uniq_org_dept_id"),
    )



    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization", back_populates="departments")
    policies = relationship("AttendancePolicy", backref="department", cascade="all, delete-orphan")

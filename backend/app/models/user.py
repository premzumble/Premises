from datetime import datetime
import uuid
from sqlalchemy import String, Text, ForeignKey, DateTime, UniqueConstraint, ForeignKeyConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


class Admin(Base):
    __tablename__ = "admins"
    __table_args__ = (
        UniqueConstraint("organization_id", "id", name="uniq_org_admin_id"),
    )



    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    full_name: Mapped[str] = mapped_column(Text, nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="ACTIVE")
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")


class Faculty(Base):
    __tablename__ = "faculty"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "department_id"],
            ["departments.organization_id", "departments.id"],
            name="fk_faculty_department",
            ondelete="SET NULL",
        ),
        UniqueConstraint("organization_id", "id", name="uniq_org_faculty_id"),
    )



    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    department_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    full_name: Mapped[str] = mapped_column(Text, nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(255), nullable=False, default="PENDING_APPROVAL")
    phone_number: Mapped[str] = mapped_column(String(30), nullable=True)
    emergency_contact: Mapped[str] = mapped_column(String(255), nullable=True)
    profile_photo_url: Mapped[str] = mapped_column(Text, nullable=True)
    registered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    organization = relationship("Organization")
    department = relationship("Department")
    devices = relationship("Device", back_populates="faculty", cascade="all, delete-orphan")

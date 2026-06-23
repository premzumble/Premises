from datetime import datetime
import uuid
from sqlalchemy import String, Text, ForeignKey, DateTime, ForeignKeyConstraint, JSON, Uuid, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"
    __table_args__ = (
        # Composite index for org-scoped chronological lookups (the primary admin query pattern)
        Index("ix_audit_logs_org_created", "organization_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(20), nullable=False)  # ADMIN, FACULTY, SYSTEM
    actor_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)  # Polymorphic reference
    action: Mapped[str] = mapped_column(Text, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    old_value: Mapped[dict] = mapped_column(JSON, nullable=True)
    new_value: Mapped[dict] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    organization = relationship("Organization")


class PolicyChangeHistory(Base):
    __tablename__ = "policy_change_history"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "policy_id"],
            ["attendance_policies.organization_id", "attendance_policies.id"],
            name="fk_hist_policy",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["organization_id", "changed_by"],
            ["admins.organization_id", "admins.id"],
            name="fk_hist_admin",
            ondelete="SET NULL",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    policy_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    changed_by: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    field_name: Mapped[str] = mapped_column(Text, nullable=False)
    old_value: Mapped[str] = mapped_column(Text, nullable=True)
    new_value: Mapped[str] = mapped_column(Text, nullable=True)
    changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    organization = relationship("Organization")
    admin = relationship("Admin")

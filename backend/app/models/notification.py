from datetime import datetime
import uuid
from sqlalchemy import String, Text, ForeignKey, DateTime, ForeignKeyConstraint, Uuid, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database.database import Base


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        ForeignKeyConstraint(
            ["organization_id", "faculty_id"],
            ["faculty.organization_id", "faculty.id"],
            name="fk_notification_faculty",
            ondelete="CASCADE",
        ),
        # Performance indexes for notification lookups
        Index("ix_notifications_recipient_id", "recipient_id"),
        Index("ix_notifications_org_role", "organization_id", "recipient_role"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False)
    faculty_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    type: Mapped[str] = mapped_column(String(30), nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    read_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="SENT")
    recipient_role: Mapped[str] = mapped_column(String(20), nullable=True)
    recipient_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    organization = relationship("Organization")
    faculty = relationship("Faculty")

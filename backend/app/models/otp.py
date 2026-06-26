import uuid
from datetime import datetime, timedelta, timezone
from sqlalchemy import String, Text, DateTime, Integer, Boolean, Uuid
from sqlalchemy.orm import Mapped, mapped_column
from app.database.database import Base


class OtpVerification(Base):
    __tablename__ = "otp_verifications"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    otp: Mapped[str] = mapped_column(String(6), nullable=False)
    purpose: Mapped[str] = mapped_column(String(20), nullable=False, default="REGISTRATION") # REGISTRATION, PASSWORD_RESET

    # Registration data (only for registration flow)
    registration_data: Mapped[str] = mapped_column(Text, nullable=True)

    # Security tracking
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    used_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)

    @property
    def is_expired(self) -> bool:
        return datetime.now(timezone.utc) > self.expires_at

import uuid
from datetime import datetime
from sqlalchemy import String, Text, DateTime, Uuid
from sqlalchemy.orm import Mapped, mapped_column
from app.database.database import Base


class OtpVerification(Base):
    __tablename__ = "otp_verifications"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    otp: Mapped[str] = mapped_column(String(6), nullable=False)
    registration_data: Mapped[str] = mapped_column(Text, nullable=False)  # Serialized JSON registration details
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

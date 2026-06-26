from fastapi import APIRouter, Depends
from app.schemas.base import StandardResponse
from app.services.email_service import EmailService

router = APIRouter()

@router.get("/email", response_model=StandardResponse[dict])
async def check_email_config():
    """Verify if the SMTP configuration is working correctly."""
    is_valid = EmailService.verify_smtp_config()
    if is_valid:
        return StandardResponse(
            success=True,
            message="SMTP configuration is valid and reachable.",
            data={"status": "online"}
        )
    else:
        return StandardResponse(
            success=False,
            message="SMTP configuration is invalid or unreachable. Please check your .env settings.",
            data={"status": "offline"}
        )

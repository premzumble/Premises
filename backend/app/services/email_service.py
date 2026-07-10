import logging
import smtplib
import asyncio
import sys
import os
import uuid
from typing import Optional
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from jinja2 import Environment, FileSystemLoader, select_autoescape
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timezone
from app.core.config import settings
from app.models.otp import EmailLog

logger = logging.getLogger("app.email_service")

# Setup Jinja2 environment
TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"
jinja_env = Environment(
    loader=FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=select_autoescape(['html', 'xml'])
)


def _send_smtp_sync(msg: MIMEMultipart, host: str, port: int, username: str, password: str, tls: bool) -> bool:
    """Synchronous SMTP delivery helper intended to run in a thread pool."""
    if port == 465:
        server = smtplib.SMTP_SSL(host, port, timeout=10)
    else:
        server = smtplib.SMTP(host, port, timeout=10)
        server.ehlo()
        if tls:
            server.starttls()
            server.ehlo()

    try:
        server.login(username, password)
        server.send_message(msg)
        return True
    finally:
        try:
            server.quit()
        except Exception:
            pass


class EmailService:
    @staticmethod
    def _render_template(template_name: str, **kwargs) -> str:
        template = jinja_env.get_template(template_name)
        return template.render(**kwargs)

    @staticmethod
    async def send_otp_email(
        db: AsyncSession,
        email: str,
        otp: str,
        purpose: str = "REGISTRATION",
        organization_id: Optional[uuid.UUID] = None,
        user_id: Optional[uuid.UUID] = None,
        request_id: Optional[uuid.UUID] = None
    ) -> bool:
        """
        Sends a professional OTP email with strict idempotency validation and loop protection.
        """
        # 1. Enforce strict database-backed idempotency
        idempotency_key = f"otp_{email.strip().lower()}_{purpose}_{otp}"
        
        # Check if already processed
        stmt = select(EmailLog).where(EmailLog.idempotency_key == idempotency_key)
        res = await db.execute(stmt)
        existing = res.scalars().first()
        
        if existing and existing.status == "SENT":
            logger.info(f"[EMAIL] Skip duplicate email dispatch for key: {idempotency_key}")
            return True

        if not existing:
            log_record = EmailLog(
                organization_id=organization_id,
                user_id=user_id,
                recipient=email,
                email_type=f"OTP_{purpose}",
                idempotency_key=idempotency_key,
                status="PENDING",
                attempts=1
            )
            db.add(log_record)
            try:
                await db.commit()
            except Exception as e:
                await db.rollback()
                logger.info(f"[EMAIL] Concurrent conflict detected, skipping duplicate: {e}")
                return True
        else:
            log_record = existing
            log_record.attempts += 1
            log_record.status = "PENDING"
            db.add(log_record)
            await db.commit()

        # 2. Check if running inside test runner (pytest)
        is_testing = "pytest" in sys.modules or os.environ.get("TESTING") == "true"
        
        subject = "Premises - Verification Code"
        if purpose == "PASSWORD_RESET":
            subject = "Premises - Password Reset Verification Code"
        elif purpose == "DEVICE_BINDING":
            subject = "Premises - Device Verification Code"

        success = False
        error_msg = None

        if is_testing:
            logger.info(f"[EMAIL] [TEST MOCK] Bypassing real SMTP send. Recipient={email}, Type=OTP_{purpose}, Code={otp}")
            success = True
        else:
            if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
                logger.warning(f"[EMAIL] SMTP credentials not configured. OTP for {email}: {otp}")
                error_msg = "SMTP credentials not configured"
            else:
                try:
                    # Render HTML template
                    html_content = EmailService._render_template("otp_email.html", otp=otp, subject=subject)

                    # Create message
                    msg = MIMEMultipart('alternative')
                    msg['Subject'] = subject
                    msg['From'] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_FROM_EMAIL}>"
                    msg['To'] = email

                    msg.attach(MIMEText(f"Your verification code is: {otp}", 'plain'))
                    msg.attach(MIMEText(html_content, 'html'))

                    # Run synchronous SMTP connection in thread pool
                    success = await asyncio.to_thread(
                        _send_smtp_sync,
                        msg,
                        settings.SMTP_HOST,
                        settings.SMTP_PORT,
                        settings.SMTP_USERNAME,
                        settings.SMTP_PASSWORD,
                        settings.SMTP_TLS
                    )
                    if not success:
                        error_msg = "SMTP transaction failed"
                except Exception as e:
                    error_msg = str(e)
                    logger.error(f"[EMAIL] Exception occurred during SMTP dispatch to {email}: {e}")

        # 3. Update execution results to database and logging systems
        log_record.status = "SENT" if success else "FAILED"
        log_record.error_message = error_msg
        if success:
            log_record.sent_at = datetime.now(timezone.utc)
        
        db.add(log_record)
        await db.commit()

        logger.info(
            f"[EMAIL LOG] Type=OTP_{purpose}, Recipient={email}, Status={log_record.status}, "
            f"OrgID={organization_id}, UserID={user_id}, Attempts={log_record.attempts}, Timestamp={datetime.now(timezone.utc).isoformat()}"
        )
        return success

    @staticmethod
    async def send_welcome_email(
        db: AsyncSession,
        email: str,
        admin_name: str,
        org_name: str,
        org_code: str,
        organization_id: Optional[uuid.UUID] = None,
        user_id: Optional[uuid.UUID] = None,
        request_id: Optional[uuid.UUID] = None
    ) -> bool:
        """
        Sends a professional welcome email with strict database-backed idempotency validation.
        """
        # 1. Enforce database-backed idempotency
        idempotency_key = f"welcome_{email.strip().lower()}_{org_code}"

        stmt = select(EmailLog).where(EmailLog.idempotency_key == idempotency_key)
        res = await db.execute(stmt)
        existing = res.scalars().first()

        if existing and existing.status == "SENT":
            logger.info(f"[EMAIL] Skip duplicate welcome email dispatch for key: {idempotency_key}")
            return True

        if not existing:
            log_record = EmailLog(
                organization_id=organization_id,
                user_id=user_id,
                recipient=email,
                email_type="WELCOME",
                idempotency_key=idempotency_key,
                status="PENDING",
                attempts=1
            )
            db.add(log_record)
            try:
                await db.commit()
            except Exception as e:
                await db.rollback()
                logger.info(f"[EMAIL] Concurrent conflict detected on welcome email, skipping: {e}")
                return True
        else:
            log_record = existing
            log_record.attempts += 1
            log_record.status = "PENDING"
            db.add(log_record)
            await db.commit()

        # 2. Check if running inside test runner
        is_testing = "pytest" in sys.modules or os.environ.get("TESTING") == "true"
        
        subject = "Premises - Organization Created Successfully"
        success = False
        error_msg = None

        if is_testing:
            logger.info(f"[EMAIL] [TEST MOCK] Bypassing welcome email to {email} (Org={org_name}, Code={org_code})")
            success = True
        else:
            if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
                logger.warning(f"[EMAIL] SMTP credentials not configured. Org Code for {email}: {org_code}")
                error_msg = "SMTP credentials not configured"
            else:
                try:
                    # Render HTML template
                    html_content = EmailService._render_template(
                        "welcome_email.html",
                        admin_name=admin_name,
                        org_name=org_name,
                        org_code=org_code,
                        subject=subject
                    )

                    # Create message
                    msg = MIMEMultipart('alternative')
                    msg['Subject'] = subject
                    msg['From'] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_FROM_EMAIL}>"
                    msg['To'] = email

                    plain_text = (
                        f"Congratulations! Your organization {org_name} has been successfully registered on Premises.\n\n"
                        f"Your Organization Code is: {org_code}\n\n"
                        "This code is required when faculty members register to join your workspace. Please keep it secure.\n\n"
                        "You can now log in to your admin dashboard to manage your workspace."
                    )
                    msg.attach(MIMEText(plain_text, 'plain'))
                    msg.attach(MIMEText(html_content, 'html'))

                    # Run SMTP synchronous operation in thread pool
                    success = await asyncio.to_thread(
                        _send_smtp_sync,
                        msg,
                        settings.SMTP_HOST,
                        settings.SMTP_PORT,
                        settings.SMTP_USERNAME,
                        settings.SMTP_PASSWORD,
                        settings.SMTP_TLS
                    )
                    if not success:
                        error_msg = "SMTP transaction failed"
                except Exception as e:
                    error_msg = str(e)
                    logger.error(f"[EMAIL] Exception occurred during welcome SMTP dispatch to {email}: {e}")

        # 3. Update database results
        log_record.status = "SENT" if success else "FAILED"
        log_record.error_message = error_msg
        if success:
            log_record.sent_at = datetime.now(timezone.utc)

        db.add(log_record)
        await db.commit()

        logger.info(
            f"[EMAIL LOG] Type=WELCOME, Recipient={email}, Status={log_record.status}, "
            f"OrgID={organization_id}, UserID={user_id}, Attempts={log_record.attempts}, Timestamp={datetime.now(timezone.utc).isoformat()}"
        )
        return success

    @staticmethod
    async def send_override_email(
        db: AsyncSession,
        email: str,
        faculty_name: str,
        attendance_date: str,
        override_status: str,
        override_reason: str,
        override_remarks: Optional[str] = None,
        organization_id: Optional[uuid.UUID] = None,
        user_id: Optional[uuid.UUID] = None
    ) -> bool:
        """
        Sends an email notification when an administrator manually overrides a faculty attendance record.
        """
        idempotency_key = f"override_{email.strip().lower()}_{attendance_date}_{override_status}"

        stmt = select(EmailLog).where(EmailLog.idempotency_key == idempotency_key)
        res = await db.execute(stmt)
        existing = res.scalars().first()

        if existing and existing.status == "SENT":
            return True

        if not existing:
            log_record = EmailLog(
                organization_id=organization_id,
                user_id=user_id,
                recipient=email,
                email_type="ATTENDANCE_OVERRIDE",
                idempotency_key=idempotency_key,
                status="PENDING",
                attempts=1
            )
            db.add(log_record)
            await db.commit()
        else:
            log_record = existing
            log_record.attempts += 1
            db.add(log_record)
            await db.commit()

        is_testing = "pytest" in sys.modules or os.environ.get("TESTING") == "true"
        subject = "Premises - Attendance Record Updated"
        success = False
        error_msg = None

        if is_testing:
            success = True
        else:
            if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
                error_msg = "SMTP credentials not configured"
            else:
                try:
                    html_content = EmailService._render_template(
                        "override_email.html",
                        date=attendance_date,
                        status=override_status,
                        reason=override_reason,
                        remarks=override_remarks
                    )

                    msg = MIMEMultipart('alternative')
                    msg['Subject'] = subject
                    msg['From'] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_FROM_EMAIL}>"
                    msg['To'] = email

                    plain_text = f"Your attendance for {attendance_date} has been updated to {override_status}."
                    msg.attach(MIMEText(plain_text, 'plain'))
                    msg.attach(MIMEText(html_content, 'html'))

                    success = await asyncio.to_thread(
                        _send_smtp_sync,
                        msg,
                        settings.SMTP_HOST,
                        settings.SMTP_PORT,
                        settings.SMTP_USERNAME,
                        settings.SMTP_PASSWORD,
                        settings.SMTP_TLS
                    )
                except Exception as e:
                    error_msg = str(e)

        log_record.status = "SENT" if success else "FAILED"
        log_record.error_message = error_msg
        if success:
            log_record.sent_at = datetime.now(timezone.utc)

        db.add(log_record)
        await db.commit()
        return success

    @staticmethod
    async def verify_smtp_config() -> bool:
        """Verifies if the SMTP configuration is valid asynchronously to keep event loop safe."""
        if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
            return False
        try:
            def _check():
                if settings.SMTP_PORT == 465:
                    server = smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10)
                else:
                    server = smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10)
                    if settings.SMTP_TLS:
                        server.starttls()
                try:
                    server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                    return True
                finally:
                    server.quit()

            return await asyncio.to_thread(_check)
        except Exception as e:
            logger.error(f"[EMAIL] SMTP Health Check failed: {str(e)}")
            return False

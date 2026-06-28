import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from jinja2 import Environment, FileSystemLoader, select_autoescape
from app.core.config import settings

logger = logging.getLogger("app.email_service")

# Setup Jinja2 environment
TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"
jinja_env = Environment(
    loader=FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=select_autoescape(['html', 'xml'])
)

class EmailService:
    @staticmethod
    def _render_template(template_name: str, **kwargs) -> str:
        template = jinja_env.get_template(template_name)
        return template.render(**kwargs)

    @staticmethod
    def send_otp_email(email: str, otp: str, purpose: str = "REGISTRATION") -> bool:
        """
        Sends a professional OTP email.
        purpose: 'REGISTRATION' or 'PASSWORD_RESET'
        """
        if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
            logger.warning(f"[EMAIL] SMTP credentials not configured. OTP for {email}: {otp}")
            return False

        subject = "Premises - Verification Code"
        if purpose == "PASSWORD_RESET":
            subject = "Premises - Password Reset Verification Code"

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

            # Send via SMTP
            # If using port 465, use SMTP_SSL. If 587, use SMTP + starttls
            if settings.SMTP_PORT == 465:
                server = smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT)
            else:
                server = smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT)
                server.ehlo()
                if settings.SMTP_TLS:
                    server.starttls()
                    server.ehlo()

            try:
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(msg)
                logger.info(f"[EMAIL] Successfully sent {purpose} OTP to {email}")
                return True
            finally:
                server.quit()

        except Exception as e:
            logger.error(f"[EMAIL] Failed to send email to {email}: {str(e)}")
            return False

    @staticmethod
    def send_welcome_email(email: str, admin_name: str, org_name: str, org_code: str) -> bool:
        """
        Sends a professional welcome email with the organization code.
        """
        if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
            logger.warning(f"[EMAIL] SMTP credentials not configured. Org Code for {email}: {org_code}")
            return False

        subject = "Premises - Organization Created Successfully"

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

            # Send via SMTP
            if settings.SMTP_PORT == 465:
                server = smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT)
            else:
                server = smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT)
                server.ehlo()
                if settings.SMTP_TLS:
                    server.starttls()
                    server.ehlo()

            try:
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(msg)
                logger.info(f"[EMAIL] Successfully sent welcome email to {email}")
                return True
            finally:
                server.quit()

        except Exception as e:
            logger.error(f"[EMAIL] Failed to send welcome email to {email}: {str(e)}")
            return False

    @staticmethod
    def verify_smtp_config() -> bool:
        """Verifies if the SMTP configuration is valid."""
        if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
            return False
        try:
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
        except Exception as e:
            logger.error(f"[EMAIL] SMTP Health Check failed: {str(e)}")
            return False

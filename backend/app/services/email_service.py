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
        template = jinja_env.get_member(template_name)
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
            html_content = jinja_env.get_template("otp_email.html").render(
                otp=otp,
                subject=subject
            )

            # Create message
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From'] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_FROM_EMAIL}>"
            msg['To'] = email

            msg.attach(MIMEText(f"Your verification code is: {otp}", 'plain'))
            msg.attach(MIMEText(html_content, 'html'))

            # Send via SMTP
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
                if settings.SMTP_TLS:
                    server.starttls()
                    print("=" * 60)
                    print("SMTP_USERNAME:", settings.SMTP_USERNAME)
                    print("SMTP_PASSWORD:", settings.SMTP_PASSWORD)
                    print("SMTP_FROM_EMAIL:", settings.SMTP_FROM_EMAIL)
                    print("SMTP_HOST:", settings.SMTP_HOST)
                    print("SMTP_PORT:", settings.SMTP_PORT)
                    print("=" * 60)
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(msg)

            logger.info(f"[EMAIL] Successfully sent {purpose} OTP to {email}")
            return True

        except Exception as e:
            logger.error(f"[EMAIL] Failed to send email to {email}: {str(e)}")
            return False

    @staticmethod
    def verify_smtp_config() -> bool:
        """Verifies if the SMTP configuration is valid."""
        if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
            return False
        try:
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as server:
                if settings.SMTP_TLS:
                    server.starttls()
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
            return True
        except Exception as e:
            logger.error(f"[EMAIL] SMTP Health Check failed: {str(e)}")
            return False

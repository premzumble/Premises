import json
import logging
import random
import string
import uuid
from datetime import datetime, timezone
from typing import Any, Optional, Tuple
from sqlalchemy import select, update, desc
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.constants import UserRole, UserStatus, RequestStatus
from app.core.exceptions import AuthException, ConflictException, NotFoundException, ValidationException
from app.core.security import get_password_hash, verify_password, create_access_token, create_refresh_token
from app.models.organization import Organization, OrganizationSettings, Department
from app.models.user import Admin, Faculty
from app.models.request import Device, FacultyRegistrationRequest, DeviceChangeRequest
from app.models.otp import OtpVerification
from app.models.notification import Notification
from app.models.log import AuditLog
from app.schemas.auth import AdminRegisterRequest, FacultyRegisterRequest, LoginRequest, PublicDepartmentResponse, PublicOrgDetailsResponse, VerifyOtpResponse
from app.repositories.admin_repo import AdminRepository
from app.repositories.faculty_repo import FacultyRepository


def _generate_otp(length: int = 6) -> str:
    return ''.join(random.choices(string.digits, k=length))


def _generate_org_code(org_name: str) -> str:
    """Derives a short unique org code from the org name (uppercase, max 8 chars)."""
    base = ''.join(filter(str.isalpha, org_name)).upper()[:8]
    suffix = ''.join(random.choices(string.digits, k=3))
    return f"{base}{suffix}"


logger = logging.getLogger("app.auth_service")


PUBLIC_DOMAINS = {
    "gmail.com", "googlemail.com",
    "yahoo.com", "yahoo.co.in", "yahoo.co.uk", "yahoo.com.br", "yahoo.com.mx", "ymail.com",
    "outlook.com", "hotmail.com", "live.com", "msn.com", "live.co.uk", "hotmail.co.uk", "hotmail.fr",
    "protonmail.com", "protonmail.ch", "proton.me",
    "zoho.com", "zoho.in", "zoho.eu",
    "aol.com", "mail.com", "icloud.com", "me.com", "mac.com",
    "yandex.com", "yandex.ru", "yandex.by", "yandex.kz", "yandex.ua",
    "gmx.com", "gmx.net", "gmx.de", "gmx.at", "gmx.ch",
    "mail.ru", "inbox.ru", "list.ru", "bk.ru",
    "rediffmail.com", "lycos.com", "fastmail.com", "hushmail.com"
}


def is_public_email_domain(domain: str) -> bool:
    domain = domain.strip().lower()
    if domain in PUBLIC_DOMAINS:
        return True
    parts = domain.split('.')
    if len(parts) >= 2:
        last_two = ".".join(parts[-2:])
        if last_two in PUBLIC_DOMAINS:
            return True
        if len(parts) >= 3:
            last_three = ".".join(parts[-3:])
            if last_three in PUBLIC_DOMAINS:
                return True
    return False


class AuthService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.admin_repo = AdminRepository(db)
        self.faculty_repo = FacultyRepository(db)

    # ------------------------------------------------------------------
    # ADMIN: Step 1 — Initiate registration & send OTP
    # ------------------------------------------------------------------
    async def initiate_admin_registration(self, data: AdminRegisterRequest) -> str:
        """Creates an OTP record for admin registration. Returns the OTP (for dev: print to terminal)."""

        # 1. Check if email already exists in admin or faculty tables
        admin_check = await self.admin_repo.get_by_email(data.email)
        faculty_check = await self.faculty_repo.get_by_email(data.email)
        if admin_check or faculty_check:
            raise ConflictException("An account with this email address already exists.")

        # 2. Check if OTP already pending for this email — delete stale record
        stmt = select(OtpVerification).where(OtpVerification.email == data.email)
        res = await self.db.execute(stmt)
        existing_otp = res.scalars().first()
        if existing_otp:
            await self.db.delete(existing_otp)
            await self.db.flush()

        # 3. Generate OTP and serialize registration data
        otp = _generate_otp()
        registration_data = json.dumps({
            "org_name": data.org_name,
            "org_type": data.org_type,
            "admin_name": data.admin_name,
            "email": data.email,
            "password_hash": get_password_hash(data.password),
        })

        otp_record = OtpVerification(
            email=data.email,
            otp=otp,
            registration_data=registration_data,
        )
        self.db.add(otp_record)
        await self.db.commit()

        # In development: print OTP to terminal
        print(f"\n{'='*50}")
        print(f"[DEV] OTP for {data.email}: {otp}")
        print(f"{'='*50}\n")

        return otp

    # ------------------------------------------------------------------
    # ADMIN: Step 2 — Verify OTP & create Organization + Admin
    # ------------------------------------------------------------------
    async def verify_admin_otp(self, email: str, otp: str) -> VerifyOtpResponse:
        """Verifies the OTP and creates the Organization and Admin account."""

        stmt = select(OtpVerification).where(OtpVerification.email == email)
        res = await self.db.execute(stmt)
        otp_record = res.scalars().first()

        if not otp_record:
            raise NotFoundException("No pending registration found for this email. Please register again.")

        if otp_record.otp != otp:
            raise ValidationException("Invalid OTP. Please check the code and try again.")

        # Deserialize saved registration data
        reg_data = json.loads(otp_record.registration_data)

        # Generate unique org code
        org_code = _generate_org_code(reg_data["org_name"])

        # Extract domain from email (excluding public domains)
        admin_email = reg_data["email"].strip().lower()
        extracted_domain = None
        if "@" in admin_email:
            domain_part = admin_email.split("@")[-1].strip()
            if not is_public_email_domain(domain_part):
                extracted_domain = domain_part
                logger.info(f"Extracted college domain '{extracted_domain}' from admin email '{admin_email}'.")
            else:
                logger.info(f"Admin email '{admin_email}' belongs to a public domain. Storing domain as NULL.")

        # Create Organization
        organization = Organization(
            name=reg_data["org_name"],
            type=reg_data["org_type"],
            organization_code=org_code,
            domain=extracted_domain,
        )
        self.db.add(organization)
        await self.db.flush()  # flush to get organization.id

        # Create default OrganizationSettings
        org_settings = OrganizationSettings(
            organization_id=organization.id,
        )
        self.db.add(org_settings)

        # Create Admin user
        admin = Admin(
            organization_id=organization.id,
            full_name=reg_data["admin_name"],
            email=reg_data["email"],
            password_hash=reg_data["password_hash"],
            status=UserStatus.ACTIVE.value,
        )
        self.db.add(admin)

        # Delete the OTP record
        await self.db.delete(otp_record)
        await self.db.flush()

        # Audit log: admin registration completed
        audit_log = AuditLog(
            organization_id=organization.id,
            actor_type="ADMIN",
            actor_id=admin.id,
            action="ADMIN_REGISTERED",
            entity_type="ORGANIZATION",
            entity_id=organization.id,
            new_value={
                "org_name": organization.name,
                "org_code": org_code,
                "admin_email": admin.email,
                "admin_name": admin.full_name,
            },
        )
        self.db.add(audit_log)

        await self.db.commit()
        await self.db.refresh(organization)
        logger.info(f"Successfully created organization '{organization.name}' (ID: {organization.id}) and admin '{admin.full_name}' (ID: {admin.id})")

        return VerifyOtpResponse(
            organization_id=organization.id,
            organization_code=org_code,
            name=reg_data["org_name"],
            message=f"Organization '{reg_data['org_name']}' created successfully! Your organization code is {org_code}.",
        )

    # ------------------------------------------------------------------
    # PUBLIC: Fetch org details by code (for faculty registration)
    # ------------------------------------------------------------------
    async def get_public_org_details(self, organization_code: str) -> PublicOrgDetailsResponse:
        """Returns organization name + departments for the given org code."""
        org_stmt = select(Organization).where(Organization.organization_code == organization_code.upper().strip())
        org_res = await self.db.execute(org_stmt)
        organization = org_res.scalars().first()
        if not organization:
            raise NotFoundException("No organization found with this code. Please verify with your admin.")

        dept_stmt = select(Department).where(Department.organization_id == organization.id)
        dept_res = await self.db.execute(dept_stmt)
        departments = dept_res.scalars().all()

        return PublicOrgDetailsResponse(
            organization_id=organization.id,
            organization_name=organization.name,
            organization_code=organization.organization_code,
            departments=[PublicDepartmentResponse(id=d.id, name=d.name) for d in departments],
        )

    # ------------------------------------------------------------------
    # PUBLIC: Lookup organization by domain or code
    # ------------------------------------------------------------------
    async def lookup_organization(self, email: Optional[str] = None, code: Optional[str] = None) -> PublicOrgDetailsResponse:
        """Looks up organization and active departments by email domain or organization code."""
        organization = None
        
        # Priority 1: Organization Code
        if code and code.strip():
            logger.info(f"Looking up organization by code '{code}'")
            org_stmt = select(Organization).where(Organization.organization_code == code.upper().strip())
            org_res = await self.db.execute(org_stmt)
            organization = org_res.scalars().first()
            if not organization:
                logger.warning(f"Organization not found with code '{code}'")
                raise NotFoundException("Organization not found.")
        
        # Priority 2: Organization Domain
        elif email and email.strip():
            logger.info(f"Looking up organization by email '{email}'")
            if "@" not in email:
                raise ValidationException("Email is invalid.")
            
            domain = email.split("@")[-1].strip().lower()
            if is_public_email_domain(domain):
                logger.warning(f"Public email domain '{domain}' detected.")
                raise ValidationException("Public email detected. Organization code required.")
            
            org_stmt = select(Organization).where(Organization.domain == domain)
            org_res = await self.db.execute(org_stmt)
            organization = org_res.scalars().first()
            if not organization:
                logger.warning(f"Organization domain '{domain}' not configured.")
                raise NotFoundException("Organization domain not configured.")
        else:
            logger.warning("Lookup attempted without email or organization code.")
            raise ValidationException("Organization code required.")

        # Check organization status
        if organization.status != "ACTIVE":
            logger.warning(f"Organization '{organization.name}' (ID: {organization.id}) is inactive.")
            raise ValidationException("Organization inactive.")

        # Load departments
        logger.info(f"Loading departments for organization '{organization.name}' (ID: {organization.id})")
        dept_stmt = select(Department).where(Department.organization_id == organization.id)
        dept_res = await self.db.execute(dept_stmt)
        all_depts = dept_res.scalars().all()
        
        active_depts = [d for d in all_depts if d.is_active]
        
        if not all_depts:
            logger.warning(f"Organization '{organization.name}' (ID: {organization.id}) has no departments.")
            raise ValidationException("Organization has no departments.")
            
        if not active_depts:
            logger.warning(f"Organization '{organization.name}' (ID: {organization.id}) has no active departments.")
            raise ValidationException("Department list unavailable.")

        return PublicOrgDetailsResponse(
            organization_id=organization.id,
            organization_name=organization.name,
            organization_code=organization.organization_code,
            departments=[PublicDepartmentResponse(id=d.id, name=d.name) for d in active_depts],
        )

    async def get_public_org_details(self, organization_code: str) -> PublicOrgDetailsResponse:
        """Returns organization name + departments for the given org code (legacy helper)."""
        return await self.lookup_organization(code=organization_code)

    # ------------------------------------------------------------------
    # FACULTY: Register (pending admin approval)
    # ------------------------------------------------------------------
    async def register_faculty(self, data: FacultyRegisterRequest) -> Faculty:
        """Registers a faculty member under the given organization code or email domain."""

        # 1. Email validation
        email = data.email.strip().lower()
        if "@" not in email:
            raise ValidationException("Email is invalid.")

        logger.info(f"Initiating faculty registration for email: {email}")

        # 2. Check if email is already taken
        admin_check = await self.admin_repo.get_by_email(email)
        if admin_check:
            logger.warning(f"Email {email} is already registered as an admin.")
            raise ConflictException("Email is already registered in the system.")

        faculty_check = await self.faculty_repo.get_by_email(email)
        if faculty_check:
            if faculty_check.status == UserStatus.PENDING_APPROVAL.value:
                logger.warning(f"Pending registration request already exists for email: {email}")
                raise ConflictException("A pending registration request already exists for this email address.")
            elif faculty_check.status == UserStatus.ACTIVE.value:
                logger.warning(f"Email {email} is already registered as an active faculty.")
                raise ConflictException("This email address is already registered as an active faculty member.")
            else:
                logger.warning(f"Account for {email} is inactive/disabled.")
                raise ConflictException("This account is inactive. Please contact your administrator.")

        # 3. Resolve Organization and validate status
        organization = None
        if not data.organization_code:
            domain = email.split("@")[-1].strip().lower()
            if is_public_email_domain(domain):
                logger.warning(f"Public email domain '{domain}' used for registration without code.")
                raise ValidationException("Public email detected. Organization code required.")
            
            logger.info(f"Resolving organization domain: {domain}")
            org_stmt = select(Organization).where(Organization.domain == domain)
            org_res = await self.db.execute(org_stmt)
            organization = org_res.scalars().first()
            if not organization:
                logger.warning(f"Organization domain '{domain}' not configured.")
                raise NotFoundException("Organization domain not configured.")
        else:
            logger.info(f"Resolving organization code: {data.organization_code}")
            org_stmt = select(Organization).where(Organization.organization_code == data.organization_code.upper().strip())
            org_res = await self.db.execute(org_stmt)
            organization = org_res.scalars().first()
            if not organization:
                logger.warning(f"Organization not found with code '{data.organization_code}'")
                raise NotFoundException("Organization not found.")

        if organization.status != "ACTIVE":
            logger.warning(f"Organization '{organization.name}' (ID: {organization.id}) is inactive.")
            raise ValidationException("Organization inactive.")

        # 4. Validate Department
        if not data.department_id:
            logger.warning("Faculty registration attempted without selecting a department.")
            raise ValidationException("Department required.")

        logger.info(f"Validating selected department ID: {data.department_id}")
        dept_stmt = select(Department).where(Department.id == data.department_id)
        dept_res = await self.db.execute(dept_stmt)
        department = dept_res.scalars().first()
        if not department:
            logger.warning(f"Department ID {data.department_id} not found.")
            raise NotFoundException("Department not found.")

        if department.organization_id != organization.id:
            logger.warning(f"Selected department '{department.name}' does not belong to organization '{organization.name}'.")
            raise ValidationException("Selected department does not belong to this organization.")

        if not department.is_active:
            logger.warning(f"Selected department '{department.name}' is inactive.")
            raise ValidationException("Department inactive.")

        # Create Faculty member
        hashed_password = get_password_hash(data.password)
        faculty_data = {
            "organization_id": organization.id,
            "department_id": data.department_id,
            "full_name": data.full_name,
            "email": email,
            "password_hash": hashed_password,
            "status": UserStatus.PENDING_APPROVAL.value,
        }
        faculty = await self.faculty_repo.create(obj_in_data=faculty_data)

        # Create Device registration if provided
        if data.device_identifier:
            logger.info(f"Registering device '{data.device_model}' ({data.platform}) for faculty: {email}")
            device = Device(
                organization_id=organization.id,
                faculty_id=faculty.id,
                device_identifier=data.device_identifier,
                device_model=data.device_model,
                platform=data.platform.value if data.platform else "ANDROID",
                is_active=True,
            )
            self.db.add(device)

        # Queue registration approval request
        reg_request = FacultyRegistrationRequest(
            organization_id=organization.id,
            faculty_id=faculty.id,
            status=RequestStatus.PENDING.value,
        )
        self.db.add(reg_request)

        # Create Admin notification
        admin_notification = Notification(
            organization_id=organization.id,
            faculty_id=faculty.id,
            type="ADMIN_FACULTY_REGISTRATION",
            title="New Faculty Registration",
            message=f"{faculty.full_name} has requested access.",
            recipient_role="ADMIN",
            recipient_id=None
        )
        self.db.add(admin_notification)

        await self.db.commit()
        await self.db.refresh(faculty)
        
        logger.info(f"Faculty registration successfully submitted for approval: {faculty.email} (ID: {faculty.id}) in organization '{organization.name}'.")
        return faculty

    # ------------------------------------------------------------------
    # LOGIN: Unified login (auto-detect role if not specified)
    # ------------------------------------------------------------------
    async def login(self, data: LoginRequest) -> Tuple[str, str, Any, Any]:
        """
        Unified login: tries Admin first if role=ADMIN (or unspecified),
        then Faculty if role=FACULTY (or unspecified) with device binding.
        """
        email = data.email.strip().lower()

        # --- Try ADMIN ---
        if data.role is None or data.role == UserRole.ADMIN:
            admin = await self.admin_repo.get_by_email(email)
            if admin and verify_password(data.password, admin.password_hash):
                logger.info(f"Admin login attempt: {email}")
                if admin.status != UserStatus.ACTIVE.value:
                    logger.warning(f"Admin login failed: Account inactive for email {email}")
                    raise AuthException("Your administrative account has been deactivated.")
                admin.last_login_at = datetime.now(timezone.utc)
                self.db.add(admin)
                # Audit log: admin login
                login_log = AuditLog(
                    organization_id=admin.organization_id,
                    actor_type="ADMIN",
                    actor_id=admin.id,
                    action="ADMIN_LOGIN",
                    entity_type="ADMIN",
                    entity_id=admin.id,
                    new_value={"email": email},
                )
                self.db.add(login_log)
                await self.db.commit()
                logger.info(f"Admin login successful: {email} (ID: {admin.id})")
                access = create_access_token(admin.id, UserRole.ADMIN.value, admin.organization_id)
                refresh = create_refresh_token(admin.id, UserRole.ADMIN.value, admin.organization_id)
                return access, refresh, UserRole.ADMIN, admin

        # --- Try FACULTY ---
        if data.role is None or data.role == UserRole.FACULTY:
            faculty = await self.faculty_repo.get_by_email(email)
            if faculty and verify_password(data.password, faculty.password_hash):
                logger.info(f"Faculty login attempt: {email}")
                if faculty.status == UserStatus.PENDING_APPROVAL.value:
                    logger.warning(f"Login failed: Account pending approval for faculty: {email}")
                    raise AuthException("Your account is pending administrator verification. Please wait for approval.")
                
                if faculty.status == UserStatus.INACTIVE.value:
                    # Check if there is a rejected request
                    reg_stmt = select(FacultyRegistrationRequest).where(
                        FacultyRegistrationRequest.faculty_id == faculty.id,
                        FacultyRegistrationRequest.status == RequestStatus.REJECTED.value
                    )
                    reg_res = await self.db.execute(reg_stmt)
                    rejected_req = reg_res.scalars().first()
                    if rejected_req:
                        logger.warning(f"Login failed: Account rejected for faculty: {email}")
                        raise AuthException("Your registration request has been rejected. Please contact support.")
                    else:
                        logger.warning(f"Login failed: Account inactive for faculty: {email}")
                        raise AuthException("Your account is inactive. Please contact your administrator.")
                
                if faculty.status != UserStatus.ACTIVE.value:
                    logger.warning(f"Login failed: Account status '{faculty.status}' not active for faculty: {email}")
                    raise AuthException("Your account is inactive. Please contact your administrator.")

                # Handle Device Binding & Security
                device_id = data.device_identifier or "UNKNOWN_DEVICE"
                model = data.device_model or "Unknown Model"
                platform = data.platform or "ANDROID"
                os_ver = data.os_version or "Unknown OS"
                manuf = data.manufacturer or "Unknown Manufacturer"

                active_device = await self.faculty_repo.get_active_device(faculty.id)
                if not active_device:
                    # Case A: First successful login, register the device
                    new_device = Device(
                        organization_id=faculty.organization_id,
                        faculty_id=faculty.id,
                        device_identifier=device_id,
                        device_model=model,
                        platform=platform,
                        os_version=os_ver,
                        manufacturer=manuf,
                        is_active=True
                    )
                    self.db.add(new_device)
                    
                    audit_log = AuditLog(
                        organization_id=faculty.organization_id,
                        actor_type="FACULTY",
                        actor_id=faculty.id,
                        action="REGISTER_DEVICE",
                        entity_type="DEVICE",
                        entity_id=new_device.id,
                        new_value={"device_identifier": device_id, "device_model": model, "platform": platform, "os_version": os_ver, "manufacturer": manuf}
                    )
                    self.db.add(audit_log)
                elif active_device.device_identifier != device_id:
                    # Check if a pending or rejected device change request already exists for this device
                    swap_stmt = select(DeviceChangeRequest).where(
                        DeviceChangeRequest.faculty_id == faculty.id,
                        DeviceChangeRequest.new_device_identifier == device_id
                    ).order_by(desc(DeviceChangeRequest.created_at))
                    swap_res = await self.db.execute(swap_stmt)
                    latest_swap = swap_res.scalars().first()
                    if latest_swap:
                        if latest_swap.status == RequestStatus.PENDING.value:
                            logger.warning(f"Device change request already pending for faculty {email} on device {device_id}")
                            raise AuthException("Your device change request is pending administrator verification.")
                        elif latest_swap.status == RequestStatus.REJECTED.value:
                            logger.warning(f"Device change request was rejected for faculty {email} on device {device_id}")
                            raise AuthException(f"Your device change request has been rejected: {latest_swap.rejection_reason or 'No reason specified'}. Please contact support.")

                    # Case B: Login from a different device, require OTP
                    if not data.otp:
                        # Clean up any existing OTP verification for this email
                        existing_otp_stmt = select(OtpVerification).where(OtpVerification.email == email)
                        existing_otp_res = await self.db.execute(existing_otp_stmt)
                        existing_otp = existing_otp_res.scalars().first()
                        if existing_otp:
                            await self.db.delete(existing_otp)
                            await self.db.flush()

                        # Generate device verification OTP
                        otp = _generate_otp()
                        reg_payload = json.dumps({
                            "device_identifier": device_id,
                            "device_model": model,
                            "platform": platform,
                            "os_version": os_ver,
                            "manufacturer": manuf
                        })
                        otp_verification = OtpVerification(
                            email=email,
                            otp=otp,
                            registration_data=reg_payload
                        )
                        self.db.add(otp_verification)
                        await self.db.commit()

                        # Print OTP to logs
                        print(f"\n{'='*50}")
                        print(f"[DEV] NEW DEVICE BINDING OTP FOR {email}: {otp}")
                        print(f"{'='*50}\n")

                        raise AuthException("NEW_DEVICE_OTP_REQUIRED")
                    else:
                        # Validate the OTP
                        otp_stmt = select(OtpVerification).where(OtpVerification.email == email)
                        otp_res = await self.db.execute(otp_stmt)
                        otp_record = otp_res.scalars().first()

                        if not otp_record or otp_record.otp != data.otp:
                            raise AuthException("Invalid verification OTP. Please try again.")

                        # OTP is valid, create a pending DeviceChangeRequest
                        device_request = DeviceChangeRequest(
                            organization_id=faculty.organization_id,
                            faculty_id=faculty.id,
                            old_device_id=active_device.id,
                            new_device_identifier=device_id,
                            new_device_model=model,
                            reason=data.device_swap_reason or "New device login",
                            status=RequestStatus.PENDING.value
                        )
                        self.db.add(device_request)

                        # Create Admin notification
                        admin_notification = Notification(
                            organization_id=faculty.organization_id,
                            faculty_id=faculty.id,
                            type="ADMIN_DEVICE_SWAP",
                            title="Device Swap Request",
                            message=f"{faculty.full_name} has requested a device swap.",
                            recipient_role="ADMIN",
                            recipient_id=None
                        )
                        self.db.add(admin_notification)

                        # Clean up OTP record
                        await self.db.delete(otp_record)
                        await self.db.commit()

                        logger.info(f"Device change request successfully submitted for faculty: {email}")
                        raise AuthException("Device change request submitted. Please wait for administrator approval.")

                faculty.last_login_at = datetime.now(timezone.utc)
                self.db.add(faculty)
                # Audit log: faculty login
                faculty_login_log = AuditLog(
                    organization_id=faculty.organization_id,
                    actor_type="FACULTY",
                    actor_id=faculty.id,
                    action="FACULTY_LOGIN",
                    entity_type="FACULTY",
                    entity_id=faculty.id,
                    new_value={"email": email},
                )
                self.db.add(faculty_login_log)
                await self.db.commit()
                logger.info(f"Faculty login successful: {email} (ID: {faculty.id})")
                access = create_access_token(faculty.id, UserRole.FACULTY.value, faculty.organization_id)
                refresh = create_refresh_token(faculty.id, UserRole.FACULTY.value, faculty.organization_id)
                return access, refresh, UserRole.FACULTY, faculty

        raise AuthException("Invalid email or password.")

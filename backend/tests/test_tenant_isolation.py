import pytest
import uuid
import json
from datetime import datetime, timezone, date, timedelta
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.database.database import AsyncSessionLocal, init_db
from app.models.organization import Organization, Department
from app.models.user import Admin, Faculty
from app.models.request import Device, FacultyRegistrationRequest, DeviceChangeRequest, ReasonRequest
from app.models.attendance import AttendanceRecord
from app.models.log import AuditLog
from app.models.otp import OtpVerification
from sqlalchemy import select, delete


@pytest.mark.asyncio
async def test_cross_tenant_isolation():
    await init_db()

    # Define unique test emails/names for Org A and Org B
    email_admin_a = "admin_a@tenanta.com"
    email_admin_b = "admin_b@tenantb.com"
    email_fac_a = "faculty_a@tenanta.com"
    email_fac_b = "faculty_b@tenantb.com"

    async with AsyncSessionLocal() as db:
        # 1. Clean up any existing records for these emails
        await db.execute(delete(OtpVerification).where(OtpVerification.email.in_([email_admin_a, email_admin_b, email_fac_a, email_fac_b])))
        await db.execute(delete(Admin).where(Admin.email.in_([email_admin_a, email_admin_b])))
        await db.execute(delete(Faculty).where(Faculty.email.in_([email_fac_a, email_fac_b])))
        await db.execute(delete(Organization).where(Organization.name.in_(["Tenant Org A", "Tenant Org B"])))
        await db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # --- Seeding Organization A ---
        # Admin A Reg
        res = await client.post("/api/v1/auth/register-admin", json={
            "org_name": "Tenant Org A",
            "org_type": "Corporate",
            "admin_name": "Admin A",
            "email": email_admin_a,
            "password": "passwordA"
        })
        assert res.status_code == 200, f"A: {res.json()}"
        
        async with AsyncSessionLocal() as db:
            otp_a = (await db.execute(select(OtpVerification).where(OtpVerification.email == email_admin_a))).scalars().first().otp
            
        res = await client.post("/api/v1/auth/verify-otp", json={"email": email_admin_a, "otp": otp_a})
        assert res.status_code == 200
        org_a_id = uuid.UUID(res.json()["data"]["organization_id"])
        
        # Log in Admin A
        res = await client.post("/api/v1/auth/login", json={"email": email_admin_a, "password": "passwordA"})
        assert res.status_code == 200
        token_a = res.json()["data"]["access_token"]
        headers_a = {"Authorization": f"Bearer {token_a}"}

        # Create Dept A
        res = await client.post("/api/v1/settings/departments", json={"name": "Dept A", "description": "Dept A Desc"}, headers=headers_a)
        assert res.status_code == 200
        dept_a_id = uuid.UUID(res.json()["data"]["id"])

        # --- Seeding Organization B ---
        # Admin B Reg
        res = await client.post("/api/v1/auth/register-admin", json={
            "org_name": "Tenant Org B",
            "org_type": "Corporate",
            "admin_name": "Admin B",
            "email": email_admin_b,
            "password": "passwordB"
        })
        assert res.status_code == 200
        
        async with AsyncSessionLocal() as db:
            otp_b = (await db.execute(select(OtpVerification).where(OtpVerification.email == email_admin_b))).scalars().first().otp
            
        res = await client.post("/api/v1/auth/verify-otp", json={"email": email_admin_b, "otp": otp_b})
        assert res.status_code == 200
        org_b_id = uuid.UUID(res.json()["data"]["organization_id"])
        
        # Log in Admin B
        res = await client.post("/api/v1/auth/login", json={"email": email_admin_b, "password": "passwordB"})
        assert res.status_code == 200
        token_b = res.json()["data"]["access_token"]
        headers_b = {"Authorization": f"Bearer {token_b}"}

        # Create Dept B
        res = await client.post("/api/v1/settings/departments", json={"name": "Dept B", "description": "Dept B Desc"}, headers=headers_b)
        assert res.status_code == 200
        dept_b_id = uuid.UUID(res.json()["data"]["id"])

        # Seed Faculty A (Org A)
        async with AsyncSessionLocal() as db:
            from app.core.security import get_password_hash
            from app.models.notification import Notification

            fac_a = Faculty(
                organization_id=org_a_id,
                department_id=dept_a_id,
                full_name="Faculty A Member",
                email=email_fac_a,
                password_hash=get_password_hash("passwordA"),
                status="ACTIVE"
            )
            db.add(fac_a)
            
            # Seed Faculty B (Org B)
            fac_b = Faculty(
                organization_id=org_b_id,
                department_id=dept_b_id,
                full_name="Faculty B Member",
                email=email_fac_b,
                password_hash=get_password_hash("passwordB"),
                status="ACTIVE"
            )
            db.add(fac_b)
            await db.flush()

            # Seed request details for testing
            req_reg_b = FacultyRegistrationRequest(
                organization_id=org_b_id,
                faculty_id=fac_b.id,
                status="PENDING"
            )
            db.add(req_reg_b)
            
            # Seed Device Swap Request B
            req_swap_b = DeviceChangeRequest(
                organization_id=org_b_id,
                faculty_id=fac_b.id,
                new_device_identifier="DEVICE_B_NEW",
                new_device_model="Pixel 9",
                status="PENDING"
            )
            db.add(req_swap_b)

            # Seed Excusal Request (Reason Request) B
            rec_b = AttendanceRecord(
                organization_id=org_b_id,
                faculty_id=fac_b.id,
                attendance_date=date.today(),
                status="ABSENT"
            )
            db.add(rec_b)
            await db.flush()

            req_exc_b = ReasonRequest(
                organization_id=org_b_id,
                faculty_id=fac_b.id,
                attendance_record_id=rec_b.id,
                reason_type="MEDICAL",
                notes="Sick",
                status="PENDING"
            )
            db.add(req_exc_b)
            await db.commit()

            req_reg_b_id = req_reg_b.id
            req_swap_b_id = req_swap_b.id
            req_exc_b_id = req_exc_b.id

        # --- MULTI-TENANT ISOLATION BOUNDARY CHECKS ---

        # 1. Admin A cannot read Dept B
        res = await client.delete(f"/api/v1/settings/departments/{dept_b_id}", headers=headers_a)
        assert res.status_code == 404, f"Admin A successfully modified Department B: {res.json()}"

        # 2. Admin A cannot read/write Policy for Dept B
        res = await client.get(f"/api/v1/settings/policy?department_id={dept_b_id}", headers=headers_a)
        assert res.status_code == 404, "Admin A loaded policy details for Department B"

        res = await client.put("/api/v1/settings/policy", json={
            "department_id": str(dept_b_id),
            "allowed_outside_minutes": 10
        }, headers=headers_a)
        assert res.status_code == 404, "Admin A successfully set/updated policy on Department B"

        # 3. Admin A cannot approve/reject Faculty Registration Request B
        res = await client.post(f"/api/v1/faculty/approve-registration/{req_reg_b_id}?status=APPROVED", headers=headers_a)
        assert res.status_code == 404, "Admin A approved cross-tenant faculty request B"

        # 4. Admin A cannot approve/reject Device Swap Request B
        res = await client.post(f"/api/v1/admin/approve-device-swap/{req_swap_b_id}", headers=headers_a)
        assert res.status_code == 404, "Admin A approved cross-tenant device swap B"

        # 5. Admin A cannot approve/reject Excusal Request B
        res = await client.post(f"/api/v1/admin/approve-excusal/{req_exc_b_id}", headers=headers_a)
        assert res.status_code == 404, "Admin A approved cross-tenant geofence excusal request B"

        # 6. Admin A cannot perform attendance override on a cross-tenant faculty ID
        res = await client.post("/api/v1/admin/attendance/override", json={
            "faculty_id": str(uuid.uuid4()),
            "attendance_date": date.today().isoformat(),
            "override_status": "PRESENT",
            "override_reason": "Testing isolation",
            "override_remarks": "Test remarks"
        }, headers=headers_a)
        assert res.status_code == 404, f"Admin A manual attendance override got: {res.status_code}: {res.json()}"

        # 7. Admin A cannot export reports using cross-tenant department filter
        res = await client.get(f"/api/v1/admin/export-report?department_id={dept_b_id}", headers=headers_a)
        assert res.status_code == 404, "Admin A generated attendance report filtered on cross-tenant Department B"

        # 8. Admin A cannot fetch attendance logs filtered on cross-tenant department
        res = await client.get(f"/api/v1/admin/attendance-logs?department_id={dept_b_id}", headers=headers_a)
        assert res.status_code == 404, "Admin A fetched logs filtered on cross-tenant Department B"

        # --- Clean up seeded test records ---
        async with AsyncSessionLocal() as db:
            await db.execute(delete(ReasonRequest).where(ReasonRequest.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(AttendanceRecord).where(AttendanceRecord.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(DeviceChangeRequest).where(DeviceChangeRequest.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(FacultyRegistrationRequest).where(FacultyRegistrationRequest.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(Faculty).where(Faculty.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(Department).where(Department.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(Admin).where(Admin.organization_id.in_([org_a_id, org_b_id])))
            await db.execute(delete(Organization).where(Organization.id.in_([org_a_id, org_b_id])))
            await db.commit()

import pytest
import uuid
import json
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.database.database import AsyncSessionLocal, init_db
from app.models.organization import Organization, Department
from app.models.user import Admin, Faculty
from app.models.request import Device, FacultyRegistrationRequest, DeviceChangeRequest, ReasonRequest
from app.models.otp import OtpVerification
from app.models.notification import Notification
from sqlalchemy import select, delete


@pytest.mark.asyncio
async def test_approvals_and_notifications_workflow():
    await init_db()
    
    test_org_name = "Test Approvals University"
    test_admin_email = "admin@testapprovals.edu"
    test_faculty_email = "faculty@testapprovals.edu"
    
    # 0. Clean up existing test data
    async with AsyncSessionLocal() as db:
        await db.execute(delete(OtpVerification).where(OtpVerification.email.in_([test_admin_email, test_faculty_email])))
        orgs_res = await db.execute(select(Organization).where(Organization.name == test_org_name))
        orgs = orgs_res.scalars().all()
        for org in orgs:
            await db.execute(delete(Device).where(Device.organization_id == org.id))
            await db.execute(delete(FacultyRegistrationRequest).where(FacultyRegistrationRequest.organization_id == org.id))
            await db.execute(delete(DeviceChangeRequest).where(DeviceChangeRequest.organization_id == org.id))
            await db.execute(delete(ReasonRequest).where(ReasonRequest.organization_id == org.id))
            await db.execute(delete(Notification).where(Notification.organization_id == org.id))
            await db.execute(delete(Faculty).where(Faculty.organization_id == org.id))
            await db.execute(delete(Admin).where(Admin.organization_id == org.id))
            await db.execute(delete(Department).where(Department.organization_id == org.id))
            await db.execute(delete(Organization).where(Organization.id == org.id))
        await db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Admin Registration (Initiate & Verify)
        res = await client.post("/api/v1/auth/register-admin", json={
            "org_name": test_org_name,
            "org_type": "University",
            "admin_name": "Admin Approvals",
            "email": test_admin_email,
            "password": "password123"
        })
        assert res.status_code == 200
        
        async with AsyncSessionLocal() as db:
            otp_record = (await db.execute(select(OtpVerification).where(OtpVerification.email == test_admin_email))).scalars().first()
            admin_otp = otp_record.otp
            
        res = await client.post("/api/v1/auth/verify-otp", json={
            "email": test_admin_email,
            "otp": admin_otp
        })
        assert res.status_code == 200
        res_data = res.json()["data"]
        org_code = res_data["organization_code"]
        org_id = res_data["organization_id"]
        
        # Seed department
        async with AsyncSessionLocal() as db:
            dept = Department(organization_id=uuid.UUID(org_id), name="Computer Science", is_active=True)
            db.add(dept)
            await db.commit()
            await db.refresh(dept)
            dept_id = str(dept.id)

        # Log in as Admin to get Token
        res = await client.post("/api/v1/auth/login", json={
            "email": test_admin_email,
            "password": "password123"
        })
        assert res.status_code == 200
        admin_token = res.json()["data"]["access_token"]
        admin_headers = {"Authorization": f"Bearer {admin_token}"}

        # 2. Register Faculty (Pending Approval)
        res = await client.post("/api/v1/auth/register", json={
            "full_name": "Faculty Approvals",
            "email": test_faculty_email,
            "password": "password123",
            "organization_code": org_code,
            "department_id": dept_id,
            "device_identifier": "device_original",
            "device_model": "iPhone 13"
        })
        assert res.status_code == 200
        faculty_id = res.json()["data"]["id"]

        # Try logging in as Faculty (should fail: pending approval)
        res = await client.post("/api/v1/auth/login", json={
            "email": test_faculty_email,
            "password": "password123",
            "device_identifier": "device_original",
            "device_model": "iPhone 13"
        })
        assert res.status_code == 401
        assert "pending administrator verification" in res.json()["message"]

        # Check Admin Pending Counts
        res = await client.get("/api/v1/admin/pending-counts", headers=admin_headers)
        assert res.status_code == 200
        counts = res.json()["data"]
        assert counts["registrations"] == 1
        assert counts["device_swaps"] == 0
        assert counts["excusals"] == 0
        assert counts["unread_notifications"] == 1

        # Check Admin Pending Registrations list
        res = await client.get("/api/v1/admin/pending-registrations", headers=admin_headers)
        assert res.status_code == 200
        pending_list = res.json()["data"]
        assert len(pending_list) == 1
        assert pending_list[0]["name"] == "Faculty Approvals"
        assert pending_list[0]["email"] == test_faculty_email
        request_id = pending_list[0]["id"]

        # Approve Faculty Registration
        res = await client.post(f"/api/v1/admin/approve-registration/{request_id}", headers=admin_headers)
        assert res.status_code == 200

        # Faculty Login (should now succeed)
        res = await client.post("/api/v1/auth/login", json={
            "email": test_faculty_email,
            "password": "password123",
            "device_identifier": "device_original",
            "device_model": "iPhone 13"
        })
        assert res.status_code == 200
        faculty_token = res.json()["data"]["access_token"]
        faculty_headers = {"Authorization": f"Bearer {faculty_token}"}

        # 3. New Device Swap Flow
        # Try login from new device (triggers OTP)
        res = await client.post("/api/v1/auth/login", json={
            "email": test_faculty_email,
            "password": "password123",
            "device_identifier": "device_new",
            "device_model": "iPhone 15"
        })
        assert res.status_code == 401
        assert res.json()["message"] == "NEW_DEVICE_OTP_REQUIRED"

        async with AsyncSessionLocal() as db:
            otp_record = (await db.execute(select(OtpVerification).where(OtpVerification.email == test_faculty_email))).scalars().first()
            faculty_otp = otp_record.otp

        # Login with OTP (creates DeviceChangeRequest and blocks)
        res = await client.post("/api/v1/auth/login", json={
            "email": test_faculty_email,
            "password": "password123",
            "device_identifier": "device_new",
            "device_model": "iPhone 15",
            "otp": faculty_otp,
            "device_swap_reason": "Upgraded phone"
        })
        assert res.status_code == 401
        assert "Device change request submitted" in res.json()["message"]

        # Check pending counts again
        res = await client.get("/api/v1/admin/pending-counts", headers=admin_headers)
        assert res.status_code == 200
        counts = res.json()["data"]
        assert counts["registrations"] == 0
        assert counts["device_swaps"] == 1

        # Check list of device swaps
        res = await client.get("/api/v1/admin/pending-device-swaps", headers=admin_headers)
        assert res.status_code == 200
        swaps = res.json()["data"]
        assert len(swaps) == 1
        assert swaps[0]["new_device"] == "iPhone 15"
        assert swaps[0]["reason"] == "Upgraded phone"
        swap_request_id = swaps[0]["id"]

        # Reject the device swap
        res = await client.post(
            f"/api/v1/admin/reject-device-swap/{swap_request_id}",
            headers=admin_headers,
            json={"rejection_reason": "Security policy check failed"}
        )
        assert res.status_code == 200

        # Login from the rejected device should report rejection
        res = await client.post("/api/v1/auth/login", json={
            "email": test_faculty_email,
            "password": "password123",
            "device_identifier": "device_new",
            "device_model": "iPhone 15"
        })
        assert res.status_code == 401
        assert "rejected: Security policy check failed" in res.json()["message"]

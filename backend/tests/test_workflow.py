import pytest
import uuid
import json
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.database.database import AsyncSessionLocal, init_db
from app.models.organization import Organization, Department
from app.models.user import Admin, Faculty
from app.models.request import Device, FacultyRegistrationRequest
from app.models.otp import OtpVerification
from sqlalchemy import select, delete


@pytest.mark.asyncio
async def test_end_to_end_erp_workflow():
    await init_db()
    # 0. Clean up any existing test records to prevent conflicts
    test_org_name = "Test Workflow University"
    test_admin_email = "admin@testuniv.edu"
    test_faculty_college_email = "faculty@testuniv.edu"
    test_faculty_public_email = "faculty_test@gmail.com"
    
    async with AsyncSessionLocal() as db:
        # Delete existing test data
        await db.execute(delete(OtpVerification).where(OtpVerification.email.in_([test_admin_email, test_faculty_college_email, test_faculty_public_email])))
        
        # Find orgs to clean up
        orgs_res = await db.execute(select(Organization).where(Organization.name == test_org_name))
        orgs = orgs_res.scalars().all()
        for org in orgs:
            await db.execute(delete(Device).where(Device.organization_id == org.id))
            await db.execute(delete(FacultyRegistrationRequest).where(FacultyRegistrationRequest.organization_id == org.id))
            await db.execute(delete(Faculty).where(Faculty.organization_id == org.id))
            await db.execute(delete(Admin).where(Admin.organization_id == org.id))
            await db.execute(delete(Department).where(Department.organization_id == org.id))
            await db.execute(delete(Organization).where(Organization.id == org.id))
        await db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Admin Registration (Initiate)
        reg_payload = {
            "org_name": test_org_name,
            "org_type": "University",
            "admin_name": "Admin Tester",
            "email": test_admin_email,
            "password": "password123"
        }
        res = await client.post("/api/v1/auth/register-admin", json=reg_payload)
        assert res.status_code == 200, f"Admin reg initiation failed: {res.json()}"
        assert res.json()["success"] is True
        
        # Verify OTP is created in database
        async with AsyncSessionLocal() as db:
            otp_res = await db.execute(select(OtpVerification).where(OtpVerification.email == test_admin_email))
            otp_record = otp_res.scalars().first()
            assert otp_record is not None
            otp_code = otp_record.otp
            assert len(otp_code) == 6
            
        # 2. Organization Creation & Domain Extraction (Verify OTP)
        verify_payload = {
            "email": test_admin_email,
            "otp": otp_code
        }
        res = await client.post("/api/v1/auth/verify-otp", json=verify_payload)
        assert res.status_code == 200, f"Admin verify OTP failed: {res.json()}"
        res_data = res.json()["data"]
        org_id = res_data["organization_id"]
        org_code = res_data["organization_code"]
        assert org_code is not None
        
        # Verify domain is extracted
        async with AsyncSessionLocal() as db:
            org_db = await db.get(Organization, uuid.UUID(org_id))
            assert org_db is not None
            assert org_db.domain == "testuniv.edu"
            
            # seed an active department for the organization to test faculty registration
            dept = Department(organization_id=org_db.id, name="Computer Science", is_active=True)
            db.add(dept)
            await db.commit()
            await db.refresh(dept)
            dept_id = str(dept.id)

        # 3. Organization Domain Extraction checks (Public domain filtering)
        public_admin_email = "admin_temp@gmail.com"
        reg_payload_public = {
            "org_name": "Public Temp College",
            "org_type": "College",
            "admin_name": "Public Tester",
            "email": public_admin_email,
            "password": "password123"
        }
        res = await client.post("/api/v1/auth/register-admin", json=reg_payload_public)
        assert res.status_code == 200
        
        async with AsyncSessionLocal() as db:
            otp_rec = (await db.execute(select(OtpVerification).where(OtpVerification.email == public_admin_email))).scalars().first()
            public_otp = otp_rec.otp
            
        res = await client.post("/api/v1/auth/verify-otp", json={"email": public_admin_email, "otp": public_otp})
        assert res.status_code == 200
        public_org_id = res.json()["data"]["organization_id"]
        
        async with AsyncSessionLocal() as db:
            public_org = await db.get(Organization, uuid.UUID(public_org_id))
            # Domain must be NULL for public email registrations
            assert public_org.domain is None
            
            # Cleanup public temp org
            await db.execute(delete(Admin).where(Admin.organization_id == uuid.UUID(public_org_id)))
            await db.execute(delete(Organization).where(Organization.id == uuid.UUID(public_org_id)))
            await db.commit()

        # 4. Faculty Registration (College Email) - Auto-detect
        # Call lookup-org with email
        res = await client.get(f"/api/v1/auth/org-lookup?email={test_faculty_college_email}")
        assert res.status_code == 200, f"College email lookup failed: {res.json()}"
        lookup_data = res.json()["data"]
        assert lookup_data["organization_id"] == org_id
        assert len(lookup_data["departments"]) > 0
        assert lookup_data["departments"][0]["id"] == dept_id

        # Perform registration using domain (no code provided)
        fac_reg_payload = {
            "full_name": "College Faculty",
            "email": test_faculty_college_email,
            "password": "password123",
            "department_id": dept_id,
            "device_identifier": "DEVICE_COLLEGE_1",
            "device_model": "iPhone 15",
            "platform": "IOS"
        }
        res = await client.post("/api/v1/auth/register", json=fac_reg_payload)
        assert res.status_code == 200, f"Faculty reg with college email failed: {res.json()}"
        fac_id = res.json()["data"]["id"]

        # 5. Faculty Registration (Public Email) - Require Code
        # Call lookup-org with public email (must fail with Public email detected)
        res = await client.get(f"/api/v1/auth/org-lookup?email={test_faculty_public_email}")
        assert res.status_code == 422, f"Expected 422 for public email lookup, got {res.status_code}: {res.json()}"
        assert "Public email detected" in res.json()["message"]

        # Call lookup-org with code
        res = await client.get(f"/api/v1/auth/org-lookup?code={org_code}")
        assert res.status_code == 200
        assert res.json()["data"]["organization_id"] == org_id

        # Register public email faculty using org_code
        fac_pub_reg_payload = {
            "full_name": "Public Faculty",
            "email": test_faculty_public_email,
            "password": "password123",
            "organization_code": org_code,
            "department_id": dept_id,
            "device_identifier": "DEVICE_PUBLIC_1",
            "device_model": "Pixel 8",
            "platform": "ANDROID"
        }
        res = await client.post("/api/v1/auth/register", json=fac_pub_reg_payload)
        assert res.status_code == 200, f"Faculty reg with public email failed: {res.json()}"
        fac_pub_id = res.json()["data"]["id"]

        # Verify registration requests are pending in DB
        async with AsyncSessionLocal() as db:
            requests = (await db.execute(select(FacultyRegistrationRequest).where(FacultyRegistrationRequest.organization_id == uuid.UUID(org_id)))).scalars().all()
            assert len(requests) == 2
            
            # Find request IDs
            req_college = [r for r in requests if r.faculty_id == uuid.UUID(fac_id)][0]
            req_public = [r for r in requests if r.faculty_id == uuid.UUID(fac_pub_id)][0]

        # 6. Faculty Approval / Rejection Lifecycle
        # Log in as Admin to get token
        res = await client.post("/api/v1/auth/login", json={"email": test_admin_email, "password": "password123"})
        assert res.status_code == 200
        admin_token = res.json()["data"]["access_token"]
        headers = {"Authorization": f"Bearer {admin_token}"}

        # Reject public faculty request
        res = await client.post(f"/api/v1/faculty/approve-registration/{req_public.id}?status=REJECTED", headers=headers)
        assert res.status_code == 200

        # Approve college faculty request
        res = await client.post(f"/api/v1/faculty/approve-registration/{req_college.id}?status=APPROVED", headers=headers)
        assert res.status_code == 200

        # Verify status in database
        async with AsyncSessionLocal() as db:
            fac_coll = await db.get(Faculty, uuid.UUID(fac_id))
            assert fac_coll.status == "ACTIVE"
            
            fac_pub = await db.get(Faculty, uuid.UUID(fac_pub_id))
            assert fac_pub.status == "INACTIVE"

        # 7. Faculty Login Restrictions
        # Try login as rejected public faculty (must fail)
        res = await client.post("/api/v1/auth/login", json={"email": test_faculty_public_email, "password": "password123"})
        assert res.status_code == 401
        assert "rejected" in res.json()["message"].lower()

        # Try login as pending faculty
        temp_pending_email = "pending@testuniv.edu"
        await client.post("/api/v1/auth/register", json={
            "full_name": "Pending Faculty",
            "email": temp_pending_email,
            "password": "password123",
            "department_id": dept_id
        })
        res = await client.post("/api/v1/auth/login", json={"email": temp_pending_email, "password": "password123"})
        assert res.status_code == 401
        assert "pending" in res.json()["message"].lower()

        # 8. Device Binding
        async with AsyncSessionLocal() as db:
            dev = (await db.execute(select(Device).where(Device.faculty_id == uuid.UUID(fac_id), Device.is_active == True))).scalars().first()
            assert dev is not None
            assert dev.device_identifier == "DEVICE_COLLEGE_1"

        # Login with bound device (should succeed directly)
        login_payload = {
            "email": test_faculty_college_email,
            "password": "password123",
            "device_identifier": "DEVICE_COLLEGE_1",
            "device_model": "iPhone 15",
            "platform": "IOS"
        }
        res = await client.post("/api/v1/auth/login", json=login_payload)
        assert res.status_code == 200
        fac_token = res.json()["data"]["access_token"]

        # 9. OTP Verification (New device login)
        new_device_login_payload = {
            "email": test_faculty_college_email,
            "password": "password123",
            "device_identifier": "DEVICE_COLLEGE_2",
            "device_model": "iPhone 16 Pro",
            "platform": "IOS"
        }
        res = await client.post("/api/v1/auth/login", json=new_device_login_payload)
        assert res.status_code == 401
        assert res.json()["message"] == "NEW_DEVICE_OTP_REQUIRED"

        # Retrieve generated device OTP from database
        async with AsyncSessionLocal() as db:
            dev_otp = (await db.execute(select(OtpVerification).where(OtpVerification.email == test_faculty_college_email))).scalars().first()
            assert dev_otp is not None
            otp_code_dev = dev_otp.otp

        # Login again with OTP (submits request and returns 401)
        new_device_login_payload["otp"] = otp_code_dev
        res = await client.post("/api/v1/auth/login", json=new_device_login_payload)
        assert res.status_code == 401
        assert "Device change request submitted" in res.json()["message"]

        # Admin approves the device swap request
        res = await client.get("/api/v1/admin/pending-device-swaps", headers=headers)
        assert res.status_code == 200
        swaps = res.json()["data"]
        assert len(swaps) == 1
        swap_request_id = swaps[0]["id"]

        res = await client.post(f"/api/v1/admin/approve-device-swap/{swap_request_id}", headers=headers)
        assert res.status_code == 200

        # Login again after admin approval (should succeed directly)
        login_after_approval_payload = {
            "email": test_faculty_college_email,
            "password": "password123",
            "device_identifier": "DEVICE_COLLEGE_2",
            "device_model": "iPhone 16 Pro",
            "platform": "IOS"
        }
        res = await client.post("/api/v1/auth/login", json=login_after_approval_payload)
        assert res.status_code == 200
        new_fac_token = res.json()["data"]["access_token"]

        # Verify device bound state in DB
        async with AsyncSessionLocal() as db:
            dev1 = (await db.execute(select(Device).where(Device.device_identifier == "DEVICE_COLLEGE_1"))).scalars().first()
            assert dev1.is_active is False
            dev2 = (await db.execute(select(Device).where(Device.device_identifier == "DEVICE_COLLEGE_2"))).scalars().first()
            assert dev2.is_active is True

        # 10. Dashboard Access
        fac_headers = {"Authorization": f"Bearer {new_fac_token}"}
        res = await client.get("/api/v1/faculty/dashboard-summary", headers=fac_headers)
        assert res.status_code == 200, f"Dashboard access failed: {res.json()}"
        assert res.json()["success"] is True

        # Clean up database after test
        async with AsyncSessionLocal() as db:
            # Delete pending temp faculty
            await db.execute(delete(FacultyRegistrationRequest).where(FacultyRegistrationRequest.faculty_id.in_([
                uuid.UUID(fac_id), uuid.UUID(fac_pub_id)
            ])))
            # Delete devices
            await db.execute(delete(Device).where(Device.faculty_id.in_([
                uuid.UUID(fac_id), uuid.UUID(fac_pub_id)
            ])))
            # Delete faculty
            await db.execute(delete(Faculty).where(Faculty.email.in_([
                test_faculty_college_email, test_faculty_public_email, temp_pending_email
            ])))
            # Delete admin
            await db.execute(delete(Admin).where(Admin.email == test_admin_email))
            # Delete departments
            await db.execute(delete(Department).where(Department.organization_id == uuid.UUID(org_id)))
            # Delete organization
            await db.execute(delete(Organization).where(Organization.id == uuid.UUID(org_id)))
            await db.commit()

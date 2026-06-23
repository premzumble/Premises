import pytest
import uuid
from datetime import datetime, date, time, timezone
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.database.database import AsyncSessionLocal, init_db
from app.models.log import AuditLog, PolicyChangeHistory
from sqlalchemy import select, delete

@pytest.mark.asyncio
async def test_audit_logs_and_pagination_endpoints():
    await init_db()
    
    from app.models.organization import Organization
    from app.models.user import Admin
    from app.core.security import create_access_token
    
    async with AsyncSessionLocal() as db:
        # Cleanup logs
        await db.execute(delete(AuditLog))
        await db.execute(delete(PolicyChangeHistory))
        
        # Cleanup prior test orgs if any
        existing_org = (await db.execute(select(Organization).where(Organization.name == "Audit Test Org"))).scalars().first()
        if existing_org:
            await db.execute(delete(Admin).where(Admin.organization_id == existing_org.id))
            await db.execute(delete(Organization).where(Organization.id == existing_org.id))
            await db.commit()

        org = Organization(
            name="Audit Test Org",
            organization_code="AUDITOR123",
            type="School",
            status="ACTIVE"
        )
        db.add(org)
        await db.flush()
        
        admin = Admin(
            organization_id=org.id,
            full_name="Audit Administrator",
            email="auditor@test.com",
            password_hash="fakehash",
            status="ACTIVE"
        )
        db.add(admin)
        await db.commit()
        await db.refresh(admin)
        
        admin_id = admin.id
        org_id = org.id

    token = create_access_token(admin_id, "ADMIN", org_id)
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Test 1: POST /auth/logout logs the action
        res = await client.post("/api/v1/auth/logout", headers=headers)
        assert res.status_code == 200, f"Logout failed: {res.text}"
        assert res.json()["success"] is True
        
        async with AsyncSessionLocal() as db:
            logs = (await db.execute(select(AuditLog).where(AuditLog.action == "USER_LOGOUT"))).scalars().all()
            assert len(logs) == 1
            assert logs[0].actor_id == admin_id

        # Test 2: PUT /settings/policy logs policy change history
        policy_payload = {
            "allowed_outside_minutes": 45,
            "reminder_1_minutes": 10,
            "reminder_2_minutes": 20,
            "reminder_3_minutes": 30,
            "evaluation_minutes": 20,
            "start_time": "08:00:00",
            "end_time": "16:00:00",
            "half_day_cutoff_time": "13:00:00",
            "absent_cutoff_time": "13:00:00"
        }
        res = await client.put("/api/v1/settings/policy", json=policy_payload, headers=headers)
        assert res.status_code == 200, f"Policy update failed: {res.text}"
        assert res.json()["success"] is True
        
        async with AsyncSessionLocal() as db:
            history = (await db.execute(select(PolicyChangeHistory))).scalars().all()
            assert len(history) > 0
            audit = (await db.execute(select(AuditLog).where(AuditLog.action == "POLICY_UPDATED"))).scalars().all()
            assert len(audit) == 1

        # Test 3: GET /admin/attendance-logs returns paginated structure
        res = await client.get("/api/v1/admin/attendance-logs?page=1&page_size=10", headers=headers)
        assert res.status_code == 200, f"Logs fetch failed: {res.text}"
        data = res.json()["data"]
        assert "items" in data
        assert "page" in data
        assert "total" in data

        # Test 4: GET /admin/export-report returns streaming response
        res = await client.get("/api/v1/admin/export-report?report_type=Daily Attendance Summary", headers=headers)
        assert res.status_code == 200, f"Export failed: {res.text}"
        assert "text/csv" in res.headers["content-type"]
        assert len(res.text) > 0

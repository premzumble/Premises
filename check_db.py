import asyncio
import os
import sys

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.getcwd(), "backend"))

from app.database.database import AsyncSessionLocal
from app.models.organization import Organization, Department
from sqlalchemy import select

async def check():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(Organization).where(Organization.organization_code == 'MAULICOL580'))
        o = res.scalars().first()
        if not o:
            print("Org not found")
            return

        print(f"Org: {o.name}, ID: {o.id}")

        res = await db.execute(select(Department).where(Department.organization_id == o.id))
        depts = res.scalars().all()
        print(f"Total Departments: {len(depts)}")
        for d in depts:
            print(f"Name: {d.name}, Active: {d.is_active}")

if __name__ == "__main__":
    asyncio.run(check())

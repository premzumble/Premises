import asyncio
import os
import sys

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.getcwd(), "backend"))

import app.models.base
from app.database.database import AsyncSessionLocal
from app.models.user import Faculty, Admin
from sqlalchemy import select

async def check():
    async with AsyncSessionLocal() as db:
        print("Admins:")
        res = await db.execute(select(Admin))
        for a in res.scalars().all():
            print(f"- {a.email}")

        print("\nFaculty:")
        res = await db.execute(select(Faculty))
        for f in res.scalars().all():
            print(f"- {f.email}")

if __name__ == "__main__":
    asyncio.run(check())

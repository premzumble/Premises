import asyncio
import os
import sys

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.getcwd(), "backend"))

# MUST import base models to register them
import app.models.base
from app.database.database import AsyncSessionLocal
from app.services.auth_service import AuthService

async def test():
    async with AsyncSessionLocal() as db:
        service = AuthService(db)
        print("Testing lookup_organization(code='MAULICOL580')...")
        try:
            res = await service.lookup_organization(code='MAULICOL580')
            print(f"Success: {res.organization_name}")
            print(f"ID: {res.organization_id}")
            print(f"Departments: {[d.name for d in res.departments]}")
        except Exception as e:
            print(f"Failed: {e}")

        print("\nTesting lookup_organization(code='maulicol580')...")
        try:
            res = await service.lookup_organization(code='maulicol580')
            print(f"Success: {res.organization_name}")
        except Exception as e:
            print(f"Failed: {e}")

if __name__ == "__main__":
    asyncio.run(test())

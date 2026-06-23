from typing import Optional, Any
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import Admin
from app.repositories.base import BaseRepository


class AdminRepository(BaseRepository[Admin]):
    def __init__(self, db: AsyncSession):
        super().__init__(Admin, db)

    async def get_by_email(self, email: str) -> Optional[Admin]:
        stmt = select(Admin).where(Admin.email == email)
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def get_by_email_and_org(self, email: str, organization_id: Any) -> Optional[Admin]:
        stmt = select(Admin).where(Admin.email == email, Admin.organization_id == organization_id)
        result = await self.db.execute(stmt)
        return result.scalars().first()

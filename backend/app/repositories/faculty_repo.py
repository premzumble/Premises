from typing import List, Optional, Any
import uuid
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import Faculty
from app.models.request import Device
from app.repositories.base import BaseRepository


class FacultyRepository(BaseRepository[Faculty]):
    def __init__(self, db: AsyncSession):
        super().__init__(Faculty, db)

    async def get_by_email(self, email: str) -> Optional[Faculty]:
        stmt = select(Faculty).where(Faculty.email == email)
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def get_active_device(self, faculty_id: uuid.UUID) -> Optional[Device]:
        stmt = select(Device).where(Device.faculty_id == faculty_id, Device.is_active == True)
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def get_multi_by_org(
        self,
        organization_id: uuid.UUID,
        *,
        status: Optional[str] = None,
        department_id: Optional[uuid.UUID] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[Faculty]:
        stmt = select(Faculty).where(Faculty.organization_id == organization_id)
        if status:
            stmt = stmt.where(Faculty.status == status)
        if department_id:
            stmt = stmt.where(Faculty.department_id == department_id)
        stmt = stmt.offset(skip).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

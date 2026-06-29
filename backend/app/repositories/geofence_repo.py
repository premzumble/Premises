from typing import List, Optional
import uuid
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.geofence import Geofence, AttendancePolicy
from app.repositories.base import BaseRepository


class GeofenceRepository(BaseRepository[Geofence]):
    def __init__(self, db: AsyncSession):
        super().__init__(Geofence, db)

    async def get_active_by_org(self, organization_id: uuid.UUID) -> List[Geofence]:
        from sqlalchemy.orm import selectinload
        stmt = (
            select(Geofence)
            .where(Geofence.organization_id == organization_id, Geofence.is_active == True)
            .options(selectinload(Geofence.vertices))
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_policy_by_org(self, organization_id: uuid.UUID) -> Optional[AttendancePolicy]:
        stmt = select(AttendancePolicy).where(
            AttendancePolicy.organization_id == organization_id,
            AttendancePolicy.department_id == None
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def get_policy_by_dept(self, organization_id: uuid.UUID, department_id: Optional[uuid.UUID]) -> Optional[AttendancePolicy]:
        """
        Hierarchical policy lookup:
        1. Try fetching department-specific policy.
        2. Fallback to organization-wide default policy.
        """
        # 1. Try Department Policy
        if department_id:
            stmt = select(AttendancePolicy).where(
                AttendancePolicy.organization_id == organization_id,
                AttendancePolicy.department_id == department_id
            )
            result = await self.db.execute(stmt)
            policy = result.scalars().first()
            if policy:
                return policy

        # 2. Fallback to Org Default
        return await self.get_policy_by_org(organization_id)

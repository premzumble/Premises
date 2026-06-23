from typing import Any, List
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.dependencies import get_current_user, require_role, get_db
from app.core.constants import UserRole
from app.core.exceptions import NotFoundException, ConflictException
from app.schemas.base import StandardResponse
from app.schemas.geofence import AttendancePolicyResponse, AttendancePolicyUpdate
from app.schemas.organization import (
    OrganizationSettingsResponse,
    OrganizationSettingsUpdate,
    DepartmentCreate,
    DepartmentResponse,
)
from app.models.geofence import AttendancePolicy
from app.models.organization import OrganizationSettings, Department
from app.models.log import AuditLog, PolicyChangeHistory
from app.repositories.geofence_repo import GeofenceRepository


router = APIRouter()


@router.get("/policy", response_model=StandardResponse[AttendancePolicyResponse])
async def get_policy(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
):
    repo = GeofenceRepository(db)
    policy = await repo.get_policy_by_org(current_user.organization_id)
    if not policy:
        raise NotFoundException("Attendance policy configurations not found.")
        
    return StandardResponse(
        success=True,
        message="Attendance policy loaded successfully.",
        data=AttendancePolicyResponse.model_validate(policy),
    )


@router.put("/policy", response_model=StandardResponse[AttendancePolicyResponse])
async def update_policy(
    data: AttendancePolicyUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    repo = GeofenceRepository(db)
    policy = await repo.get_policy_by_org(current_user.organization_id)
    
    # Track old values
    old_values = {}
    if policy:
        for field in data.model_dump(exclude_unset=True).keys():
            val = getattr(policy, field)
            old_values[field] = str(val) if val is not None else None
    else:
        old_values = {}
        
    if not policy:
        policy_data = data.model_dump(exclude_unset=True)
        policy_data["organization_id"] = current_user.organization_id
        policy = AttendancePolicy(**policy_data)
        db.add(policy)
        await db.flush()
    else:
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(policy, field, value)
        db.add(policy)
        
    # Write details to PolicyChangeHistory and AuditLog
    new_values = {}
    for field, val in data.model_dump(exclude_unset=True).items():
        new_val_str = str(val) if val is not None else None
        new_values[field] = new_val_str
        old_val_str = old_values.get(field)
        if old_val_str != new_val_str:
            history_record = PolicyChangeHistory(
                organization_id=current_user.organization_id,
                policy_id=policy.id,
                changed_by=current_user.id,
                field_name=field,
                old_value=old_val_str,
                new_value=new_val_str
            )
            db.add(history_record)
            
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="POLICY_UPDATED",
        entity_type="ATTENDANCE_POLICY",
        entity_id=policy.id,
        old_value=old_values,
        new_value=new_values
    )
    db.add(audit_log)
        
    await db.commit()
    await db.refresh(policy)
    return StandardResponse(
        success=True,
        message="Attendance policy updated successfully.",
        data=AttendancePolicyResponse.model_validate(policy),
    )



@router.get("/settings", response_model=StandardResponse[OrganizationSettingsResponse])
async def get_settings(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
):
    stmt = select(OrganizationSettings).where(OrganizationSettings.organization_id == current_user.organization_id)
    res = await db.execute(stmt)
    settings = res.scalars().first()
    if not settings:
        raise NotFoundException("Organization settings configurations not found.")
        
    return StandardResponse(
        success=True,
        message="Organization settings loaded.",
        data=OrganizationSettingsResponse.model_validate(settings),
    )


@router.put("/settings", response_model=StandardResponse[OrganizationSettingsResponse])
async def update_settings(
    data: OrganizationSettingsUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    stmt = select(OrganizationSettings).where(OrganizationSettings.organization_id == current_user.organization_id)
    res = await db.execute(stmt)
    settings = res.scalars().first()
    
    # Track old values
    old_values = {}
    if settings:
        for field in data.model_dump(exclude_unset=True).keys():
            old_values[field] = getattr(settings, field)
    else:
        old_values = {}
        
    if not settings:
        settings_data = data.model_dump(exclude_unset=True)
        settings_data["organization_id"] = current_user.organization_id
        settings = OrganizationSettings(**settings_data)
        db.add(settings)
        await db.flush()
    else:
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(settings, field, value)
        db.add(settings)
        
    # Write details to AuditLog
    new_values = data.model_dump(exclude_unset=True)
    audit_log = AuditLog(
        organization_id=current_user.organization_id,
        actor_type="ADMIN",
        actor_id=current_user.id,
        action="SETTINGS_UPDATED",
        entity_type="ORGANIZATION_SETTINGS",
        entity_id=settings.id,
        old_value=old_values,
        new_value=new_values
    )
    db.add(audit_log)
        
    await db.commit()
    await db.refresh(settings)
    return StandardResponse(
        success=True,
        message="Organization settings updated successfully.",
        data=OrganizationSettingsResponse.model_validate(settings),
    )



@router.get("/departments", response_model=StandardResponse[List[DepartmentResponse]])
async def list_departments(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
):
    stmt = select(Department).where(
        Department.organization_id == current_user.organization_id,
        Department.is_active == True
    )
    res = await db.execute(stmt)
    depts = res.scalars().all()
    return StandardResponse(
        success=True,
        message="Departments loaded successfully.",
        data=[DepartmentResponse.model_validate(d) for d in depts],
    )


@router.post("/departments", response_model=StandardResponse[DepartmentResponse])
async def create_department(
    data: DepartmentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    stmt = select(Department).where(
        Department.organization_id == current_user.organization_id,
        Department.name == data.name
    )
    res = await db.execute(stmt)
    existing_dept = res.scalars().first()
    
    if existing_dept:
        if not existing_dept.is_active:
            existing_dept.is_active = True
            existing_dept.description = data.description
            db.add(existing_dept)
            await db.commit()
            await db.refresh(existing_dept)
            return StandardResponse(
                success=True,
                message="Department re-activated successfully.",
                data=DepartmentResponse.model_validate(existing_dept),
            )
        else:
            raise ConflictException("Department with this name already exists.")

    dept_data = data.model_dump()
    dept_data["organization_id"] = current_user.organization_id
    dept = Department(**dept_data)
    db.add(dept)
    await db.commit()
    await db.refresh(dept)
    
    return StandardResponse(
        success=True,
        message="Department created successfully.",
        data=DepartmentResponse.model_validate(dept),
    )


@router.delete("/departments/{dept_id}", response_model=StandardResponse[dict])
async def delete_department(
    dept_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    stmt = select(Department).where(
        Department.id == dept_id,
        Department.organization_id == current_user.organization_id
    )
    res = await db.execute(stmt)
    dept = res.scalars().first()
    if not dept:
        raise NotFoundException("Department not found.")
        
    # Soft delete department
    dept.is_active = False
    db.add(dept)
    await db.commit()
    
    return StandardResponse(
        success=True,
        message="Department deleted successfully.",
        data={},
    )

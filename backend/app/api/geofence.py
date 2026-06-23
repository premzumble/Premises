from typing import Any, List
import uuid
import httpx
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.dependencies import get_current_user, require_role, get_db
from app.core.constants import UserRole
from app.core.exceptions import NotFoundException
from app.schemas.base import StandardResponse
from app.schemas.geofence import GeofenceCreate, GeofenceResponse
from app.models.geofence import Geofence
from app.repositories.geofence_repo import GeofenceRepository

router = APIRouter()


@router.get("/search", response_model=StandardResponse[List[dict]])
async def search_location(
    query: str = Query(..., min_length=1),
    current_user: Any = Depends(get_current_user),
):
    try:
        from urllib.parse import quote
        from app.core.config import settings
        
        # If Google Maps API key is configured, use Google Geocoding REST API
        if settings.GOOGLE_MAPS_API_KEY and settings.GOOGLE_MAPS_API_KEY.strip():
            api_key = settings.GOOGLE_MAPS_API_KEY.strip()
            url = f"https://maps.googleapis.com/maps/api/geocode/json?address={quote(query)}&key={api_key}"
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(url)
                if response.status_code == 200:
                    data = response.json()
                    results = []
                    for item in data.get("results", []):
                        lat_val = item.get("geometry", {}).get("location", {}).get("lat")
                        lng_val = item.get("geometry", {}).get("location", {}).get("lng")
                        results.append({
                            "display_name": item.get("formatted_address", ""),
                            "lat": str(lat_val) if lat_val is not None else "",
                            "lon": str(lng_val) if lng_val is not None else "",
                        })
                    return StandardResponse(
                        success=True,
                        message="Search results fetched successfully via Google Maps.",
                        data=results,
                    )
                
                return StandardResponse(
                    success=False,
                    message=f"Google Geocoding failed with status {response.status_code}",
                    data=[],
                )

        # Fallback to OpenStreetMap/Nominatim
        async with httpx.AsyncClient(timeout=10.0) as client:
            headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
            url = f"https://nominatim.openstreetmap.org/search?q={quote(query)}&format=json&limit=5"
            response = await client.get(url, headers=headers)
            
            if response.status_code == 200:
                data = response.json()
                results = [
                    {
                        "display_name": item.get("display_name", ""),
                        "lat": item.get("lat"),
                        "lon": item.get("lon"),
                    }
                    for item in data
                ]
                return StandardResponse(
                    success=True,
                    message="Search results fetched successfully.",
                    data=results,
                )
            
            return StandardResponse(
                success=False,
                message=f"Location search failed with status {response.status_code}",
                data=[],
            )
    except Exception as e:
        return StandardResponse(
            success=False,
            message=f"Location search failed: {str(e)}",
            data=[],
        )


@router.get("/", response_model=StandardResponse[List[GeofenceResponse]])
async def list_geofences(
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
):
    repo = GeofenceRepository(db)
    geofences = await repo.get_active_by_org(current_user.organization_id)
    responses = [GeofenceResponse.model_validate(g) for g in geofences]
    return StandardResponse(
        success=True,
        message="Active campus geofences fetched successfully.",
        data=responses,
    )


@router.post("/", response_model=StandardResponse[GeofenceResponse])
async def create_geofence(
    data: GeofenceCreate,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    repo = GeofenceRepository(db)
    # Deactivate existing active geofences for this organization
    active_gfs = await repo.get_active_by_org(current_user.organization_id)
    for old_gf in active_gfs:
        old_gf.is_active = False
        db.add(old_gf)

    gf_data = data.model_dump()
    gf_data["organization_id"] = current_user.organization_id
    gf_data["updated_by"] = current_user.email
    
    gf = await repo.create(obj_in_data=gf_data)
    await db.commit()
    await db.refresh(gf)
    
    return StandardResponse(
        success=True,
        message="Campus geofence created successfully.",
        data=GeofenceResponse.model_validate(gf),
    )


@router.delete("/{geofence_id}", response_model=StandardResponse[dict])
async def delete_geofence(
    geofence_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Any = Depends(get_current_user),
    _guard: None = Depends(require_role([UserRole.ADMIN.value])),
):
    repo = GeofenceRepository(db)
    gf = await repo.get(geofence_id)
    if not gf or gf.organization_id != current_user.organization_id:
        raise NotFoundException("Geofence not found.")
        
    await repo.remove(id=geofence_id)
    await db.commit()
    return StandardResponse(
        success=True,
        message="Geofence deleted successfully.",
        data={},
    )

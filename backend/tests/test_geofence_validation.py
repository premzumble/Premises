import pytest
from app.schemas.geofence import GeofenceCreate, GeofenceVertexBase
from app.services.attendance_service import AttendanceService
from pydantic import ValidationError

def test_circle_geofence_validation():
    # Valid circle
    gf = GeofenceCreate(
        name="Valid Circle",
        geofence_type="circle",
        latitude=18.403817,
        longitude=76.560943,
        radius_meters=100.0
    )
    assert gf.geofence_type == "circle"
    
    # Missing coordinates
    with pytest.raises(ValidationError):
        GeofenceCreate(
            name="Invalid Circle",
            geofence_type="circle",
            radius_meters=100.0
        )

    # Radius too small
    with pytest.raises(ValidationError):
        GeofenceCreate(
            name="Too Small Circle",
            geofence_type="circle",
            latitude=18.403817,
            longitude=76.560943,
            radius_meters=5.0
        )

def test_polygon_geofence_validation():
    # Valid polygon (square around center)
    valid_vertices = [
        GeofenceVertexBase(latitude=18.401, longitude=76.559),
        GeofenceVertexBase(latitude=18.405, longitude=76.559),
        GeofenceVertexBase(latitude=18.405, longitude=76.563),
        GeofenceVertexBase(latitude=18.401, longitude=76.563)
    ]
    gf = GeofenceCreate(
        name="Valid Polygon",
        geofence_type="polygon",
        vertices=valid_vertices
    )
    assert gf.geofence_type == "polygon"
    assert len(gf.vertices) == 4

    # Self-intersecting polygon (hourglass shape)
    invalid_vertices = [
        GeofenceVertexBase(latitude=18.401, longitude=76.559),
        GeofenceVertexBase(latitude=18.405, longitude=76.563), # Crosses edge
        GeofenceVertexBase(latitude=18.405, longitude=76.559),
        GeofenceVertexBase(latitude=18.401, longitude=76.563)
    ]
    with pytest.raises(ValidationError) as excinfo:
        GeofenceCreate(
            name="Hourglass Polygon",
            geofence_type="polygon",
            vertices=invalid_vertices
        )
    assert "Self-intersecting polygon boundaries are invalid" in str(excinfo.value)

    # Duplicate consecutive vertices
    invalid_consecutive = [
        GeofenceVertexBase(latitude=18.401, longitude=76.559),
        GeofenceVertexBase(latitude=18.401, longitude=76.559), # consecutive duplicate
        GeofenceVertexBase(latitude=18.405, longitude=76.559),
        GeofenceVertexBase(latitude=18.401, longitude=76.563)
    ]
    with pytest.raises(ValidationError) as excinfo:
        GeofenceCreate(
            name="Consecutive Duplicate Polygon",
            geofence_type="polygon",
            vertices=invalid_consecutive
        )
    assert "Duplicate consecutive vertices are invalid" in str(excinfo.value)

    # Degenerate (less than 3 unique vertices)
    degenerate = [
        GeofenceVertexBase(latitude=18.401, longitude=76.559),
        GeofenceVertexBase(latitude=18.405, longitude=76.563),
        GeofenceVertexBase(latitude=18.401, longitude=76.559) # only 2 unique
    ]
    with pytest.raises(ValidationError) as excinfo:
        GeofenceCreate(
            name="Degenerate Polygon",
            geofence_type="polygon",
            vertices=degenerate
        )
    assert "A polygon geofence must have at least 3 unique vertices" in str(excinfo.value)

def test_ray_casting_pip_math():
    # Define a polygon (triangle)
    poly = [
        (0.0, 0.0),
        (0.0, 10.0),
        (10.0, 0.0)
      ]
    
    # Point inside triangle
    assert AttendanceService._is_point_in_polygon(2.0, 2.0, poly) is True
    
    # Point exactly on vertex
    assert AttendanceService._is_point_in_polygon(0.0, 0.0, poly) is True
    
    # Point exactly on edge
    assert AttendanceService._is_point_in_polygon(0.0, 5.0, poly) is True
    
    # Point outside triangle
    assert AttendanceService._is_point_in_polygon(8.0, 8.0, poly) is False
    assert AttendanceService._is_point_in_polygon(-1.0, -1.0, poly) is False

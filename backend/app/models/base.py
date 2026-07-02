# app/models/base.py
#
# This module serves two purposes:
# 1. Re-exports `Base` from app.database.database so all model files can do:
#      from app.models.base import Base
#    without directly depending on the database layer.
#
# 2. Imports ALL models (after Base is defined) so that SQLAlchemy's metadata
#    registry is populated when init_db() calls metadata.create_all().
#    These imports MUST stay at the bottom to avoid circular import issues.

from app.database.database import Base  # noqa: F401 — re-export Base

# ---------------------------------------------------------------------------
# Import all models to register their tables on the shared Base.metadata.
# These imports are intentionally late (bottom of file) to prevent circular
# imports since each model imports `Base` from this file.
# ---------------------------------------------------------------------------
from app.models.organization import Organization, OrganizationSettings, Department  # noqa: F401
from app.models.user import Admin, Faculty                                          # noqa: F401
from app.models.geofence import Geofence, AttendancePolicy, GeofenceVertex                  # noqa: F401
from app.models.attendance import AttendanceRecord, LocationEvent                   # noqa: F401
from app.models.request import (                                                    # noqa: F401
    Device, ReasonRequest, FacultyRegistrationRequest, DeviceChangeRequest
)
from app.models.notification import Notification                                    # noqa: F401
from app.models.log import AuditLog, PolicyChangeHistory                            # noqa: F401
from app.models.otp import OtpVerification, EmailLog                                  # noqa: F401

__all__ = ["Base"]

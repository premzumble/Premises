import logging
import re
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi.errors import RateLimitExceeded
from app.core.config import settings
from app.core.exceptions import BaseAppException
from app.core.limiter import limiter
from app.database.database import init_db
from app.api import auth, admin, faculty, attendance, geofence, settings as api_settings

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("app.main")


# Regex pattern for allowed origins in dev mode:
# - localhost / 127.0.0.1 (browser/emulator)
# - 10.x.x.x / 192.168.x.x / 172.16-31.x.x  (physical device on local Wi-Fi)
_LOCALHOST_ORIGIN_RE = re.compile(
    r"^https?://(localhost|127\.0\.0\.1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+)(:\d+)?$"
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing database session engines...")
    try:
        await init_db()
        logger.info("Database tables synchronized successfully.")
    except Exception as e:
        logger.critical(f"\n{'='*80}\nCRITICAL DATABASE ERROR: {e}\n{'='*80}\n")
        import sys
        sys.exit(1)
    yield
    logger.info("Shutting down backend services...")


app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Multi-tenant Smart Geofence Attendance Monitoring System Backend API",
    version="1.0.0",
    lifespan=lifespan,
)
app.state.limiter = limiter



# ---------------------------------------------------------------------------
# CORS Middleware
# In DEV_MODE: dynamically allow any localhost origin (any port).
# In production: use the explicit CORS_ORIGINS list from config/.env.
#
# IMPORTANT: We cannot use allow_origins=["*"] with allow_credentials=True.
# Instead, in dev mode we use a custom middleware that echoes back the
# request's Origin header if it matches localhost.
# ---------------------------------------------------------------------------

if settings.DEV_MODE:
    # Custom CORS middleware that approves any localhost origin dynamically
    from starlette.middleware.base import BaseHTTPMiddleware
    from starlette.types import ASGIApp

    class DevCORSMiddleware(BaseHTTPMiddleware):
        async def dispatch(self, request: Request, call_next):
            origin = request.headers.get("origin", "")
            is_localhost = bool(_LOCALHOST_ORIGIN_RE.match(origin))

            # Handle preflight OPTIONS request
            if request.method == "OPTIONS":
                headers = {
                    "Access-Control-Allow-Origin": origin if is_localhost else "",
                    "Access-Control-Allow-Credentials": "true",
                    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, X-Requested-With",
                    "Access-Control-Max-Age": "86400",
                }
                return JSONResponse(status_code=200, content={}, headers=headers)

            response = await call_next(request)

            if is_localhost:
                response.headers["Access-Control-Allow-Origin"] = origin
                response.headers["Access-Control-Allow-Credentials"] = "true"
                response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
                response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, Accept, X-Requested-With"

            return response

    app.add_middleware(DevCORSMiddleware)
    logger.info("DEV_MODE: Dynamic localhost CORS middleware enabled.")
else:
    # Production: use explicit allow-list from config
    origins = (
        list(settings.CORS_ORIGINS)
        if isinstance(settings.CORS_ORIGINS, list)
        else [settings.CORS_ORIGINS]
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    logger.info(f"Production CORS: allowed origins = {origins}")


# ---------------------------------------------------------------------------
# Global Exception Handlers
# ---------------------------------------------------------------------------

@app.exception_handler(RateLimitExceeded)
async def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={
            "success": False,
            "message": "Too many requests. Please wait a moment and try again.",
            "data": {},
        },
    )


@app.exception_handler(BaseAppException)

async def app_exception_handler(request: Request, exc: BaseAppException):
    logger.warning(
        f"[{request.method}] {request.url.path} → {exc.status_code} {exc.message}"
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "success": False,
            "message": exc.message,
            "data": exc.data,
        },
    )


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.error(
        f"Unhandled exception on [{request.method}] {request.url.path}: {exc}",
        exc_info=True,
    )
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "message": "An unexpected server error occurred. Please contact support.",
            "data": {},
        },
    )


# ---------------------------------------------------------------------------
# API Routers
# ---------------------------------------------------------------------------
app.include_router(auth.router,         prefix=f"{settings.API_V1_STR}/auth",       tags=["Authentication"])
app.include_router(admin.router,        prefix=f"{settings.API_V1_STR}/admin",      tags=["Admin Portal"])
app.include_router(faculty.router,      prefix=f"{settings.API_V1_STR}/faculty",    tags=["Faculty Management"])
app.include_router(attendance.router,   prefix=f"{settings.API_V1_STR}/attendance", tags=["Attendance Lifecycle"])
app.include_router(geofence.router,     prefix=f"{settings.API_V1_STR}/geofence",   tags=["Geofencing Configuration"])
app.include_router(api_settings.router, prefix=f"{settings.API_V1_STR}/settings",   tags=["Settings & Policies"])


@app.get("/", tags=["Health"])
async def root():
    return {
        "project": settings.PROJECT_NAME,
        "status": "online",
        "version": "1.0.0",
        "docs_url": "/docs",
        "dev_mode": settings.DEV_MODE,
    }


@app.get("/health", tags=["Health"])
async def health_check():
    """Simple health check endpoint — useful for frontend connectivity testing."""
    return {"status": "ok", "service": settings.PROJECT_NAME}


@app.get("/download-apk", tags=["Utility"])
async def download_apk():
    """Download the latest compiled release APK of the Premises client application."""
    import os
    apk_path = os.path.abspath(
        os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
            "build", "app", "outputs", "flutter-apk", "app-release.apk"
        )
    )
    if not os.path.exists(apk_path):
        return JSONResponse(
            status_code=404,
            content={
                "success": False,
                "message": "APK file not found. Please compile the application first.",
                "data": {},
            }
        )
    return FileResponse(
        path=apk_path,
        media_type="application/vnd.android.package-archive",
        filename="premises-release.apk"
    )


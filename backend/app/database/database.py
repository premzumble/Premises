import logging
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import declarative_base
from app.core.config import settings

logger = logging.getLogger("app.database")

Base = declarative_base()

# ---------------------------------------------------------------------------
# Engine setup — PostgreSQL is mandatory
# ---------------------------------------------------------------------------
try:
    engine = create_async_engine(
        settings.DATABASE_URL,
        echo=False,
        future=True,
        pool_size=10,
        max_overflow=5,
        pool_pre_ping=True,
    )
    logger.info("Database engine created for PostgreSQL.")
except Exception as e:
    logger.critical(f"Cannot initialize database engine: {e}")
    raise RuntimeError(
        "PostgreSQL is not running. Please start PostgreSQL and restart the backend."
    ) from e

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def init_db() -> None:
    """
    Verify connectivity to the database and ensure base tables exist.
    """
    from app.models.base import Base as ModelBase  # noqa: F401
    from sqlalchemy.engine import make_url

    try:
        url = make_url(settings.DATABASE_URL)
    except Exception as parse_err:
        logger.critical(f"Invalid DATABASE_URL format: {parse_err}")
        raise RuntimeError(
            f"Configuration Error: Invalid DATABASE_URL format. Please check your backend/.env file."
        ) from parse_err

    # Print startup logging details
    env_name = "Development" if settings.DEV_MODE else "Production"
    logger.info("=" * 60)
    logger.info(f"Project: {settings.PROJECT_NAME}")
    logger.info(f"Environment: {env_name}")
    logger.info("Database:")
    logger.info(f"  Host: {url.host}")
    logger.info(f"  Port: {url.port}")
    logger.info(f"  Database: {url.database}")

    try:
        # Verify connection and ensure base metadata is applied
        async with engine.begin() as conn:
            from sqlalchemy import text
            await conn.execute(text("SELECT 1"))
            await conn.run_sync(ModelBase.metadata.create_all)

        logger.info("  Connection: Successful")
        logger.info("=" * 60)
        logger.info("Database connection verified successfully.")

    except Exception as e:
        logger.critical("  Connection: Failed")
        logger.info("=" * 60)
        logger.critical(f"Database connection failed: {e}")

        # Check if database does not exist
        err_msg = str(e).lower()
        if "database" in err_msg and ("does not exist" in err_msg or "3d000" in err_msg):
            raise RuntimeError(
                f"PostgreSQL Connection Error: The database '{url.database}' does not exist on "
                f"PostgreSQL server at '{url.host}:{url.port}'. Please create the database first."
            ) from e
        else:
            raise RuntimeError(
                "PostgreSQL is not running. Please start PostgreSQL and restart the backend."
            ) from e



import pytest
import asyncio
from app.database.database import engine

@pytest.fixture(autouse=True, scope="function")
def cleanup_database_engine():
    yield
    try:
        asyncio.run(engine.dispose())
    except Exception:
        pass

import json
import os
from pathlib import Path
from typing import List, Union
from dotenv import load_dotenv
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Base directory of the backend (where .env is located)
BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
env_path = BACKEND_DIR / ".env"

if not env_path.exists():
    raise RuntimeError(
        f"Configuration error: .env file not found at '{env_path}'. "
        "Please create a .env file in the backend directory."
    )

# Load environment variables from .env
load_dotenv(dotenv_path=env_path)

# Enforce required environment variables immediately
missing_vars = []
for var in ["DATABASE_URL", "JWT_SECRET"]:
    val = os.environ.get(var)
    if not val or val.strip() == "":
        missing_vars.append(var)

if missing_vars:
    raise RuntimeError(
        f"Configuration Error: The following required environment variables are missing or empty: "
        f"{', '.join(missing_vars)}. Please define them in your backend/.env file."
    )


class Settings(BaseSettings):
    PROJECT_NAME: str = "Premises"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    GOOGLE_MAPS_API_KEY: str = ""

    # Dev Mode: when True, all localhost origins are allowed dynamically
    DEV_MODE: bool = True

    # CORS Origins — used as static fallback in non-dev mode
    CORS_ORIGINS: Union[List[str], str] = [
        "http://localhost:57535",
        "http://localhost:8080",
        "http://localhost:3000",
        "http://localhost:5000",
        "http://127.0.0.1:57535",
        "http://127.0.0.1:8080",
    ]

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> Union[List[str], str]:
        if isinstance(v, str) and not v.startswith("["):
            return [i.strip() for i in v.split(",")]
        elif isinstance(v, str) and v.startswith("["):
            try:
                return json.loads(v)
            except Exception:
                return ["http://localhost:8080"]
        return v

    model_config = SettingsConfigDict(
        env_file=str(env_path),
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()

# Premises Backend (FastAPI)

Welcome to the backend service for the **Premises** Smart Geofence Attendance Monitoring System. This is a multi-tenant enterprise backend built using FastAPI, SQLAlchemy 2.0 (async), Pydantic, and PostgreSQL.

---

## Technical Stack

* **Core**: Python 3.10+ & FastAPI
* **Database & ORM**: PostgreSQL & SQLAlchemy 2.0 (Async Engine via `asyncpg`)
* **Validations**: Pydantic v2
* **Authentication**: JWT Authorization (Access & Refresh Tokens) & Bcrypt Password Hashing
* **Server**: Uvicorn

---

## Directory Structure

The project implements a clean layered architecture:
```
backend/
├── app/
│   ├── core/           # Configuration, Security, and Exceptions
│   ├── database/       # Engine creation and session yields
│   ├── models/         # SQLAlchemy 2.0 Declarative Models
│   ├── schemas/        # Pydantic validation schemas
│   ├── repositories/   # Base and specialized database query classes
│   ├── services/       # Core business rule evaluators (distance checks)
│   ├── api/            # Version 1 Endpoint Routers
│   └── main.py         # Application root entrypoint
├── requirements.txt    # Library dependencies
├── .env                # App settings and environment credentials
└── README.md           # This setup manual
```

---

## Getting Started

### 1. Environment Configurations
Configure your database connection and secrets in `backend/.env`.

Default fallbacks are pre-configured:
```env
PROJECT_NAME="Premises"
API_V1_STR="/api/v1"
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5432/premises"
JWT_SECRET="09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7"
```

*(Note: If a connection to PostgreSQL cannot be established on startup, the application logs a warning and falls back to a local async SQLite database file `premises_fallback.db` for instant offline testing and development).*

### 2. Local Setup
Create a virtual environment, activate it, and install python dependencies:
```bash
cd backend
python -m venv venv

# On Windows:
venv\Scripts\activate
# On Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt
```

### 3. Running the Server
Boot the FastAPI application using Uvicorn:
```bash
uvicorn app.main:app --reload --port 8000
```

---

## API Documentation

FastAPI compiles interactive API documentation automatically:
* **Swagger UI (Interactive Playground)**: [http://localhost:8000/docs](http://localhost:8000/docs)
* **ReDoc (Detailed Specs)**: [http://localhost:8000/redoc](http://localhost:8000/redoc)

---

## Layered Architecture Code Flow

To keep database queries, business rules, and HTTP endpoints strictly isolated:
1. **API Router** (`app/api/`): Accepts request payloads, performs authentication verification checks via guards, and delegates to the Service.
2. **Service Layer** (`app/services/`): Implements business validations (e.g. Haversine geofence boundary checks, device locks, time cutoff statuses) and calls Repositories.
3. **Repository Layer** (`app/repositories/`): Conducts raw database queries using SQLAlchemy 2.0 select and insert statements.
4. **Declarative Models** (`app/models/`): Houses DB schemas and structural relationship declarations.

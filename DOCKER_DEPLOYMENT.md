# Premises Production Docker Deployment

This document provides instructions for deploying the **Premises** backend using Docker and Docker Compose.

## Project Structure
- `backend/Dockerfile`: Production image definition (Python 3.11 Slim).
- `docker-compose.yml`: Service orchestration.
- `deploy.sh` / `deploy.ps1`: Automated deployment scripts.
- `backend/.env.example`: Configuration template.

## Prerequisites
- Docker Engine installed.
- Docker Compose plugin installed.
- PostgreSQL database accessible (either on host or another container).

## Configuration
Before deploying, you must set up the environment variables:
1. Navigate to the `backend` directory.
2. Copy `.env.example` to `.env`.
3. Edit `.env` and fill in the required values:
   - `DATABASE_URL`: Your PostgreSQL connection string.
   - `JWT_SECRET`: A secure random string for token signing.
   - `DEV_MODE`: Set to `False` for production environments.

## Deployment Commands

### Building and Running
To build the image and start the container in detached mode:
```bash
docker compose up --build -d
```

### Stopping
To stop and remove the container:
```bash
docker compose down
```

### Restarting
To restart the backend:
```bash
docker compose restart backend
```

### Updating
To pull the latest code and rebuild:
```bash
git pull
docker compose up --build -d
```

### Checking Logs
To view live logs:
```bash
docker compose logs -f backend
```

## Production Details
- **Port**: The backend is exposed on port **8019**.
- **Healthcheck**: Docker will monitor `http://localhost:8019/health` to ensure the service is healthy.
- **User**: The application runs under a non-privileged user `premises` for security.
- **Restart Policy**: `unless-stopped` ensures the backend starts automatically after a reboot.

## Deployment on a VPS / Remote Server
1. Clone the repository to the server.
2. Configure `backend/.env` with production database credentials.
3. Run `./deploy.sh`.
4. (Optional) Configure a reverse proxy like Nginx or Traefik to handle SSL/TLS on port 80/443 and forward traffic to port 8019.

## Troubleshooting
- **Database Connection**: Ensure the `DATABASE_URL` in `.env` is reachable from within the Docker container. (Use host IP instead of `localhost` if DB is on host).
- **Port Conflict**: If port 8019 is already in use, modify the mapping in `docker-compose.yml`.
- **Environment Variables**: If the backend fails to start, verify that all required variables in `backend/.env` are present.

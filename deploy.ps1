# Premises Production Deployment Script (Windows PowerShell)

Write-Host "--- Starting Premises Deployment ---" -ForegroundColor Cyan

# 1. Ensure .env exists
if (-not (Test-Path "backend/.env")) {
    Write-Host "Error: backend/.env file not found." -ForegroundColor Red
    Write-Host "Please create it using backend/.env.example as a template." -ForegroundColor Yellow
    exit 1
}

# 2. Stop existing containers
Write-Host "Stopping existing containers..."
docker compose down

# 3. Build and start containers
Write-Host "Building and starting containers in detached mode..."
docker compose up --build -d

# 4. Check status
Write-Host "Checking container status..."
docker compose ps

# 5. Check logs for initial errors
Write-Host "Waiting for backend to initialize (5s)..."
Start-Sleep -Seconds 5
docker compose logs backend --tail 20

Write-Host "Deployment complete. Backend should be reachable at port 8019." -ForegroundColor Green

#!/bin/bash

# Premises Production Deployment Script (Linux)

echo "--- Starting Premises Deployment ---"

# 1. Ensure .env exists
if [ ! -f backend/.env ]; then
    echo "Error: backend/.env file not found."
    echo "Please create it using backend/.env.example as a template."
    exit 1
fi

# 2. Stop existing containers
echo "Stopping existing containers..."
docker compose down

# 3. Build and start containers
echo "Building and starting containers in detached mode..."
docker compose up --build -d

# 4. Check status
echo "Checking container status..."
docker compose ps

# 5. Check logs for initial errors
echo "Waiting for backend to initialize (5s)..."
sleep 5
docker compose logs backend --tail 20

echo "Deployment complete. Backend should be reachable at port 8019."

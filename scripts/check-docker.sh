#!/bin/bash
set -euo pipefail

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Docker is not running."
        
        # Check if we're using Colima or Docker Desktop
        if command -v colima &> /dev/null; then
            echo "Starting Colima..."
            
            # Check if Colima is already running
            if colima status &>/dev/null; then
                echo "Colima is already running but Docker is not accessible."
                echo "Trying to restart Colima..."
                colima stop
                sleep 2
            fi
            
            # Start Colima with appropriate resources
            colima start --cpu 4 --memory 8 --disk 60
            
            # Wait for Docker to be ready (up to 60 seconds)
            echo "Waiting for Docker daemon to be ready..."
            for i in {1..60}; do
                if docker info >/dev/null 2>&1; then
                    echo "Colima started successfully!"
                    return 0
                fi
                # Show progress every 5 seconds
                if [ $((i % 5)) -eq 0 ]; then
                    echo "Still waiting... ($i/60 seconds)"
                fi
                sleep 1
            done
            
            echo "ERROR: Docker daemon failed to start within 60 seconds."
            echo "Please check Colima status with: colima status"
            return 1
            
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # Fallback to Docker Desktop if Colima is not installed
            echo "Colima not found. Trying Docker Desktop..."
            
            if open -a Docker 2>/dev/null; then
                # Wait for Docker to start (up to 60 seconds)
                echo "Waiting for Docker Desktop to start..."
                for i in {1..60}; do
                    if docker info >/dev/null 2>&1; then
                        echo "Docker Desktop started successfully!"
                        return 0
                    fi
                    # Show progress every 5 seconds
                    if [ $((i % 5)) -eq 0 ]; then
                        echo "Still waiting... ($i/60 seconds)"
                    fi
                    sleep 1
                done
                echo "ERROR: Docker Desktop failed to start within 60 seconds."
                return 1
            else
                echo "ERROR: Neither Colima nor Docker Desktop found!"
                echo "Please run: ./scripts/setup-colima.sh"
                return 1
            fi
        else
            echo "ERROR: Docker is not running!"
            echo "Please start Docker manually."
            return 1
        fi
    fi
    return 0
}

# Run the check
check_docker
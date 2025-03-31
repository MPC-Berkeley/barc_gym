#!/bin/bash

# Configurable variables
CARLA_PATH="CARLA/Carla-0.10.0-Linux-Shipping"
REPO_DIR="barc_gym"
CARLA_QUALITY="Low"
WAIT_TIME=30
SKIP_CARLA_LAUNCH=0

# Step 1: Optional CARLA launch
if [ "$SKIP_CARLA_LAUNCH" -eq 0 ]; then
    if ! pgrep -f "CarlaUnreal" > /dev/null; then
        echo "Starting CARLA with $CARLA_QUALITY quality..."
        cd "$CARLA_PATH" || exit 1
        ./CarlaUnreal.sh -quality-level="$CARLA_QUALITY" &
        CARLA_PID=$!
        echo "Waiting $WAIT_TIME seconds for initialization..."
        sleep "$WAIT_TIME"
        cd ../..
    else
        echo "CARLA is already running. Skipping launch."
    fi
else
    echo "Skipping CARLA launch as requested."
fi

# Step 2: Run Python script
echo "Running BARC environment test..."
cd "$REPO_DIR" || exit 1
python test_barc_env.py --controller pid
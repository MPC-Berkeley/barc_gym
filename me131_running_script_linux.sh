# Step 10: Run CARLA Simulator and Python script
echo "Running CARLA Simulator..."
cd CARLA/Carla-0.10.0-Linux-Shipping

# Check if CARLA is already running
if ! pgrep -f "CarlaUnreal" > /dev/null; then
    # CARLA is not running, start it
    echo "Starting CarlaUnreal.sh with low quality settings..."
    ./CarlaUnreal.sh -quality-level=Low &
    CARLA_PID=$!
    echo "Waiting 30 seconds for CARLA to initialize..."
    sleep 30
else
    # CARLA is already running
    echo "CARLA simulator is already running. Skipping launch..."
fi

echo "Running PID script in gym-carla..."
cd ../../"$REPO_DIR"
# python run_pid_carla_gym.py --town L_track
python test_barc_env.py --controller pid
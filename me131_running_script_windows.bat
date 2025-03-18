:: Step 10: Run CARLA Simulator and Python script
echo Running CARLA Simulator...
cd CARLA\Carla-0.10.0-Win64-Shipping

:: Check if CARLA is already running
tasklist /FI "IMAGENAME eq CarlaUnreal.exe" 2>NUL | find /I /N "CarlaUnreal.exe">NUL
if %ERRORLEVEL% NEQ 0 (
    :: CARLA is not running, start it
    echo Starting CarlaUnreal.exe with low quality settings...
    start "" "CarlaUnreal.exe" -quality-level=Low
    echo Waiting 30 seconds for CARLA to initialize...
    timeout /t 30 /nobreak >NUL
) else (
    :: CARLA is already running
    echo CARLA simulator is already running. Skipping launch...
)

echo Running PID script in gym-carla...
cd ..\..\barc_gym
:: python run_pid_carla_gym.py --town L_track
python test_barc_env.py --controller pid



@echo off
setlocal

:: Configurable Variables
SET CARLA_PATH=CARLA\Carla-0.10.0-Win64-Shipping
SET SCRIPT_PATH=barc_gym
SET CARLA_QUALITY=Low
SET WAIT_TIME=30
SET SKIP_CARLA_LAUNCH=0

:: Step 1: Optional CARLA launch
IF "%SKIP_CARLA_LAUNCH%"=="0" (
    tasklist /FI "IMAGENAME eq CarlaUnreal.exe" | find "CarlaUnreal.exe" >NUL || (
        echo Starting CARLA with %CARLA_QUALITY% quality...
        start "" "%CARLA_PATH%\CarlaUnreal.exe" -quality-level=%CARLA_QUALITY%
        echo Waiting %WAIT_TIME% seconds for initialization...
        timeout /t %WAIT_TIME% /nobreak >NUL
    )
) ELSE (
    echo Skipping CARLA launch as requested.
)

:: Step 2: Run Python script
echo Running BARC environment test...
cd %SCRIPT_PATH%
python test_barc_env.py --controller pid

endlocal
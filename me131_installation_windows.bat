@echo off
setlocal EnableDelayedExpansion

:: Batch script to set up CARLA simulation environment on Windows (with optional steps)

:: Configurable Variables (users can modify these)
SET ENV_NAME=carla_gym_me131
SET PYTHON_VERSION=3.8
SET CARLA_DOWNLOAD_URL=https://tiny.carla.org/carla-0-10-0-windows
SET REPO_URL=https://github.com/MPC-Berkeley/barc_gym.git
SET REPO_BRANCH=main
SET REPO_DIR=barc_gym

:: Optional Steps Control (set to 1 to skip)
SET SKIP_CONDA=0
SET SKIP_CARLA_DOWNLOAD=0
SET SKIP_REPO_CLONE=0
SET SKIP_PIP_INSTALL=0
SET SKIP_PACKAGE_INSTALL=0

:: Parse command line arguments
for %%a in (%*) do (
    if "%%a"=="--skip-conda" set SKIP_CONDA=1
    if "%%a"=="--skip-carla" set SKIP_CARLA_DOWNLOAD=1
    if "%%a"=="--skip-repo" set SKIP_REPO_CLONE=1
    if "%%a"=="--skip-pip" set SKIP_PIP_INSTALL=1
    if "%%a"=="--skip-packages" set SKIP_PACKAGE_INSTALL=1
)

:: Step 1: Optional Conda setup
IF "%SKIP_CONDA%"=="0" (
    echo Checking for Conda installation...
    call conda --version 2>NUL
    IF %ERRORLEVEL% NEQ 0 (
        echo Conda is not installed. You have two options:
        echo 1. Install Miniconda from: https://docs.conda.io/en/latest/miniconda.html
        echo 2. Rerun with --skip-conda to proceed without Conda
        pause
        exit /b 1
    )
    echo Conda is installed. Proceeding with environment setup...

    :: Step 2: Create or update Conda environment
    echo Managing Conda environment '%ENV_NAME%'...
    call conda env list | findstr "%ENV_NAME%"
    IF %ERRORLEVEL% EQU 0 (
        echo Environment '%ENV_NAME%' exists. Checking Python version...
        call conda activate %ENV_NAME%
        for /f "tokens=2" %%i in ('python --version 2^>NUL') do set CURRENT_PY_VERSION=%%i
        echo Current Python version in '%ENV_NAME%': !CURRENT_PY_VERSION!
        IF NOT "!CURRENT_PY_VERSION:~0,3!"=="3.8" (
            echo Python version is not 3.8. Recreating environment...
            call conda deactivate
            call conda env remove -n %ENV_NAME%
            call conda create -y -n %ENV_NAME% python=%PYTHON_VERSION%
        )
    ) ELSE (
        echo Creating Conda environment '%ENV_NAME%' with Python %PYTHON_VERSION%...
        call conda create -y -n %ENV_NAME% python=%PYTHON_VERSION%
    )

    :: Step 3: Activate environment
    call conda activate %ENV_NAME%
    call python -m pip install --upgrade pip
) ELSE (
    echo Skipping Conda setup as requested. Make sure Python 3.8 is available.
)

:: Step 4: Optional CARLA download
IF "%SKIP_CARLA_DOWNLOAD%"=="0" (
    IF NOT EXIST "CARLA" (
        echo Downloading CARLA (this may take some time)...
        curl -L -o CARLA_Latest.zip "%CARLA_DOWNLOAD_URL%" || (
            echo Trying alternative download method...
            certutil -urlcache -split -f "%CARLA_DOWNLOAD_URL%" CARLA_Latest.zip || (
                echo Download failed. You can:
                echo 1. Manually download CARLA from: %CARLA_DOWNLOAD_URL%
                echo 2. Place the zip in this directory as CARLA_Latest.zip
                echo 3. Rerun with --skip-carla if already downloaded
                pause
                exit /b 1
            )
        )

        echo Extracting CARLA...
        mkdir CARLA 2>NUL
        powershell -ExecutionPolicy Bypass -Command "Expand-Archive -Path 'CARLA_Latest.zip' -DestinationPath 'CARLA' -Force" || (
            echo Extraction failed. Please extract CARLA_Latest.zip manually.
            pause
            exit /b 1
        )
    ) ELSE (
        echo CARLA directory exists. Skipping download.
    )
) ELSE (
    echo Skipping CARLA download as requested.
)

:: Step 5: Setup CARLA Python API (always required)
echo Setting up CARLA Python API...
SET CARLA_WHEEL_PATH=CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI\carla\dist\carla-0.10.0-cp38-cp38-win_amd64.whl
SET CARLA_API_INSTALLED=0

IF EXIST "%CARLA_WHEEL_PATH%" (
    pip install "%CARLA_WHEEL_PATH%" --force-reinstall --verbose > carla_install_log.txt 2>&1 && (
        python -c "import carla; print('CARLA imported successfully')" 2>NUL && (
            SET CARLA_API_INSTALLED=1
            echo CARLA wheel installed successfully.
        ) || (
            pip uninstall -y carla 2>NUL
            echo Wheel installed but import failed. Using PYTHONPATH method.
        )
    ) || (
        echo Wheel installation failed. Using PYTHONPATH method.
    )
)

IF !CARLA_API_INSTALLED! EQU 0 (
    FOR %%D IN (
        "CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI"
        "CARLA\PythonAPI"
    ) DO (
        IF EXIST %%~D (
            setx PYTHONPATH "%PYTHONPATH%;%CD%\%%~D"
            SET PYTHONPATH=%PYTHONPATH%;%CD%\%%~D
            python -c "import carla; print('CARLA version:', carla.__version__)" 2>NUL && (
                SET CARLA_API_INSTALLED=1
                echo CARLA PythonAPI found at %%~D
                goto :carla_api_success
            )
        )
    )
    IF !CARLA_API_INSTALLED! EQU 0 (
        echo ERROR: CARLA PythonAPI not found. Check your CARLA installation.
        pause
        exit /b 1
    )
)
:carla_api_success

:: Step 6: Optional repository clone
IF "%SKIP_REPO_CLONE%"=="0" (
    IF NOT EXIST "%REPO_DIR%" (
        echo Cloning repository...
        git clone -b %REPO_BRANCH% %REPO_URL% %REPO_DIR% || (
            echo Failed to clone repository.
            pause
            exit /b 1
        )
    ) ELSE (
        echo Updating existing repository...
        cd %REPO_DIR%
        git pull
        cd ..
    )
) ELSE (
    echo Skipping repository clone as requested.
)

:: Step 7: Optional pip requirements installation
IF "%SKIP_PIP_INSTALL%"=="0" (
    echo Installing Python dependencies...
    cd %REPO_DIR%
    IF EXIST "requirements.txt" (
        pip install -r requirements.txt || (
            echo Installing fallback dependencies...
            pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
        )
    ) ELSE (
        pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
    )
) ELSE (
    echo Skipping pip requirements installation as requested.
)

:: Step 8: Optional package installation
IF "%SKIP_PACKAGE_INSTALL%"=="0" (
    echo Installing component packages...
    cd %REPO_DIR%
    FOR %%P IN (
        "gym-carla"
        "mpclab_common"
        "mpclab_controllers" 
        "mpclab_simulation"
    ) DO (
        IF EXIST "%%~P\setup.py" (
            pip install -e %%~P || echo Warning: Failed to install %%~P package.
        )
    )
) ELSE (
    echo Skipping package installation as requested.
)

cd ..

:: Success message
echo.
echo Setup completed successfully!
echo You can now run the simulation with: me131_running_script_windows.bat
echo.
echo Optional parameters for next run:
echo --skip-conda       Skip Conda setup
echo --skip-carla       Skip CARLA download
echo --skip-repo        Skip repository clone
echo --skip-pip         Skip pip requirements installation
echo --skip-packages    Skip component packages installation
echo.
pause
endlocal
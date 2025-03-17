@echo off
setlocal EnableDelayedExpansion

:: Batch script to set up CARLA simulation environment on Windows using Conda

:: Variables
SET ENV_NAME=carla_gym_me131
SET PYTHON_VERSION=3.8
SET CARLA_DOWNLOAD_URL=https://tiny.carla.org/carla-0-10-0-windows
SET REPO_URL=https://github.com/MPC-Berkeley/barc_gym.git
SET REPO_BRANCH=main
SET REPO_DIR=barc_gym

:: Step 1: Check if Conda is installed
echo Checking for Conda installation...
call conda --version 2>NUL
IF %ERRORLEVEL% NEQ 0 (
    echo Conda is not installed. Please install Miniconda or Anaconda and try again.
    echo You can download Miniconda from: https://docs.conda.io/en/latest/miniconda.html
    pause
    exit /b 1
)
echo Conda is installed. Proceeding to the next step...

:: Step 2: Check and enforce Python 3.8 environment
echo Checking if Conda environment '%ENV_NAME%' exists and its Python version...
call conda env list | findstr "%ENV_NAME%"
IF %ERRORLEVEL% EQU 0 (
    echo Environment '%ENV_NAME%' exists. Checking Python version...
    call conda activate %ENV_NAME%
    for /f "tokens=2" %%i in ('python --version 2^>NUL') do set CURRENT_PY_VERSION=%%i
    echo Current Python version in '%ENV_NAME%': !CURRENT_PY_VERSION!
    IF NOT "!CURRENT_PY_VERSION:~0,3!"=="3.8" (
        echo Python version is not 3.8. Removing and recreating environment...
        call conda deactivate
        call conda env remove -n %ENV_NAME%
        IF %ERRORLEVEL% NEQ 0 (
            echo Failed to remove existing environment.
            pause
            exit /b 1
        )
        echo Creating Conda environment '%ENV_NAME%' with Python %PYTHON_VERSION%...
        call conda create -y -n %ENV_NAME% python=%PYTHON_VERSION%
        IF %ERRORLEVEL% NEQ 0 (
            echo Failed to create Conda environment.
            pause
            exit /b 1
        )
        echo Conda environment recreated with Python %PYTHON_VERSION%.
    ) ELSE (
        echo Python version is already 3.8. Skipping recreation...
    )
) ELSE (
    echo Creating Conda environment '%ENV_NAME%' with Python %PYTHON_VERSION%...
    call conda create -y -n %ENV_NAME% python=%PYTHON_VERSION%
    IF %ERRORLEVEL% NEQ 0 (
        echo Failed to create Conda environment.
        pause
        exit /b 1
    )
    echo Conda environment created. Proceeding to the next step...
)

:: Step 3: Activate and verify environment
echo Activating Conda environment...
call conda activate %ENV_NAME%
IF %ERRORLEVEL% NEQ 0 (
    echo Failed to activate Conda environment.
    pause
    exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>NUL') do set CURRENT_PY_VERSION=%%i
echo Verifying Python version: !CURRENT_PY_VERSION!
IF NOT "!CURRENT_PY_VERSION:~0,3!"=="3.8" (
    echo ERROR: Python version is not 3.8 after activation. Setup cannot proceed.
    pause
    exit /b 1
)
call python -m pip install --upgrade pip
IF %ERRORLEVEL% NEQ 0 (
    echo Failed to upgrade pip.
    pause
    exit /b 1
)
echo Pip upgraded. Proceeding to the next step...

:: Step 4 & 5: Check if CARLA directory already exists
IF EXIST "CARLA" (
    echo CARLA directory already exists. Skipping download and extraction steps...
) ELSE (
    echo Downloading CARLA...
    echo This may take some time depending on your internet connection...
    curl -L -o CARLA_Latest.zip "%CARLA_DOWNLOAD_URL%"
    IF %ERRORLEVEL% NEQ 0 (
        echo Failed to download CARLA. Trying alternative method...
        certutil -urlcache -split -f "%CARLA_DOWNLOAD_URL%" CARLA_Latest.zip
        IF %ERRORLEVEL% NEQ 0 (
            echo All download methods failed.
            echo Please download CARLA manually from: %CARLA_DOWNLOAD_URL%
            echo Then place the zip file in this directory and rename it to CARLA_Latest.zip
            pause
            exit /b 1
        )
    )
    echo CARLA downloaded. Proceeding to the next step...

    echo Extracting CARLA...
    mkdir CARLA 2>NUL
    echo This may take some time...
    call powershell -ExecutionPolicy Bypass -Command "Expand-Archive -Path 'CARLA_Latest.zip' -DestinationPath 'CARLA' -Force"
    IF %ERRORLEVEL% NEQ 0 (
        echo Failed to extract using PowerShell.
        echo Please extract CARLA_Latest.zip manually to a folder named CARLA.
        pause
        exit /b 1
    )
    echo CARLA extracted. Proceeding to the next step...
)

:: Step 6: Install CARLA Python API with thorough validation
echo Installing CARLA Python API...
SET CARLA_WHEEL_PATH=CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI\carla\dist\carla-0.10.0-cp38-cp38-win_amd64.whl
SET CARLA_API_INSTALLED=0

IF EXIST "%CARLA_WHEEL_PATH%" (
    echo Found CARLA Python wheel for Python 3.8: %CARLA_WHEEL_PATH%
    echo Installing wheel with verbose output...
    pip install "%CARLA_WHEEL_PATH%" --force-reinstall --verbose > carla_install_log.txt 2>&1
    IF %ERRORLEVEL% EQU 0 (
        echo Wheel installation reported success. Validating...
        python -c "import carla; print('CARLA imported successfully')" 2>NUL
        IF %ERRORLEVEL% EQU 0 (
            SET CARLA_API_INSTALLED=1
            echo CARLA wheel validated successfully.
        ) ELSE (
            echo Wheel installed but import failed. Check carla_install_log.txt for details.
            echo Uninstalling wheel and falling back to PYTHONPATH...
            pip uninstall -y carla 2>NUL
        )
    ) ELSE (
        echo Wheel installation failed. Check carla_install_log.txt for details.
        echo Proceeding with PYTHONPATH fallback...
    )
) ELSE (
    echo CARLA wheel not found at expected path.
)

IF !CARLA_API_INSTALLED! EQU 0 (
    echo Setting up CARLA Python API via PYTHONPATH...
    IF EXIST "CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI" (
        setx PYTHONPATH "%PYTHONPATH%;%CD%\CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI"
        SET PYTHONPATH=%PYTHONPATH%;%CD%\CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI
        echo Added CARLA PythonAPI to PYTHONPATH.
    ) ELSE IF EXIST "CARLA\PythonAPI" (
        setx PYTHONPATH "%PYTHONPATH%;%CD%\CARLA\PythonAPI"
        SET PYTHONPATH=%PYTHONPATH%;%CD%\CARLA\PythonAPI
        echo Added CARLA PythonAPI to PYTHONPATH.
    ) ELSE (
        echo ERROR: CARLA PythonAPI directory not found. Setup incomplete.
        pause
        exit /b 1
    )
    :: Validate PYTHONPATH fallback
    python -c "import carla; print('CARLA version:', carla.__version__)" 2>NUL
    IF %ERRORLEVEL% NEQ 0 (
        echo ERROR: PYTHONPATH fallback failed. CARLA module not found.
        echo Current PYTHONPATH: %PYTHONPATH%
        pause
        exit /b 1
    ) ELSE (
        echo CARLA Python API validated via PYTHONPATH.
        SET CARLA_API_INSTALLED=1
    )
)

echo CARLA Python API setup completed. Proceeding to the next step...

:: Step 7: Clone repository (no submodules needed)
echo Checking if repository already exists...
IF EXIST "%REPO_DIR%" (
    echo Repository directory already exists. Updating...
    cd %REPO_DIR%
    git pull
    cd ..
) ELSE (
    echo Cloning repository...
    git clone -b %REPO_BRANCH% %REPO_URL% %REPO_DIR%
    IF %ERRORLEVEL% NEQ 0 (
        echo Failed to clone repository.
        pause
        exit /b 1
    )
    echo Repository cloned. Proceeding to the next step...
)

:: Step 8: Install requirements from gym-carla if available
echo Installing requirements from barc_gym...
cd %REPO_DIR%
IF EXIST "requirements.txt" (
    echo Found requirements.txt in barc_gym. Installing...
    pip install -r requirements.txt
    IF %ERRORLEVEL% NEQ 0 (
        echo Warning: Some requirements may have failed to install.
        echo Installing common dependencies as fallback...
        pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
    )
) ELSE (
    echo No requirements.txt found in barc_gym. Installing common dependencies...
    pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
)

:: Step 9: Install all component packages
echo Installing gym-carla package...
IF EXIST "gym-carla\setup.py" (
    echo Found setup.py in gym-carla. Installing...
    pip install -e gym-carla
    IF %ERRORLEVEL% NEQ 0 (
        echo Warning: Failed to install gym-carla package.
    )
) ELSE (
    echo Warning: setup.py not found in gym-carla. Skipping installation.
)

echo Installing mpclab_common package...
IF EXIST "mpclab_common\setup.py" (
    echo Found setup.py in mpclab_common. Installing...
    pip install -e mpclab_common
    IF %ERRORLEVEL% NEQ 0 (
        echo Warning: Failed to install mpclab_common package.
    )
) ELSE (
    echo Warning: setup.py not found in mpclab_common. Skipping installation.
)

echo Installing mpclab_controllers package...
IF EXIST "mpclab_controllers\setup.py" (
    echo Found setup.py in mpclab_controllers. Installing...
    pip install -e mpclab_controllers
    IF %ERRORLEVEL% NEQ 0 (
        echo Warning: Failed to install mpclab_controllers package.
    )
) ELSE (
    echo Warning: setup.py not found in mpclab_controllers. Skipping installation.
)

echo Installing mpclab_simulation package...
IF EXIST "mpclab_simulation\setup.py" (
    echo Found setup.py in mpclab_simulation. Installing...
    pip install -e mpclab_simulation
    IF %ERRORLEVEL% NEQ 0 (
        echo Warning: Failed to install mpclab_simulation package.
    )
) ELSE (
    echo Warning: setup.py not found in mpclab_simulation. Skipping installation.
)

cd ..

:: Success message
echo Setup completed successfully!
echo Conda environment: %ENV_NAME%
echo CARLA downloaded to: CARLA
echo Repository cloned to: %REPO_DIR%
echo.
echo NOTE: If you encounter import errors with CARLA in your Python code,
echo you may need to manually set your PYTHONPATH to include one of these paths:
echo 1. %CD%\CARLA\PythonAPI
echo 2. %CD%\CARLA\Carla-0.10.0-Win64-Shipping\PythonAPI (if available)
echo.
pause

endlocal
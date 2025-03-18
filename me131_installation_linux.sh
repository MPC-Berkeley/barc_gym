#!/bin/bash

# Shell script to set up CARLA simulation environment on Linux using Conda

# Variables
ENV_NAME="carla_gym_me131"
PYTHON_VERSION="3.8"
CARLA_DOWNLOAD_URL="https://tiny.carla.org/carla-0-10-0-linux-tar"
REPO_URL="https://github.com/MPC-Berkeley/barc_gym.git"
REPO_BRANCH="main"
REPO_DIR="barc_gym"

# Step 1: Check if Conda is installed
echo "Checking for Conda installation..."
if ! command -v conda &> /dev/null; then
    echo "Conda is not installed. Please install Miniconda or Anaconda and try again."
    echo "You can download Miniconda from: https://docs.conda.io/en/latest/miniconda.html"
    exit 1
fi
echo "Conda is installed. Proceeding to the next step..."

# Step 2: Check and enforce Python 3.8 environment
echo "Checking if Conda environment '$ENV_NAME' exists and its Python version..."
if conda env list | grep -q "$ENV_NAME"; then
    echo "Environment '$ENV_NAME' exists. Checking Python version..."
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "$ENV_NAME"
    CURRENT_PY_VERSION=$(python --version 2>&1 | cut -d' ' -f2)
    echo "Current Python version in '$ENV_NAME': $CURRENT_PY_VERSION"
    if [[ ! "$CURRENT_PY_VERSION" == 3.8* ]]; then
        echo "Python version is not 3.8. Removing and recreating environment..."
        conda deactivate
        conda env remove -n "$ENV_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to remove existing environment."
            exit 1
        fi
        echo "Creating Conda environment '$ENV_NAME' with Python $PYTHON_VERSION..."
        conda create -y -n "$ENV_NAME" python="$PYTHON_VERSION"
        if [ $? -ne 0 ]; then
            echo "Failed to create Conda environment."
            exit 1
        fi
        echo "Conda environment recreated with Python $PYTHON_VERSION."
    else
        echo "Python version is already 3.8. Skipping recreation..."
    fi
else
    echo "Creating Conda environment '$ENV_NAME' with Python $PYTHON_VERSION..."
    conda create -y -n "$ENV_NAME" python="$PYTHON_VERSION"
    if [ $? -ne 0 ]; then
        echo "Failed to create Conda environment."
        exit 1
    fi
    echo "Conda environment created. Proceeding to the next step..."
fi

# Step 3: Activate and verify environment
echo "Activating Conda environment..."
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"
if [ $? -ne 0 ]; then
    echo "Failed to activate Conda environment."
    exit 1
fi
CURRENT_PY_VERSION=$(python --version 2>&1 | cut -d' ' -f2)
echo "Verifying Python version: $CURRENT_PY_VERSION"
if [[ ! "$CURRENT_PY_VERSION" == 3.8* ]]; then
    echo "ERROR: Python version is not 3.8 after activation. Setup cannot proceed."
    exit 1
fi
python -m pip install --upgrade pip
if [ $? -ne 0 ]; then
    echo "Failed to upgrade pip."
    exit 1
fi
echo "Pip upgraded. Proceeding to the next step..."

# Step 4 & 5: Check if CARLA directory already exists
if [ -d "CARLA" ]; then
    echo "CARLA directory already exists. Skipping download and extraction steps..."
else
    echo "Downloading CARLA..."
    echo "This may take some time depending on your internet connection..."
    mkdir -p CARLA
    if ! wget -O CARLA_Latest.tar.gz "$CARLA_DOWNLOAD_URL"; then
        echo "Failed to download CARLA using wget. Trying curl..."
        if ! curl -L -o CARLA_Latest.tar.gz "$CARLA_DOWNLOAD_URL"; then
            echo "All download methods failed."
            echo "Please download CARLA manually from: $CARLA_DOWNLOAD_URL"
            echo "Then place the tar.gz file in this directory and rename it to CARLA_Latest.tar.gz"
            exit 1
        fi
    fi
    echo "CARLA downloaded. Proceeding to the next step..."

    echo "Extracting CARLA..."
    echo "This may take some time..."
    tar -xf CARLA_Latest.tar.gz -C CARLA
    if [ $? -ne 0 ]; then
        echo "Failed to extract CARLA."
        echo "Please extract CARLA_Latest.tar.gz manually to a folder named CARLA."
        exit 1
    fi
    echo "CARLA extracted. Proceeding to the next step..."
fi

# Step 6: Install CARLA Python API with thorough validation
echo "Installing CARLA Python API..."
CARLA_WHEEL_PATH="CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI/carla/dist/carla-0.10.0-cp38-cp38-linux_x86_64.whl"
CARLA_API_INSTALLED=0

if [ -f "$CARLA_WHEEL_PATH" ]; then
    echo "Found CARLA Python wheel for Python 3.8: $CARLA_WHEEL_PATH"
    echo "Installing wheel with verbose output..."
    pip install "$CARLA_WHEEL_PATH" --force-reinstall --verbose > carla_install_log.txt 2>&1
    if [ $? -eq 0 ]; then
        echo "Wheel installation reported success. Validating..."
        if python -c "import carla; print('CARLA imported successfully')" 2>/dev/null; then
            CARLA_API_INSTALLED=1
            echo "CARLA wheel validated successfully."
        else
            echo "Wheel installed but import failed. Check carla_install_log.txt for details."
            echo "Uninstalling wheel and falling back to PYTHONPATH..."
            pip uninstall -y carla 2>/dev/null
        fi
    else
        echo "Wheel installation failed. Check carla_install_log.txt for details."
        echo "Proceeding with PYTHONPATH fallback..."
    fi
else
    echo "CARLA wheel not found at expected path."
fi

if [ $CARLA_API_INSTALLED -eq 0 ]; then
    echo "Setting up CARLA Python API via PYTHONPATH..."
    CURRENT_DIR=$(pwd)
    
    if [ -d "CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI" ]; then
        export PYTHONPATH="$PYTHONPATH:$CURRENT_DIR/CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI"
        echo "export PYTHONPATH=\"\$PYTHONPATH:$CURRENT_DIR/CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI\"" >> ~/.bashrc
        echo "Added CARLA PythonAPI to PYTHONPATH."
    elif [ -d "CARLA/PythonAPI" ]; then
        export PYTHONPATH="$PYTHONPATH:$CURRENT_DIR/CARLA/PythonAPI"
        echo "export PYTHONPATH=\"\$PYTHONPATH:$CURRENT_DIR/CARLA/PythonAPI\"" >> ~/.bashrc
        echo "Added CARLA PythonAPI to PYTHONPATH."
    else
        echo "ERROR: CARLA PythonAPI directory not found. Setup incomplete."
        exit 1
    fi
    
    # Validate PYTHONPATH fallback
    if ! python -c "import carla; print('CARLA version:', carla.__version__)" 2>/dev/null; then
        echo "ERROR: PYTHONPATH fallback failed. CARLA module not found."
        echo "Current PYTHONPATH: $PYTHONPATH"
        exit 1
    else
        echo "CARLA Python API validated via PYTHONPATH."
        CARLA_API_INSTALLED=1
    fi
fi

echo "CARLA Python API setup completed. Proceeding to the next step..."

# Step 7: Clone repository (no submodules needed)
echo "Checking if repository already exists..."
if [ -d "$REPO_DIR" ]; then
    echo "Repository directory already exists. Updating..."
    cd "$REPO_DIR"
    git pull
    cd ..
else
    echo "Cloning repository..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    if [ $? -ne 0 ]; then
        echo "Failed to clone repository."
        exit 1
    fi
    echo "Repository cloned. Proceeding to the next step..."
fi

# Step 8: Install requirements from gym-carla if available
echo "Installing requirements from barc_gym..."
cd "$REPO_DIR"
if [ -f "requirements.txt" ]; then
    echo "Found requirements.txt in barc_gym. Installing..."
    pip install -r requirements.txt
    if [ $? -ne 0 ]; then
        echo "Warning: Some requirements may have failed to install."
        echo "Installing common dependencies as fallback..."
        pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
    fi
else
    echo "No requirements.txt found in barc_gym. Installing common dependencies..."
    pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
fi

# Step 9: Install all component packages
echo "Installing gym-carla package..."
if [ -f "gym-carla/setup.py" ]; then
    echo "Found setup.py in gym-carla. Installing..."
    pip install -e gym-carla
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to install gym-carla package."
    fi
else
    echo "Warning: setup.py not found in gym-carla. Skipping installation."
fi

echo "Installing mpclab_common package..."
if [ -f "mpclab_common/setup.py" ]; then
    echo "Found setup.py in mpclab_common. Installing..."
    pip install -e mpclab_common
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to install mpclab_common package."
    fi
else
    echo "Warning: setup.py not found in mpclab_common. Skipping installation."
fi

echo "Installing mpclab_controllers package..."
if [ -f "mpclab_controllers/setup.py" ]; then
    echo "Found setup.py in mpclab_controllers. Installing..."
    pip install -e mpclab_controllers
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to install mpclab_controllers package."
    fi
else
    echo "Warning: setup.py not found in mpclab_controllers. Skipping installation."
fi

echo "Installing mpclab_simulation package..."
if [ -f "mpclab_simulation/setup.py" ]; then
    echo "Found setup.py in mpclab_simulation. Installing..."
    pip install -e mpclab_simulation
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to install mpclab_simulation package."
    fi
else
    echo "Warning: setup.py not found in mpclab_simulation. Skipping installation."
fi

cd ..

# Success message
echo "Setup completed successfully!"
echo "Conda environment: $ENV_NAME"
echo "CARLA downloaded to: CARLA"
echo "Repository cloned to: $REPO_DIR"
echo ""
echo "NOTE: If you encounter import errors with CARLA in your Python code,"
echo "you may need to manually set your PYTHONPATH to include one of these paths:"
echo "1. $(pwd)/CARLA/PythonAPI"
echo "2. $(pwd)/CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI (if available)"
echo ""
read -p "Press Enter to continue to running CARLA Simulator..."


#!/bin/bash

# Configurable variables
ENV_NAME="carla_gym_me131"
PYTHON_VERSION="3.8"
CARLA_DOWNLOAD_URL="https://tiny.carla.org/carla-0-10-0-linux-tar"
REPO_URL="https://github.com/MPC-Berkeley/barc_gym.git"
REPO_BRANCH="main"
REPO_DIR="barc_gym"

# Optional steps control (set via command line arguments)
SKIP_CONDA=0
SKIP_CARLA=0
SKIP_REPO=0
SKIP_REQUIREMENTS=0
SKIP_PACKAGES=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-conda)
            SKIP_CONDA=1
            shift
            ;;
        --skip-carla)
            SKIP_CARLA=1
            shift
            ;;
        --skip-repo)
            SKIP_REPO=1
            shift
            ;;
        --skip-requirements)
            SKIP_REQUIREMENTS=1
            shift
            ;;
        --skip-packages)
            SKIP_PACKAGES=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Available options:"
            echo "--skip-conda        Skip Conda installation and environment setup"
            echo "--skip-carla        Skip CARLA download and extraction"
            echo "--skip-repo         Skip repository cloning"
            echo "--skip-requirements Skip Python requirements installation"
            echo "--skip-packages     Skip component packages installation"
            exit 1
            ;;
    esac
done

# Step 1: Optional Conda setup
if [ "$SKIP_CONDA" -eq 0 ]; then
    echo "Checking for Conda installation..."
    if ! command -v conda &> /dev/null; then
        echo "Conda is not installed. You can:"
        echo "1. Install Miniconda from: https://docs.conda.io/en/latest/miniconda.html"
        echo "2. Rerun with --skip-conda to proceed without Conda"
        exit 1
    fi
    echo "Conda is installed. Proceeding with environment setup..."

    # Step 2: Create or update Conda environment
    echo "Checking if Conda environment '$ENV_NAME' exists..."
    if conda env list | grep -q "$ENV_NAME"; then
        echo "Environment '$ENV_NAME' exists. Checking Python version..."
        source "$(conda info --base)/etc/profile.d/conda.sh"
        conda activate "$ENV_NAME"
        CURRENT_PY_VERSION=$(python --version 2>&1 | cut -d' ' -f2)
        echo "Current Python version in '$ENV_NAME': $CURRENT_PY_VERSION"
        if [[ ! "$CURRENT_PY_VERSION" == 3.8* ]]; then
            echo "Python version is not 3.8. Recreating environment..."
            conda deactivate
            conda env remove -n "$ENV_NAME"
            conda create -y -n "$ENV_NAME" python="$PYTHON_VERSION"
        fi
    else
        echo "Creating Conda environment '$ENV_NAME' with Python $PYTHON_VERSION..."
        conda create -y -n "$ENV_NAME" python="$PYTHON_VERSION"
    fi

    # Step 3: Activate environment
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "$ENV_NAME"
    python -m pip install --upgrade pip
else
    echo "Skipping Conda setup as requested."
    echo "Please ensure Python $PYTHON_VERSION is available in your PATH."
fi

# Step 4: Optional CARLA download
if [ "$SKIP_CARLA" -eq 0 ]; then
    if [ ! -d "CARLA" ]; then
        echo "Downloading CARLA (this may take some time)..."
        if ! wget -O CARLA_Latest.tar.gz "$CARLA_DOWNLOAD_URL" && \
           ! curl -L -o CARLA_Latest.tar.gz "$CARLA_DOWNLOAD_URL"; then
            echo "Download failed. You can:"
            echo "1. Manually download from: $CARLA_DOWNLOAD_URL"
            echo "2. Place the file as CARLA_Latest.tar.gz in this directory"
            echo "3. Rerun with --skip-carla"
            exit 1
        fi

        echo "Extracting CARLA..."
        mkdir -p CARLA
        if ! tar -xf CARLA_Latest.tar.gz -C CARLA; then
            echo "Extraction failed. Please extract manually."
            exit 1
        fi
    else
        echo "CARLA directory exists. Skipping download."
    fi
else
    echo "Skipping CARLA download as requested."
fi

# Step 5: Setup CARLA Python API (always required)
echo "Setting up CARLA Python API..."
CARLA_WHEEL_PATH="CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI/carla/dist/carla-0.10.0-cp38-cp38-linux_x86_64.whl"
CARLA_API_INSTALLED=0

if [ -f "$CARLA_WHEEL_PATH" ]; then
    echo "Installing CARLA wheel..."
    pip install "$CARLA_WHEEL_PATH" --force-reinstall --verbose > carla_install_log.txt 2>&1 && \
    python -c "import carla; print('CARLA imported successfully')" 2>/dev/null && \
    CARLA_API_INSTALLED=1 || \
    pip uninstall -y carla 2>/dev/null
fi

if [ "$CARLA_API_INSTALLED" -eq 0 ]; then
    echo "Using PYTHONPATH method..."
    CURRENT_DIR=$(pwd)
    for CARLA_API_PATH in \
        "$CURRENT_DIR/CARLA/Carla-0.10.0-Linux-Shipping/PythonAPI" \
        "$CURRENT_DIR/CARLA/PythonAPI"
    do
        if [ -d "$CARLA_API_PATH" ]; then
            export PYTHONPATH="$PYTHONPATH:$CARLA_API_PATH"
            echo "export PYTHONPATH=\"\$PYTHONPATH:$CARLA_API_PATH\"" >> ~/.bashrc
            if python -c "import carla; print('CARLA version:', carla.__version__)" 2>/dev/null; then
                CARLA_API_INSTALLED=1
                echo "CARLA API found at: $CARLA_API_PATH"
                break
            fi
        fi
    done

    if [ "$CARLA_API_INSTALLED" -eq 0 ]; then
        echo "ERROR: CARLA PythonAPI not found. Check your installation."
        exit 1
    fi
fi

# Step 6: Optional repository clone
if [ "$SKIP_REPO" -eq 0 ]; then
    if [ -d "$REPO_DIR" ]; then
        echo "Updating existing repository..."
        cd "$REPO_DIR" && git pull && cd ..
    else
        echo "Cloning repository..."
        git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR" || exit 1
    fi
else
    echo "Skipping repository clone as requested."
fi

# Step 7: Optional requirements installation
if [ "$SKIP_REQUIREMENTS" -eq 0 ]; then
    echo "Installing Python dependencies..."
    cd "$REPO_DIR" || exit 1
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || \
        pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
    else
        pip install pygame>=2.1.0 gymnasium==0.28.1 scikit-image==0.16.2 loguru
    fi
else
    echo "Skipping requirements installation as requested."
fi

# Step 8: Optional package installation
if [ "$SKIP_PACKAGES" -eq 0 ]; then
    echo "Installing component packages..."
    cd "$REPO_DIR" || exit 1
    for package in gym-carla mpclab_common mpclab_controllers mpclab_simulation; do
        if [ -f "$package/setup.py" ]; then
            pip install -e "$package" || echo "Warning: Failed to install $package"
        fi
    done
else
    echo "Skipping package installation as requested."
fi

cd ..

# Success message
echo -e "\nSetup completed successfully!"
echo "You can now run the simulation with: ./me131_running_script_linux.sh"
echo -e "\nOptional parameters for next run:"
echo "--skip-conda         Skip Conda installation and environment setup"
echo "--skip-carla         Skip CARLA download and extraction"
echo "--skip-repo          Skip repository cloning"
echo "--skip-requirements  Skip Python requirements installation"
echo "--skip-packages      Skip component packages installation"
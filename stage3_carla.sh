#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=============================="
echo "Stage 3: GPU + CARLA Runtime"
echo "=============================="

echo "[0] Checking NVIDIA driver..."
if command -v nvidia-smi > /dev/null 2>&1; then
    nvidia-smi
else
    echo "[ERROR] nvidia-smi not found"
    exit 1
fi

echo "[1] Installing graphics runtime libraries..."
run_root apt-get update
run_root apt-get install -y \
    libgl1 \
    libegl1 \
    libglib2.0-0 \
    libxrandr2 \
    libxinerama1 \
    libxcursor1 \
    libxi6 \
    libxrender1 \
    libsm6 \
    libfontconfig1 \
    libfreetype6 \
    vulkan-tools \
    libvulkan1 \
    mesa-vulkan-drivers

echo "[2] Vulkan check..."
if command -v vulkaninfo > /dev/null 2>&1; then
    vulkaninfo | head -20 || true
else
    echo "[WARN] vulkaninfo not available"
fi

echo "[3] Checking CARLA installation..."
if [ ! -d "$CARLA_ROOT/PythonAPI" ]; then
    if [ ! -f "$CARLA_TAR_FILE" ]; then
        echo "[ERROR] CARLA archive not found: $CARLA_TAR_FILE"
        echo "Download the official CARLA 0.9.16 archive first:"
        echo "  bash ${SCRIPT_DIR}/download_carla.sh"
        echo "Or set CARLA_TAR_FILE / place an existing archive in ${BLOCKDATA_DIR}."
        exit 1
    fi

    mkdir -p "$CARLA_ROOT"
    echo "[INFO] Extracting CARLA to $CARLA_ROOT. This may take a while..."
    tar -xzf "$CARLA_TAR_FILE" -C "$CARLA_ROOT"
else
    echo "[OK] Found existing CARLA directory: $CARLA_ROOT"
fi

echo "[4] Installing CARLA Python API..."
if [ ! -f "$CONDA_SH" ]; then
    echo "[ERROR] Conda profile not found: $CONDA_SH"
    exit 1
fi

unset PYTHONPATH
export PYTHONNOUSERSITE=1
source "$CONDA_SH"
conda activate "$CONDA_ENV_NAME"

if [ ! -f "$CARLA_WHEEL" ]; then
    echo "[ERROR] CARLA wheel not found: $CARLA_WHEEL"
    exit 1
fi

pip install --force-reinstall "$CARLA_WHEEL"

echo "[5] CARLA Python extension test..."
python - <<'EOF'
try:
    import carla
    print("[OK] carla module imported successfully.")
except Exception as exc:
    print("[FAIL] carla import failed:", exc)
    raise SystemExit(1)
EOF

echo "=============================="
echo "Stage 3 completed."
echo "=============================="

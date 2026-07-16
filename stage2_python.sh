#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "========== Stage 2: Python (Conda) =========="

run_root apt-get install -y \
    build-essential \
    git \
    git-lfs \
    curl \
    wget \
    unzip \
    zip \
    vim \
    tmux \
    htop \
    tree \
    pkg-config

if [ ! -f "$CONDA_SH" ]; then
    echo "[ERROR] Conda profile not found: $CONDA_SH"
    echo "Run stage0_miniconda.sh first."
    exit 1
fi

unset PYTHONPATH
export PYTHONNOUSERSITE=1
source "$CONDA_SH"

if ! conda env list | awk '{print $1}' | grep -qx "$CONDA_ENV_NAME"; then
    conda create -y -n "$CONDA_ENV_NAME" python="$PYTHON_VERSION"
fi

BASHRC="$HOME/.bashrc"
START_MARKER="# === env_build conda env START ==="
END_MARKER="# === env_build conda env END ==="
TMP_BASHRC="$(mktemp)"
touch "$BASHRC"

sed "/${START_MARKER}/,/${END_MARKER}/d" "$BASHRC" > "$TMP_BASHRC"
cat > "$BASHRC" << EOF
${START_MARKER}
unset PYTHONPATH
export PYTHONNOUSERSITE=1
source ${CONDA_SH}
conda activate ${CONDA_ENV_NAME}
${END_MARKER}
EOF
cat "$TMP_BASHRC" >> "$BASHRC"
rm "$TMP_BASHRC"

conda activate "$CONDA_ENV_NAME"
python -m pip install --upgrade pip
pip install -r "${SCRIPT_DIR}/requirements.txt" \
    -i "$PIP_INDEX_URL" \
    --trusted-host "$PIP_TRUSTED_HOST"

python - <<'EOF'
import cv2
import mcap
import numpy
import pandas
import pyarrow

print("Python environment OK.")
EOF

echo
echo "======================================="
echo "Stage 2 completed."
echo "Activate environment with:"
echo "    conda activate ${CONDA_ENV_NAME}"
echo "======================================="

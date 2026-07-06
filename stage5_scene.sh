#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "Stage 5: ScenarioRunner"
echo "=========================================="

if [ ! -f "$CONDA_SH" ]; then
    echo "[ERROR] Conda profile not found: $CONDA_SH"
    exit 1
fi
source "$CONDA_SH"
conda activate "$CONDA_ENV_NAME"

mkdir -p "$BLOCKDATA_DIR"
cd "$BLOCKDATA_DIR"

echo "[1/3] Installing ScenarioRunner ${SCENARIO_RUNNER_TAG}..."
rm -rf "$SCENARIO_RUNNER_ROOT" "scenario_runner-${CARLA_VERSION}"

ARCHIVE_NAME="${SCENARIO_RUNNER_TAG}.tar.gz"
wget -O "$ARCHIVE_NAME" "https://github.com/carla-simulator/scenario_runner/archive/refs/tags/${SCENARIO_RUNNER_TAG}.tar.gz"
tar -xzf "$ARCHIVE_NAME"
mv "scenario_runner-${CARLA_VERSION}" "$SCENARIO_RUNNER_ROOT"
rm "$ARCHIVE_NAME"

cd "$SCENARIO_RUNNER_ROOT"

echo "[2/3] Installing ScenarioRunner Python requirements..."
sed -i 's/numpy==1.24.4/numpy==1.26.4/' requirements.txt
pip install -r requirements.txt \
    -i "$PIP_INDEX_URL" \
    --trusted-host "$PIP_TRUSTED_HOST"
pip install scipy==1.13.1 \
    -i "$PIP_INDEX_URL" \
    --trusted-host "$PIP_TRUSTED_HOST"

echo "[3/3] Writing shell environment to ~/.bashrc..."
BASHRC="$HOME/.bashrc"
START_MARKER="# === env_build ScenarioRunner START ==="
END_MARKER="# === env_build ScenarioRunner END ==="
TMP_BASHRC="$(mktemp)"

sed "/${START_MARKER}/,/${END_MARKER}/d" "$BASHRC" > "$TMP_BASHRC"
cat > "$BASHRC" << EOF
${START_MARKER}
export CARLA_ROOT=${CARLA_ROOT}
export SCENARIO_RUNNER_ROOT=${SCENARIO_RUNNER_ROOT}
export PYTHONPATH=\${CARLA_ROOT}/PythonAPI/carla:\${SCENARIO_RUNNER_ROOT}:\${PYTHONPATH}
${END_MARKER}
EOF
cat "$TMP_BASHRC" >> "$BASHRC"
rm "$TMP_BASHRC"

echo "Stage 5 completed."

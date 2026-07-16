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
unset PYTHONPATH
export PYTHONNOUSERSITE=1
source "$CONDA_SH"
conda activate "$CONDA_ENV_NAME"

mkdir -p "$BLOCKDATA_DIR"
cd "$BLOCKDATA_DIR"

echo "[1/3] Installing ScenarioRunner ${SCENARIO_RUNNER_TAG}..."
ARCHIVE_NAME="${SCENARIO_RUNNER_TAG}.tar.gz"
ARCHIVE_PATH="$BLOCKDATA_DIR/$ARCHIVE_NAME"
ARCHIVE_PART="${ARCHIVE_PATH}.part"
STAGING_DIR="$BLOCKDATA_DIR/.scenario_runner-${CARLA_VERSION}.staging"
BACKUP_DIR="$BLOCKDATA_DIR/.scenario_runner-${CARLA_VERSION}.backup"

if [ ! -s "$ARCHIVE_PATH" ] || ! tar -tzf "$ARCHIVE_PATH" > /dev/null 2>&1; then
    echo "[INFO] Downloading resumable archive: $ARCHIVE_PATH"
    wget -c -O "$ARCHIVE_PART" \
        "https://github.com/carla-simulator/scenario_runner/archive/refs/tags/${SCENARIO_RUNNER_TAG}.tar.gz"
    tar -tzf "$ARCHIVE_PART" > /dev/null
    mv -f "$ARCHIVE_PART" "$ARCHIVE_PATH"
else
    echo "[OK] Reusing validated archive: $ARCHIVE_PATH"
fi

ARCHIVE_ROOT="$(tar -tzf "$ARCHIVE_PATH" | sed -n '1{s|/.*||;p;q;}')"
if [ -z "$ARCHIVE_ROOT" ]; then
    echo "[ERROR] Could not determine ScenarioRunner archive root: $ARCHIVE_PATH"
    exit 1
fi

rm -rf "$STAGING_DIR" "$BACKUP_DIR"
mkdir -p "$STAGING_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR"
NEW_ROOT="$STAGING_DIR/$ARCHIVE_ROOT"
if [ ! -f "$NEW_ROOT/scenario_runner.py" ]; then
    echo "[ERROR] Invalid ScenarioRunner archive; scenario_runner.py is absent."
    exit 1
fi

# Replace the active tree only after download, archive validation, and
# extraction have all succeeded. Preserve the previous install until the
# replacement is in place.
if [ -e "$SCENARIO_RUNNER_ROOT" ]; then
    mv "$SCENARIO_RUNNER_ROOT" "$BACKUP_DIR"
fi
if ! mv "$NEW_ROOT" "$SCENARIO_RUNNER_ROOT"; then
    if [ -e "$BACKUP_DIR" ]; then
        mv "$BACKUP_DIR" "$SCENARIO_RUNNER_ROOT"
    fi
    echo "[ERROR] Failed to activate the new ScenarioRunner tree; previous install restored."
    exit 1
fi
rm -rf "$STAGING_DIR" "$BACKUP_DIR"

cd "$SCENARIO_RUNNER_ROOT"

echo "[2/3] Installing ScenarioRunner Python requirements..."
if grep -q '^numpy==1\.24\.4$' requirements.txt; then
    sed -i 's/^numpy==1\.24\.4$/numpy==1.26.4/' requirements.txt
fi
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
cat "$TMP_BASHRC" > "$BASHRC"
cat >> "$BASHRC" << EOF
${START_MARKER}
export CARLA_ROOT=${CARLA_ROOT}
export SCENARIO_RUNNER_ROOT=${SCENARIO_RUNNER_ROOT}
export PYTHONPATH=\${CARLA_ROOT}/PythonAPI/carla:\${SCENARIO_RUNNER_ROOT}:\${PYTHONPATH:-}
${END_MARKER}
EOF
rm "$TMP_BASHRC"

echo "Stage 5 completed."

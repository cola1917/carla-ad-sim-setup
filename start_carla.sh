#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

VNC_DISPLAY=":${VNC_DISPLAY_NUM}"

echo "=============================="
echo "Preparing CARLA environment"
echo "=============================="

if [ ! -d "$CARLA_ROOT" ]; then
    echo "[ERROR] CARLA_ROOT does not exist: $CARLA_ROOT"
    echo "Run stage3_carla.sh first or set CARLA_ROOT in env_config.sh."
    exit 1
fi

if ! id "$CARLA_RUN_USER" > /dev/null 2>&1; then
    echo "[INFO] User '${CARLA_RUN_USER}' not found. Creating user..."
    useradd -m -s /bin/bash "$CARLA_RUN_USER"
    usermod -aG video,render "$CARLA_RUN_USER"
else
    echo "[INFO] User '${CARLA_RUN_USER}' already exists."
fi

echo "[INFO] Configuring directory permissions..."
if [ "$(id -u)" -eq 0 ]; then
    chmod 755 "$HOME" || true
fi
chown -R "${CARLA_RUN_USER}:${CARLA_RUN_USER}" "$CARLA_ROOT"
chmod -R o+x "$ENV_HOME" || true

echo "[INFO] Configuring X11 access..."
export DISPLAY="$VNC_DISPLAY"
xhost +

echo "[INFO] Starting CARLA as '${CARLA_RUN_USER}' on port ${CARLA_PORT}..."
su "$CARLA_RUN_USER" -c "
    export DISPLAY=${VNC_DISPLAY}
    cd '${CARLA_ROOT}'
    ./CarlaUE4.sh -world-port=${CARLA_PORT} -quality-level=${CARLA_QUALITY}
"

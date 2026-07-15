#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env_config.sh
source "${SCRIPT_DIR}/env_config.sh"

CARLA_LAUNCHER="${CARLA_ROOT}/CarlaUE4.sh"

echo "=============================="
echo "Starting CARLA ${CARLA_VERSION}"
echo "=============================="

if [ ! -x "$CARLA_LAUNCHER" ]; then
    echo "[ERROR] CARLA launcher is absent or not executable: $CARLA_LAUNCHER"
    echo "Run stage3_carla.sh first or set CARLA_ROOT correctly."
    exit 1
fi

case "$CARLA_RENDER_MODE" in
    offscreen)
        RENDER_ARGS=(-RenderOffScreen -nosound)
        ;;
    display)
        export DISPLAY="${DISPLAY:-${CARLA_DISPLAY}}"
        DISPLAY_NUM="${DISPLAY#:}"
        DISPLAY_NUM="${DISPLAY_NUM%%.*}"
        if [ ! -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
            echo "[ERROR] CARLA_RENDER_MODE=display, but no X server is available at DISPLAY=${DISPLAY}."
            echo "Start an X desktop first or use CARLA_RENDER_MODE=offscreen for unattended runs."
            exit 1
        fi
        RENDER_ARGS=()
        ;;
    *)
        echo "[ERROR] CARLA_RENDER_MODE must be 'offscreen' or 'display'; got: ${CARLA_RENDER_MODE}"
        exit 2
        ;;
esac

echo "  user:        $(id -un) (uid=$(id -u))"
echo "  root:        ${CARLA_ROOT}"
echo "  port:        ${CARLA_PORT}"
echo "  quality:     ${CARLA_QUALITY}"
echo "  render mode: ${CARLA_RENDER_MODE}"

cd "$CARLA_ROOT"

# No user creation, chown, sudo, or xhost is performed. Display mode reuses the
# current user's X session; offscreen mode needs no X/VNC. Extra launcher flags
# may be appended by the caller.
exec "$CARLA_LAUNCHER" \
    "-world-port=${CARLA_PORT}" \
    "-quality-level=${CARLA_QUALITY}" \
    "${RENDER_ARGS[@]}" \
    "$@"

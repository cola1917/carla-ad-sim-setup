#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

if pgrep -x Xvnc > /dev/null; then
    echo "TurboVNC is already running."
    exit 0
fi

rm -f "/tmp/.X${VNC_DISPLAY_NUM}-lock"
rm -f "/tmp/.X11-unix/X${VNC_DISPLAY_NUM}"
rm -f "$HOME/.vnc/"*.pid
rm -f "$HOME/.vnc/"*.log

/opt/TurboVNC/bin/vncserver ":${VNC_DISPLAY_NUM}" \
    -geometry "$VNC_GEOMETRY" \
    -depth 24 \
    -rfbport "$VNC_PORT" \
    -xstartup "$HOME/.vnc/xstartup"

echo
echo "TurboVNC started."
echo "Display: :${VNC_DISPLAY_NUM}"
echo "Port: ${VNC_PORT}"

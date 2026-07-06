#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "========== Stage 1: Desktop + TurboVNC =========="

apt update
apt install -y \
    xfce4 \
    xfce4-terminal \
    thunar \
    dbus-x11 \
    x11-xserver-utils \
    xauth

mkdir -p "$BLOCKDATA_DIR"

if [ ! -f "$TURBOVNC_DEB" ]; then
    echo "[ERROR] TurboVNC package not found: $TURBOVNC_DEB"
    echo "Put turbovnc_3.3_amd64.deb in ${BLOCKDATA_DIR}."
    exit 1
fi

dpkg -i "$TURBOVNC_DEB" || true
apt install -f -y

mkdir -p "$HOME/.vnc"
echo "${VNC_PASSWORD}" | /opt/TurboVNC/bin/vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

cat > "$HOME/.vnc/xstartup" << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
exec startxfce4
EOF
chmod +x "$HOME/.vnc/xstartup"

bash "${SCRIPT_DIR}/start_vnc.sh"

echo
echo "======================================="
echo "Stage 1 completed."
echo "VNC address: <Pod_IP>:${VNC_PORT}"
echo "Password: ${VNC_PASSWORD}"
echo "======================================="

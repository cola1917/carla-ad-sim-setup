#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "========== Stage 0: sim-env + Miniconda + Mirrors =========="

echo "[1/4] Creating directory layout under ${ENV_HOME}..."
mkdir -p "$ENV_HOME" "$BLOCKDATA_DIR" "$ROS2_WS"

echo "[2/4] Configuring apt mirror (${APT_MIRROR})..."
if [ ! -f /etc/apt/sources.list.env_build.bak ]; then
    run_root cp /etc/apt/sources.list /etc/apt/sources.list.env_build.bak
fi

APT_SOURCES_TMP="$(mktemp)"
cat > "$APT_SOURCES_TMP" << EOF
deb ${APT_MIRROR} ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${APT_MIRROR} ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb ${APT_MIRROR} ${UBUNTU_CODENAME}-security main restricted universe multiverse
deb ${APT_MIRROR} ${UBUNTU_CODENAME}-backports main restricted universe multiverse
EOF
run_root install -m 0644 "$APT_SOURCES_TMP" /etc/apt/sources.list
rm -f "$APT_SOURCES_TMP"

run_root apt-get update

echo "[3/4] Installing Miniconda to ${CONDA_ROOT}..."
if [ ! -f "$CONDA_SH" ]; then
    INSTALLER="$(mktemp /tmp/miniconda_XXXXXX.sh)"
    wget -O "$INSTALLER" "$MINICONDA_INSTALLER_URL"
    bash "$INSTALLER" -b -p "$CONDA_ROOT"
    rm -f "$INSTALLER"
    echo "[OK] Miniconda installed."
else
    echo "[OK] Miniconda already installed: $CONDA_ROOT"
fi

source "$CONDA_SH"

cat > "$CONDA_ROOT/.condarc" << 'EOF'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF

echo "[4/4] Configuring shell and pip mirrors..."
mkdir -p "$HOME/.pip"
cat > "$HOME/.pip/pip.conf" << EOF
[global]
index-url = ${PIP_INDEX_URL}
trusted-host = ${PIP_TRUSTED_HOST}
EOF

BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if ! grep -q "# >>> conda initialize >>>" "$BASHRC"; then
    conda init bash
    echo "[OK] conda init added to ~/.bashrc"
else
    echo "[INFO] conda init already present in ~/.bashrc. Skipping."
fi

echo
echo "======================================="
echo "Stage 0 completed."
echo
echo "Runtime root:  ${ENV_HOME}"
echo "Data dir:      ${BLOCKDATA_DIR}"
echo "Conda root:    ${CONDA_ROOT}"
echo
echo "Put offline files in ${BLOCKDATA_DIR}:"
echo "  - carla-${CARLA_VERSION_DASH}-linux.tar.gz"
echo "  - Carla-Autoware-Bridge-main.zip"
echo "  - turbovnc_3.3_amd64.deb"
echo "======================================="

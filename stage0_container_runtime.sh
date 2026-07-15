#!/usr/bin/env bash
# Install Docker Engine and NVIDIA Container Toolkit on an Ubuntu host.
set -euo pipefail

source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "[ERROR] Ubuntu is required (found: ${ID:-unknown})." >&2
    exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || { echo "[ERROR] sudo is required." >&2; exit 1; }
    SUDO=(sudo)
fi

DOCKER_TEST_IMAGE="${DOCKER_TEST_IMAGE:-nvidia/cuda:12.8.0-base-ubuntu22.04}"
INSTALL_DOCKER="${INSTALL_DOCKER:-1}"
DOCKER_APT_URI="${DOCKER_APT_URI:-https://download.docker.com/linux/ubuntu}"
DOCKER_APT_RETRIES="${DOCKER_APT_RETRIES:-3}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "========== Stage 0C: Docker + NVIDIA Container Toolkit =========="
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y ca-certificates curl gnupg

if command -v docker >/dev/null 2>&1; then
    echo "[OK] Docker already installed: $(docker --version)"
elif [[ "${INSTALL_DOCKER}" == "1" ]]; then
    ARCH="$(dpkg --print-architecture)"
    CODENAME="${VERSION_CODENAME:-jammy}"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${TMP_DIR}/docker.asc"
    "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
    "${SUDO[@]}" install -m 0644 "${TMP_DIR}/docker.asc" /etc/apt/keyrings/docker.asc
    cat > "${TMP_DIR}/docker.sources" <<EOF
Types: deb
URIs: ${DOCKER_APT_URI}
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    "${SUDO[@]}" install -m 0644 "${TMP_DIR}/docker.sources" /etc/apt/sources.list.d/docker.sources
    DOCKER_CE_AVAILABLE=0
    for ((attempt = 1; attempt <= DOCKER_APT_RETRIES; attempt++)); do
        echo "[INFO] Refreshing Docker apt index (${attempt}/${DOCKER_APT_RETRIES})..."
        "${SUDO[@]}" apt-get update || true
        if apt-cache show docker-ce >/dev/null 2>&1; then
            DOCKER_CE_AVAILABLE=1
            break
        fi
        sleep "$((attempt * 2))"
    done

    if [[ "${DOCKER_CE_AVAILABLE}" == "1" ]]; then
        "${SUDO[@]}" apt-get install -y \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        echo "[WARN] Docker CE repository is unavailable; falling back to Ubuntu docker.io."
        UBUNTU_DOCKER_PACKAGES=(docker.io)
        for package in docker-buildx docker-compose-v2; do
            if apt-cache show "${package}" >/dev/null 2>&1; then
                UBUNTU_DOCKER_PACKAGES+=("${package}")
            fi
        done
        "${SUDO[@]}" apt-get install -y "${UBUNTU_DOCKER_PACKAGES[@]}"
    fi
else
    command -v docker >/dev/null 2>&1 || { echo "[ERROR] docker is not installed." >&2; exit 1; }
fi

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey -o "${TMP_DIR}/nvidia.gpgkey"
gpg --dearmor --yes --output "${TMP_DIR}/nvidia-keyring.gpg" "${TMP_DIR}/nvidia.gpgkey"
"${SUDO[@]}" install -m 0644 "${TMP_DIR}/nvidia-keyring.gpg" \
    /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    -o "${TMP_DIR}/nvidia.list"
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    "${TMP_DIR}/nvidia.list" > "${TMP_DIR}/nvidia.signed.list"
"${SUDO[@]}" install -m 0644 "${TMP_DIR}/nvidia.signed.list" \
    /etc/apt/sources.list.d/nvidia-container-toolkit.list
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y nvidia-container-toolkit
"${SUDO[@]}" nvidia-ctk runtime configure --runtime=docker
"${SUDO[@]}" systemctl restart docker
if [[ "${EUID}" -ne 0 ]]; then
    "${SUDO[@]}" usermod -aG docker "${USER}"
fi

"${SUDO[@]}" docker run --rm --gpus all "${DOCKER_TEST_IMAGE}" \
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo "[OK] Docker Engine and NVIDIA Container Toolkit are ready."
if [[ "${EUID}" -ne 0 ]] && ! id -nG | tr ' ' '\n' | grep -qx docker; then
    echo "[INFO] Reconnect SSH before using docker without sudo."
fi

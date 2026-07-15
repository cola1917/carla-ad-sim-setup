#!/usr/bin/env bash
# Install and validate Docker Engine plus NVIDIA Container Toolkit on Ubuntu.
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

DOCKER_APT_URI="${DOCKER_APT_URI:-https://download.docker.com/linux/ubuntu}"
DOCKER_GPG_URL="${DOCKER_GPG_URL:-${DOCKER_APT_URI}/gpg}"
NVIDIA_GPG_URL="${NVIDIA_GPG_URL:-https://nvidia.github.io/libnvidia-container/gpgkey}"
NVIDIA_LIST_URL="${NVIDIA_LIST_URL:-https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list}"
DOCKER_TEST_IMAGE="${DOCKER_TEST_IMAGE:-nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04}"
DOCKER_SHM_SIZE="${DOCKER_SHM_SIZE:-32g}"
NETWORK_RETRIES="${NETWORK_RETRIES:-5}"
INSTALL_DOCKER="${INSTALL_DOCKER:-1}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

retry() {
    local attempt=1
    while ! "$@"; do
        if (( attempt >= NETWORK_RETRIES )); then
            return 1
        fi
        echo "[WARN] Attempt ${attempt}/${NETWORK_RETRIES} failed: $*" >&2
        sleep "$((attempt * 2))"
        attempt=$((attempt + 1))
    done
}

download() {
    local url="$1"
    local output="$2"
    curl --fail --location --silent --show-error \
        --connect-timeout 15 --max-time 180 \
        --retry "${NETWORK_RETRIES}" --retry-all-errors --retry-delay 2 \
        --output "${output}" "${url}"
}

disable_source() {
    local source_file="$1"
    if [[ -f "${source_file}" ]]; then
        "${SUDO[@]}" mv "${source_file}" "${source_file}.disabled"
    fi
}

echo "========== Stage 0C: Docker + NVIDIA Container Toolkit =========="
# A stale third-party source must not prevent the script from reaching its
# repair logic. Package installation below remains the authoritative gate.
"${SUDO[@]}" apt-get update || echo "[WARN] Initial apt refresh was partial; continuing with cached Ubuntu indexes."
"${SUDO[@]}" apt-get install -y ca-certificates curl gnupg

if command -v docker >/dev/null 2>&1; then
    echo "[OK] Docker already installed: $(docker --version)"
elif [[ "${INSTALL_DOCKER}" == "1" ]]; then
    ARCH="$(dpkg --print-architecture)"
    CODENAME="${VERSION_CODENAME:-jammy}"
    download "${DOCKER_GPG_URL}" "${TMP_DIR}/docker.asc"
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

    if retry "${SUDO[@]}" apt-get update && \
        "${SUDO[@]}" apt-get install -y \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        echo "[OK] Docker Engine installed from ${DOCKER_APT_URI}."
    else
        echo "[WARN] Docker CE install failed; disabling that source and using Ubuntu docker.io."
        disable_source /etc/apt/sources.list.d/docker.sources
        retry "${SUDO[@]}" apt-get update
        UBUNTU_DOCKER_PACKAGES=(docker.io)
        for package in docker-buildx docker-compose-v2; do
            if apt-cache show "${package}" >/dev/null 2>&1; then
                UBUNTU_DOCKER_PACKAGES+=("${package}")
            fi
        done
        "${SUDO[@]}" apt-get install -y "${UBUNTU_DOCKER_PACKAGES[@]}"
    fi
else
    echo "[ERROR] INSTALL_DOCKER=0 but docker is not installed." >&2
    exit 1
fi

download "${NVIDIA_GPG_URL}" "${TMP_DIR}/nvidia.gpgkey"
gpg --dearmor --yes --output "${TMP_DIR}/nvidia-keyring.gpg" "${TMP_DIR}/nvidia.gpgkey"
"${SUDO[@]}" install -m 0644 "${TMP_DIR}/nvidia-keyring.gpg" \
    /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
download "${NVIDIA_LIST_URL}" "${TMP_DIR}/nvidia.list"
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    "${TMP_DIR}/nvidia.list" > "${TMP_DIR}/nvidia.signed.list"
"${SUDO[@]}" install -m 0644 "${TMP_DIR}/nvidia.signed.list" \
    /etc/apt/sources.list.d/nvidia-container-toolkit.list
retry "${SUDO[@]}" apt-get update
retry "${SUDO[@]}" apt-get install -y nvidia-container-toolkit
"${SUDO[@]}" nvidia-ctk runtime configure --runtime=docker
"${SUDO[@]}" systemctl restart docker
if [[ "${EUID}" -ne 0 ]]; then
    "${SUDO[@]}" usermod -aG docker "${USER}"
fi

echo "[INFO] Pulling CUDA probe image separately from runtime validation..."
retry "${SUDO[@]}" docker pull "${DOCKER_TEST_IMAGE}"
"${SUDO[@]}" docker run --rm --gpus all --shm-size="${DOCKER_SHM_SIZE}" \
    "${DOCKER_TEST_IMAGE}" bash -lc '
        set -e
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
        shm_mib=$(df -Pm /dev/shm | awk "NR == 2 {print \$2}")
        test "$shm_mib" -ge 30000
        echo "container /dev/shm: ${shm_mib} MiB"
    '

echo "[OK] Docker Engine, NVIDIA Container Toolkit, GPU access, and ${DOCKER_SHM_SIZE} /dev/shm are ready."
if [[ "${EUID}" -ne 0 ]] && ! id -nG | tr ' ' '\n' | grep -qx docker; then
    echo "[INFO] Reconnect SSH before using docker without sudo."
fi

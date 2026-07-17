#!/usr/bin/env bash
# Shared configuration for the autonomous-driving simulation environment.
# Edit this file once, copy env_config.local.sh.example, or override at runtime.

ENV_BUILD_ROOT="${ENV_BUILD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Run only host package/system-file operations as root. Runtime data and shell
# configuration remain owned by the invoking user under ENV_HOME/HOME.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    ENV_BUILD_SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    ENV_BUILD_SUDO=(sudo)
else
    echo "[ERROR] sudo is required for host package installation." >&2
    return 1 2>/dev/null || exit 1
fi
run_root() {
    "${ENV_BUILD_SUDO[@]}" "$@"
}

# Root directory for all generated runtime data (replaces legacy ~/blockdata layout).
ENV_HOME="${ENV_HOME:-$HOME/sim-env}"

# Offline archives and extracted third-party runtimes.
BLOCKDATA_DIR="${BLOCKDATA_DIR:-$ENV_HOME/data}"

# Conda settings.
CONDA_ROOT="${CONDA_ROOT:-$ENV_HOME/miniconda3}"
CONDARC="${CONDARC:-$CONDA_ROOT/.condarc}"
export CONDARC
CONDA_ENV_NAME="${CONDA_ENV_NAME:-autodrive}"
PYTHON_VERSION="${PYTHON_VERSION:-3.10}"
PYTHON_TAG="${PYTHON_TAG:-${PYTHON_VERSION//./}}"
CONDA_SH="$CONDA_ROOT/etc/profile.d/conda.sh"

# Mirror settings.
UBUNTU_CODENAME="${UBUNTU_CODENAME:-jammy}"
APT_MIRROR="${APT_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/ubuntu/}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
MINICONDA_INSTALLER_URL="${MINICONDA_INSTALLER_URL:-https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh}"

# CARLA settings.
CARLA_VERSION="${CARLA_VERSION:-0.9.16}"
CARLA_VERSION_DASH="${CARLA_VERSION_DASH:-${CARLA_VERSION//./-}}"
CARLA_TAR_FILE="${CARLA_TAR_FILE:-$BLOCKDATA_DIR/carla-${CARLA_VERSION_DASH}-linux.tar.gz}"
CARLA_ROOT="${CARLA_ROOT:-$BLOCKDATA_DIR/CARLA_${CARLA_VERSION}}"
CARLA_WHEEL="${CARLA_WHEEL:-$CARLA_ROOT/PythonAPI/carla/dist/carla-${CARLA_VERSION}-cp${PYTHON_TAG}-cp${PYTHON_TAG}-manylinux_2_31_x86_64.whl}"
CARLA_HOST="${CARLA_HOST:-localhost}"
CARLA_PORT="${CARLA_PORT:-2000}"
CARLA_QUALITY="${CARLA_QUALITY:-Low}"
CARLA_RENDER_MODE="${CARLA_RENDER_MODE:-display}"
CARLA_DISPLAY="${CARLA_DISPLAY:-:1}"

# VNC settings.
VNC_PASSWORD="${VNC_PASSWORD:-12345678}"
VNC_DISPLAY_NUM="${VNC_DISPLAY_NUM:-1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
VNC_PORT="${VNC_PORT:-5901}"
TURBOVNC_DEB="${TURBOVNC_DEB:-$BLOCKDATA_DIR/turbovnc_3.3_amd64.deb}"

# ROS / CARLA bridge settings.
ROS_DISTRO="${ROS_DISTRO:-humble}"
ROS2_WS="${ROS2_WS:-$ENV_HOME/carla-ros2-ws}"
CARLA_ROS_BRIDGE_REPO_URL="${CARLA_ROS_BRIDGE_REPO_URL:-https://github.com/carla-simulator/ros-bridge.git}"
CARLA_ROS_BRIDGE_REF="${CARLA_ROS_BRIDGE_REF:-e9063d97ff5a724f76adbb1b852dc71da1dcfeec}"
SCENARIO_RUNNER_ROOT="${SCENARIO_RUNNER_ROOT:-$BLOCKDATA_DIR/scenario_runner}"
SCENARIO_RUNNER_TAG="${SCENARIO_RUNNER_TAG:-v${CARLA_VERSION}}"

# NuRec gRPC settings. Formal replay uses `nre-ga:26.04 serve-grpc`; the
# standalone carlasimulator/nvidia-nurec-grpc:0.2.0 image cannot load 26.04
# artifacts and was removed from setup. NVIDIA NGC NuRec images require NVIDIA
# authorization, so their domestic mirrors are opt-in and must resolve to the
# pinned digests.
CLOSED_LOOP_BENCH_ROOT="${CLOSED_LOOP_BENCH_ROOT:-$HOME/workspace/ClosedLoopBench}"
NUREC_MAIN_IMAGE="${NUREC_MAIN_IMAGE:-nvcr.io/nvidia/nre/nre-ga:26.04}"
NUREC_MAIN_IMAGE_DIGEST="${NUREC_MAIN_IMAGE_DIGEST:-sha256:1c3a838440fce96258e055615b146fa8f75ad2a799e131aaa480755592317d1f}"
NUREC_TOOLS_IMAGE="${NUREC_TOOLS_IMAGE:-nvcr.io/nvidia/nre/nre-tools-ga:26.04}"
NUREC_TOOLS_IMAGE_DIGEST="${NUREC_TOOLS_IMAGE_DIGEST:-sha256:d9c19b67a86c7fca71c2c23250a953870e616c562325fb27131d004c7f8bef1c}"
NUREC_MAIN_MIRROR_IMAGE="${NUREC_MAIN_MIRROR_IMAGE:-}"
NUREC_TOOLS_MIRROR_IMAGE="${NUREC_TOOLS_MIRROR_IMAGE:-}"
NUREC_APPLY_CARLA_PATCHES="${NUREC_APPLY_CARLA_PATCHES:-1}"
NUREC_SHM_SIZE="${NUREC_SHM_SIZE:-64g}"

# Optional machine-local overrides (not tracked by git).
if [ -f "$ENV_BUILD_ROOT/env_config.local.sh" ]; then
    # shellcheck source=/dev/null
    source "$ENV_BUILD_ROOT/env_config.local.sh"
fi

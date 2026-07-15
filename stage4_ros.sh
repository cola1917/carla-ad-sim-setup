#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

if [ "$ROS_DISTRO" != "humble" ]; then
    echo "[ERROR] Stage 4 targets ROS 2 Humble on Ubuntu 22.04; got ROS_DISTRO=$ROS_DISTRO."
    exit 2
fi

echo "=========================================="
echo "Stage 4: ROS 2 + CARLA ROS Bridge"
echo "=========================================="

echo "[1/4] Installing ROS 2 ${ROS_DISTRO} dependencies..."
run_root apt-get update
run_root apt-get install -y software-properties-common curl gnupg2 lsb-release

ROS_KEY_TMP="$(mktemp)"
ROS_KEY_GPG_TMP="$(mktemp)"
curl -sSL https://mirrors.tuna.tsinghua.edu.cn/rosdistro/ros.key \
    -o "$ROS_KEY_TMP"
gpg --dearmor --yes --output "$ROS_KEY_GPG_TMP" "$ROS_KEY_TMP"
run_root install -m 0644 "$ROS_KEY_GPG_TMP" /usr/share/keyrings/ros-archive-keyring.gpg
rm -f "$ROS_KEY_TMP" "$ROS_KEY_GPG_TMP"
ROS_LIST_TMP="$(mktemp)"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu $(lsb_release -cs) main" > "$ROS_LIST_TMP"
run_root install -m 0644 "$ROS_LIST_TMP" /etc/apt/sources.list.d/ros2.list
rm -f "$ROS_LIST_TMP"

run_root apt-get update

# Some rental images contain an orphaned libicu70 point build that is absent
# from their configured Jammy mirrors. ROS desktop pulls libicu-dev, whose
# dependency requires an exact libicu70 version. Repair only that mismatched
# runtime package instead of performing an unrelated full-system upgrade.
ICU_REQUIRED_VERSION="$(
    apt-cache show libicu-dev 2>/dev/null \
        | sed -n 's/^Depends:.*libicu70 (= \([^)]*\)).*/\1/p' \
        | head -n 1
)"
ICU_INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' libicu70 2>/dev/null || true)"
if [ -n "$ICU_REQUIRED_VERSION" ] && \
   [ -n "$ICU_INSTALLED_VERSION" ] && \
   [ "$ICU_INSTALLED_VERSION" != "$ICU_REQUIRED_VERSION" ]; then
    echo "[WARN] Repairing libicu70 version mismatch: installed=${ICU_INSTALLED_VERSION}, required=${ICU_REQUIRED_VERSION}"
    run_root apt-get install -y --allow-downgrades "libicu70=${ICU_REQUIRED_VERSION}"
fi

run_root apt-get install -y \
    "ros-${ROS_DISTRO}-desktop" \
    "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" \
    "ros-${ROS_DISTRO}-tf2-eigen" \
    python3-colcon-common-extensions \
    python3-rosdep

if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    run_root rosdep init || true
fi
rosdep update || true

echo "[2/4] Preparing ROS 2 workspace: $ROS2_WS"
mkdir -p "${ROS2_WS}/src"
cd "${ROS2_WS}/src"

clone_at_ref() {
    local url="$1"
    local ref="$2"
    local destination="$3"

    if [ -d "$destination/.git" ]; then
        current_ref="$(git -C "$destination" rev-parse HEAD)"
        if [ "$current_ref" = "$ref" ]; then
            echo "[INFO] Reusing pinned checkout: $destination ($ref)"
            git -C "$destination" submodule update --init --recursive
            return
        fi
        if [ -n "$(git -C "$destination" status --porcelain)" ]; then
            echo "[ERROR] Existing checkout is at $current_ref and has local changes: $destination"
            echo "Commit or remove those changes before switching to pinned ref $ref."
            exit 1
        fi
        if ! git -C "$destination" cat-file -e "${ref}^{commit}" 2>/dev/null; then
            git -C "$destination" fetch origin "$ref"
        fi
        git -C "$destination" checkout --detach "$ref"
        git -C "$destination" submodule update --init --recursive
        return
    fi
    if [ -e "$destination" ]; then
        echo "[ERROR] Destination exists but is not a Git checkout: $destination"
        exit 1
    fi

    git clone --recursive "$url" "$destination"
    git -C "$destination" checkout --detach "$ref"
    git -C "$destination" submodule update --init --recursive
}

if [ -d "ros-bridge/.git" ]; then
    ROS_BRIDGE_SRC="${ROS2_WS}/src/ros-bridge"
    clone_at_ref "$CARLA_ROS_BRIDGE_REPO_URL" "$CARLA_ROS_BRIDGE_REF" "$ROS_BRIDGE_SRC"
else
    mkdir -p carla
    ROS_BRIDGE_SRC="${ROS2_WS}/src/carla/ros-bridge"
    clone_at_ref "$CARLA_ROS_BRIDGE_REPO_URL" "$CARLA_ROS_BRIDGE_REF" "$ROS_BRIDGE_SRC"
fi

echo "[3/4] Building bridge workspace..."
source "/opt/ros/${ROS_DISTRO}/setup.bash"

if [ ! -f "$CONDA_SH" ]; then
    echo "[ERROR] Conda profile not found: $CONDA_SH"
    exit 1
fi
source "$CONDA_SH"
conda activate "$CONDA_ENV_NAME"

cd "$ROS2_WS"
rosdep install --from-paths "$ROS_BRIDGE_SRC" --ignore-src -r -y

echo "$CARLA_VERSION" > "$ROS_BRIDGE_SRC/carla_ros_bridge/src/carla_ros_bridge/CARLA_VERSION"
echo "[INFO] Set ros-bridge CARLA version to ${CARLA_VERSION}"

sed -i 's/pcl_conversions tf2 tf2_ros)/pcl_conversions tf2 tf2_eigen tf2_geometry_msgs tf2_ros)/' \
    "$ROS_BRIDGE_SRC/pcl_recorder/CMakeLists.txt"
sed -i 's|tf2_eigen/tf2_eigen.h|tf2_eigen/tf2_eigen.hpp|g' \
    "$ROS_BRIDGE_SRC/pcl_recorder/include/PclRecorderROS2.h"

colcon build --base-paths "$ROS_BRIDGE_SRC" --symlink-install

echo "[4/4] Writing shell environment to ~/.bashrc..."
BASHRC="$HOME/.bashrc"
START_MARKER="# === env_build ROS2 START ==="
END_MARKER="# === env_build ROS2 END ==="
TMP_BASHRC="$(mktemp)"

sed "/${START_MARKER}/,/${END_MARKER}/d" "$BASHRC" > "$TMP_BASHRC"
cat > "$BASHRC" << EOF
${START_MARKER}
source /opt/ros/${ROS_DISTRO}/setup.bash
source ${ROS2_WS}/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export PYTHONPATH="${CONDA_ROOT}/envs/${CONDA_ENV_NAME}/lib/python${PYTHON_VERSION}/site-packages:\${PYTHONPATH}"
${END_MARKER}
EOF
cat "$TMP_BASHRC" >> "$BASHRC"
rm "$TMP_BASHRC"

echo "Stage 4 completed."

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "Stage 4: ROS 2 + TUM Carla-Autoware-Bridge"
echo "=========================================="

echo "[1/4] Installing ROS 2 ${ROS_DISTRO} dependencies..."
apt update
apt install -y software-properties-common curl gnupg2 lsb-release

curl -sSL https://mirrors.tuna.tsinghua.edu.cn/rosdistro/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/ros2.list > /dev/null

apt update
apt install -y \
    "ros-${ROS_DISTRO}-desktop" \
    "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" \
    "ros-${ROS_DISTRO}-tf2-eigen" \
    python3-colcon-common-extensions \
    python3-rosdep

if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    rosdep init || true
fi
rosdep update || true

echo "[2/4] Preparing ROS 2 workspace: $ROS2_WS"
mkdir -p "${ROS2_WS}/src"
cd "${ROS2_WS}/src"

if [ ! -d "ros-bridge" ]; then
    git clone --recursive https://github.com/carla-simulator/ros-bridge.git
fi

if [ ! -f "$BRIDGE_ZIP" ]; then
    echo "[ERROR] Bridge zip not found: $BRIDGE_ZIP"
    echo "Set BRIDGE_ZIP or put Carla-Autoware-Bridge-main.zip in ${BLOCKDATA_DIR}."
    exit 1
fi

rm -rf Carla-Autoware-Bridge Carla-Autoware-Bridge-main
unzip -o -q "$BRIDGE_ZIP"
mv Carla-Autoware-Bridge-main Carla-Autoware-Bridge

echo "[3/4] Building bridge workspace..."
source "/opt/ros/${ROS_DISTRO}/setup.bash"

if [ ! -f "$CONDA_SH" ]; then
    echo "[ERROR] Conda profile not found: $CONDA_SH"
    exit 1
fi
source "$CONDA_SH"
conda activate "$CONDA_ENV_NAME"

cd "$ROS2_WS"
rosdepc install --from-paths src --ignore-src -r -y

echo "$CARLA_VERSION" > "src/ros-bridge/carla_ros_bridge/src/carla_ros_bridge/CARLA_VERSION"
echo "[INFO] Set ros-bridge CARLA version to ${CARLA_VERSION}"

sed -i 's/pcl_conversions tf2 tf2_ros)/pcl_conversions tf2 tf2_eigen tf2_geometry_msgs tf2_ros)/' \
    "$ROS2_WS/src/ros-bridge/pcl_recorder/CMakeLists.txt"
sed -i 's|tf2_eigen/tf2_eigen.h|tf2_eigen/tf2_eigen.hpp|g' \
    "$ROS2_WS/src/ros-bridge/pcl_recorder/include/PclRecorderROS2.h"

colcon build --symlink-install

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

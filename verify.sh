#!/bin/bash
# Check environment readiness, stage completion, and runtime smoke tests.
# Usage:
#   bash verify.sh          # full report
#   bash verify.sh 0        # only Stage 0 checks
#   bash verify.sh 3        # Stage 3 static + CARLA runtime (server must be running)
#   bash verify.sh 4        # Stage 4 static + ROS 2 DDS runtime
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env_config.sh
source "${SCRIPT_DIR}/env_config.sh"

STAGE_FILTER="${1:-all}"

PASS=0
FAIL=0
WARN=0

pass() {
    printf "  [PASS] %s\n" "$1"
    PASS=$((PASS + 1))
}

fail() {
    printf "  [FAIL] %s\n" "$1"
    FAIL=$((FAIL + 1))
}

warn() {
    printf "  [WARN] %s\n" "$1"
    WARN=$((WARN + 1))
}

should_run() {
    local stage="$1"
    [ "$STAGE_FILTER" = "all" ] || [ "$STAGE_FILTER" = "$stage" ]
}

check_file() {
    local desc="$1"
    local path="$2"
    if [ -e "$path" ]; then
        pass "$desc: $path"
    else
        fail "$desc: $path"
    fi
}

check_cmd() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

check_bashrc_marker() {
    local desc="$1"
    local marker="$2"
    if [ -f "$HOME/.bashrc" ] && grep -qF "$marker" "$HOME/.bashrc"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

activate_conda_env() {
    if [ ! -f "$CONDA_SH" ]; then
        return 1
    fi
    # shellcheck disable=SC1090
    source "$CONDA_SH"
    conda activate "$CONDA_ENV_NAME"
}

activate_ros_env() {
    # shellcheck disable=SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    # shellcheck disable=SC1091
    source "${ROS2_WS}/install/setup.bash"
    export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
    export CARLA_ROOT
    activate_conda_env
}

cleanup_ros_demo_nodes() {
    pkill -9 -f "demo_nodes_cpp" 2>/dev/null || true
    sleep 0.5
    wait 2>/dev/null || true
}

carla_server_reachable() {
    activate_conda_env || return 1
    export CARLA_HOST CARLA_PORT
    python - <<'PY'
import os
import carla

client = carla.Client(os.environ["CARLA_HOST"], int(os.environ["CARLA_PORT"]))
client.set_timeout(3.0)
client.get_server_version()
PY
}

run_stage3_runtime_test() {
    activate_conda_env || {
        fail "CARLA runtime test (conda not available)"
        return
    }

    export CARLA_HOST CARLA_PORT

    if ! carla_server_reachable; then
        warn "CARLA runtime test skipped (server not reachable at ${CARLA_HOST}:${CARLA_PORT}; run: bash start_carla.sh)"
        return
    fi

    if python - <<'PY'
import os
import random
import time

import carla

host = os.environ["CARLA_HOST"]
port = int(os.environ["CARLA_PORT"])

client = carla.Client(host, port)
client.set_timeout(10.0)

world = client.get_world()
bp_lib = world.get_blueprint_library()
vehicle_bp = bp_lib.filter("vehicle.*model3*")[0]
spawn_points = world.get_map().get_spawn_points()

spawn_point = random.choice(spawn_points)
vehicle = world.try_spawn_actor(vehicle_bp, spawn_point)
if vehicle is None:
    raise RuntimeError("spawn failed; the selected spawn point may be occupied")

try:
    vehicle.apply_control(carla.VehicleControl(throttle=0.3))
    time.sleep(3)
    vehicle.apply_control(carla.VehicleControl(throttle=0.0, brake=1.0))
    time.sleep(1)
finally:
    vehicle.destroy()
PY
    then
        pass "CARLA runtime test (connect, spawn, destroy)"
    else
        fail "CARLA runtime test (connect, spawn, destroy)"
    fi
}

run_stage4_runtime_tests() {
    if ! activate_ros_env; then
        fail "ROS 2 runtime tests (environment not available)"
        return
    fi

    cleanup_ros_demo_nodes
    trap cleanup_ros_demo_nodes EXIT

    check_cmd "ros2 topic command is available" "ros2 topic --help"
    check_cmd "colcon is available" "colcon --help"
    check_cmd "import carla under ROS environment" "python -c 'import carla'"
    check_cmd "carla_ros_bridge package prefix exists" \
        "ros2 pkg prefix carla_ros_bridge 2>/dev/null | grep -q install"
    check_cmd "CARLA_ROOT is set" "[ -n \"${CARLA_ROOT}\" ]"
    check_cmd "CycloneDDS is enabled" "[ \"${RMW_IMPLEMENTATION}\" = \"rmw_cyclonedds_cpp\" ]"

    echo "  [INFO] ROS 2 talker/listener DDS test (~2s)..."
    ros2 run demo_nodes_cpp talker &
    local talker_pid=$!
    sleep 1
    local listener_output
    listener_output=$(timeout 2 ros2 run demo_nodes_cpp listener 2>&1 || true)
    kill -9 "$talker_pid" 2>/dev/null || true
    wait "$talker_pid" 2>/dev/null || true
    cleanup_ros_demo_nodes
    trap - EXIT

    if echo "${listener_output}" | grep -q "I heard"; then
        pass "ROS 2 talker/listener communication"
    else
        fail "ROS 2 talker/listener communication"
    fi
}

echo "=========================================="
echo "Environment verification"
echo "=========================================="
echo "ENV_HOME:      $ENV_HOME"
echo "BLOCKDATA_DIR: $BLOCKDATA_DIR"
echo "CONDA_ROOT:    $CONDA_ROOT"
echo "CARLA_ROOT:    $CARLA_ROOT"
echo "ROS2_WS:       $ROS2_WS"
echo "Filter:        $STAGE_FILTER"
echo

if should_run 0; then
    echo "[Stage 0] sim-env + Miniconda + mirrors"
    check_file "ENV_HOME exists" "$ENV_HOME"
    check_file "data directory exists" "$BLOCKDATA_DIR"
    check_file "ROS2 workspace root exists" "$ROS2_WS"
    check_file "Conda profile exists" "$CONDA_SH"
    check_cmd "conda command works" "source '$CONDA_SH' && conda --version"
    check_file "pip mirror config exists" "$HOME/.pip/pip.conf"
    check_bashrc_marker "conda init in ~/.bashrc" "# >>> conda initialize >>>"
    if grep -q "mirrors.tuna.tsinghua.edu.cn/ubuntu" /etc/apt/sources.list 2>/dev/null; then
        pass "apt Tsinghua mirror configured"
    else
        warn "apt Tsinghua mirror not detected in /etc/apt/sources.list"
    fi
    echo
fi

if should_run 1; then
    echo "[Stage 1] Desktop + TurboVNC"
    check_cmd "Xvnc available" "command -v Xvnc"
    check_file "TurboVNC deb present" "$TURBOVNC_DEB"
    check_file "VNC passwd file exists" "$HOME/.vnc/passwd"
    check_file "VNC xstartup exists" "$HOME/.vnc/xstartup"
    if pgrep -x Xvnc > /dev/null 2>&1; then
        pass "TurboVNC is running"
    else
        warn "TurboVNC is not running (run: bash start_vnc.sh)"
    fi
    echo
fi

if should_run 2; then
    echo "[Stage 2] Python environment"
    if [ -f "$CONDA_SH" ]; then
        # shellcheck disable=SC1090
        source "$CONDA_SH"
        if conda env list | awk '{print $1}' | grep -qx "$CONDA_ENV_NAME"; then
            pass "conda env '$CONDA_ENV_NAME' exists"
        else
            fail "conda env '$CONDA_ENV_NAME' exists"
        fi
        if conda activate "$CONDA_ENV_NAME" && python - <<'PY'
import cv2, mcap, numpy, pandas, pyarrow
PY
        then
            pass "core Python packages import"
        else
            fail "core Python packages import"
        fi
    else
        fail "conda env '$CONDA_ENV_NAME' exists (conda not installed)"
        fail "core Python packages import (conda not installed)"
    fi
    check_bashrc_marker "conda env block in ~/.bashrc" "# === env_build conda env START ==="
    echo
fi

if should_run 3; then
    echo "[Stage 3] CARLA installation"
    check_cmd "nvidia-smi works" "nvidia-smi"
    if [ -f "$CARLA_TAR_FILE" ] || [ -d "$CARLA_ROOT/PythonAPI" ]; then
        pass "CARLA archive or installation present"
    else
        fail "CARLA archive or installation present"
    fi
    check_file "CARLA root directory exists" "$CARLA_ROOT"
    check_file "CARLA PythonAPI exists" "$CARLA_ROOT/PythonAPI"
    check_file "CARLA launcher exists" "$CARLA_ROOT/CarlaUE4.sh"
    check_file "CARLA wheel exists" "$CARLA_WHEEL"
    if activate_conda_env && python -c "import carla" 2>/dev/null; then
        pass "import carla succeeds"
    else
        fail "import carla succeeds"
    fi

    echo "[Stage 3] CARLA runtime"
    run_stage3_runtime_test
    echo
fi

if should_run 4; then
    echo "[Stage 4] ROS 2 + bridge installation"
    check_cmd "ros2 command works" "source /opt/ros/${ROS_DISTRO}/setup.bash && ros2 -h"
    check_file "ROS 2 workspace install dir" "$ROS2_WS/install"
    if source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
       source "$ROS2_WS/install/setup.bash" 2>/dev/null && \
       ros2 pkg list 2>/dev/null | grep -qw carla_ros_bridge; then
        pass "carla_ros_bridge package registered"
    else
        fail "carla_ros_bridge package registered"
    fi
    check_bashrc_marker "ROS 2 block in ~/.bashrc" "# === env_build ROS2 START ==="

    echo "[Stage 4] ROS 2 runtime"
    run_stage4_runtime_tests
    echo
fi

if should_run 5; then
    echo "[Stage 5] ScenarioRunner"
    check_file "ScenarioRunner directory" "$SCENARIO_RUNNER_ROOT"
    check_file "ScenarioRunner main script" "$SCENARIO_RUNNER_ROOT/scenario_runner.py"
    check_bashrc_marker "ScenarioRunner block in ~/.bashrc" "# === env_build ScenarioRunner START ==="
    echo
fi

echo "=========================================="
echo "Summary: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Some checks failed. Run the corresponding stage script, then re-check:"
    echo "  bash verify.sh 0   # after stage0_miniconda.sh"
    echo "  bash verify.sh 3   # after stage3_carla.sh (+ bash start_carla.sh for runtime)"
    echo "  bash verify.sh 4   # after stage4_ros.sh"
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    echo
    echo "Warnings present. Static checks passed; review runtime items above."
fi

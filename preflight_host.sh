#!/usr/bin/env bash
# Classify a rental host before installing CARLA/NuRec dependencies.
# Safe by default: read-only checks. Pass --docker to run disposable GPU,
# bind-mount, and configurable shared-memory container probes.
set -euo pipefail

RUN_DOCKER=0
ALLOCATE_GIB=0
CUDA_TEST_IMAGE="${CUDA_TEST_IMAGE:-nvidia/cuda:12.8.0-base-ubuntu22.04}"
PYTORCH_TEST_IMAGE="${PYTORCH_TEST_IMAGE:-}"
MIN_GPU_MEMORY_MIB="${MIN_GPU_MEMORY_MIB:-24000}"
MIN_RAM_GIB="${MIN_RAM_GIB:-56}"
MIN_DISK_GIB="${MIN_DISK_GIB:-200}"
DOCKER_SHM_SIZE="${DOCKER_SHM_SIZE:-32g}"
MIN_DOCKER_SHM_MIB="${MIN_DOCKER_SHM_MIB:-30000}"
MAX_STEAL_WARN_PERCENT="${MAX_STEAL_WARN_PERCENT:-3}"
MAX_STEAL_FAIL_PERCENT="${MAX_STEAL_FAIL_PERCENT:-10}"

usage() {
    cat <<'EOF'
Usage:
  bash preflight_host.sh
  MIN_GPU_MEMORY_MIB=45000 bash preflight_host.sh --docker
  PYTORCH_TEST_IMAGE=nvcr.io/nvidia/pytorch:26.01-py3 \
    bash preflight_host.sh --docker --allocate-gib 36

Options:
  --docker            Run disposable Docker GPU, bind mount, and /dev/shm tests.
  --allocate-gib N    Actually allocate and touch N GiB of CUDA memory.
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --docker)
            RUN_DOCKER=1
            shift
            ;;
        --allocate-gib)
            [ "$#" -ge 2 ] || { echo "--allocate-gib requires a number" >&2; exit 2; }
            ALLOCATE_GIB="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

PASS=0
WARN=0
FAIL=0
CONTAINER_SIGNALS=()

pass() { printf '  [PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
warn() { printf '  [WARN] %s\n' "$1"; WARN=$((WARN + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
info() { printf '  [INFO] %s\n' "$1"; }

record_container_signal() {
    CONTAINER_SIGNALS+=("$1")
    fail "$1"
}

echo "=========================================="
echo "Rental host preflight"
echo "=========================================="

echo "[1] Host / virtualization classification"
VIRT="unknown"
CONTAINER_VIRT=""
VM_VIRT=""
if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt 2>/dev/null || true)"
    CONTAINER_VIRT="$(systemd-detect-virt --container 2>/dev/null || true)"
    VM_VIRT="$(systemd-detect-virt --vm 2>/dev/null || true)"
    [ -n "$VIRT" ] || VIRT="none"
    info "systemd-detect-virt: ${VIRT}"
    if [ -n "$CONTAINER_VIRT" ] && [ "$CONTAINER_VIRT" != "none" ]; then
        record_container_signal "container virtualization detected: ${CONTAINER_VIRT}"
    elif [ -n "$VM_VIRT" ] && [ "$VM_VIRT" != "none" ]; then
        pass "full VM detected: ${VM_VIRT}"
    elif [ "$VIRT" = "none" ]; then
        pass "no virtualization detected (likely bare metal)"
    else
        warn "virtualization could not be classified conclusively"
    fi
else
    warn "systemd-detect-virt is unavailable"
fi

PID1_COMM="$(ps -p 1 -o comm= 2>/dev/null | xargs || true)"
info "PID 1: ${PID1_COMM:-unknown}"
if [ "$PID1_COMM" = "systemd" ]; then
    pass "PID 1 is systemd"
else
    warn "PID 1 is not systemd; this is common in containers"
fi

CGROUP_TEXT="$(cat /proc/1/cgroup 2>/dev/null || true)"
if printf '%s' "$CGROUP_TEXT" | grep -qiE 'kubepods|docker|containerd|libpod|podman|lxc'; then
    record_container_signal "container/POD marker found in /proc/1/cgroup"
else
    pass "no container marker in PID 1 cgroup"
fi

for marker in /.dockerenv /run/.containerenv; do
    if [ -e "$marker" ]; then
        record_container_signal "container marker exists: ${marker}"
    fi
done
if [ -d /var/run/secrets/kubernetes.io/serviceaccount ]; then
    record_container_signal "Kubernetes service-account mount exists"
fi
if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
    record_container_signal "KUBERNETES_SERVICE_HOST is set"
fi

ROOT_FS="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
info "root filesystem: ${ROOT_SOURCE:-unknown} (${ROOT_FS:-unknown})"
case "$ROOT_FS" in
    overlay|overlayfs)
        record_container_signal "root filesystem is ${ROOT_FS}"
        ;;
    nfs|nfs4|cifs|ceph|fuse.*)
        fail "root filesystem is network/shared storage: ${ROOT_FS}"
        ;;
    ext4|xfs|btrfs|zfs)
        pass "root filesystem is a normal host/VM filesystem: ${ROOT_FS}"
        ;;
    *)
        warn "unrecognized root filesystem: ${ROOT_FS:-unknown}"
        ;;
esac
echo

echo "[2] CPU, memory, and disk capacity"
CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0)"
info "online CPUs: ${CPU_COUNT}"

RAM_KIB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
RAM_GIB=$((RAM_KIB / 1024 / 1024))
if [ "$RAM_GIB" -ge "$MIN_RAM_GIB" ]; then
    pass "RAM ${RAM_GIB} GiB >= ${MIN_RAM_GIB} GiB"
else
    fail "RAM ${RAM_GIB} GiB < ${MIN_RAM_GIB} GiB"
fi

DISK_GIB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 {print int($4 / 1024 / 1024)}')"
DISK_GIB="${DISK_GIB:-0}"
if [ "$DISK_GIB" -ge "$MIN_DISK_GIB" ]; then
    pass "free disk ${DISK_GIB} GiB >= ${MIN_DISK_GIB} GiB"
else
    fail "free disk ${DISK_GIB} GiB < ${MIN_DISK_GIB} GiB"
fi

if command -v python3 >/dev/null 2>&1; then
    STEAL_PERCENT="$(python3 - <<'PY'
import time

def sample():
    values = [int(value) for value in open('/proc/stat').readline().split()[1:]]
    return sum(values), values[7] if len(values) > 7 else 0

total0, steal0 = sample()
time.sleep(5)
total1, steal1 = sample()
delta = max(1, total1 - total0)
print(f"{100.0 * (steal1 - steal0) / delta:.2f}")
PY
)"
    info "CPU steal over 5 seconds: ${STEAL_PERCENT}%"
    if awk "BEGIN {exit !(${STEAL_PERCENT} >= ${MAX_STEAL_FAIL_PERCENT})}"; then
        fail "CPU steal is at or above ${MAX_STEAL_FAIL_PERCENT}% (severe oversubscription)"
    elif awk "BEGIN {exit !(${STEAL_PERCENT} >= ${MAX_STEAL_WARN_PERCENT})}"; then
        warn "CPU steal is at or above ${MAX_STEAL_WARN_PERCENT}%"
    else
        pass "CPU steal is below ${MAX_STEAL_WARN_PERCENT}%"
    fi
else
    warn "python3 unavailable; CPU steal sampling skipped"
fi
echo

echo "[3] NVIDIA GPU identity and capacity"
if ! command -v nvidia-smi >/dev/null 2>&1; then
    fail "nvidia-smi is unavailable"
else
    GPU_ROWS="$(nvidia-smi --query-gpu=index,name,uuid,memory.total,driver_version --format=csv,noheader,nounits 2>/dev/null || true)"
    if [ -z "$GPU_ROWS" ]; then
        fail "nvidia-smi returned no GPU"
    else
        printf '%s\n' "$GPU_ROWS" | sed 's/^/  [GPU] /'
        GPU_COUNT="$(printf '%s\n' "$GPU_ROWS" | wc -l | xargs)"
        if [ "$GPU_COUNT" -eq 1 ]; then
            pass "exactly one GPU is visible"
        else
            warn "${GPU_COUNT} GPUs are visible; verify the rental is not advertised as one 48 GiB card backed by multiple devices"
        fi
        LOW_MEMORY=0
        while IFS=',' read -r _index _name _uuid memory _driver; do
            memory="$(printf '%s' "$memory" | xargs)"
            if [ "${memory:-0}" -lt "$MIN_GPU_MEMORY_MIB" ]; then
                LOW_MEMORY=1
            fi
        done <<< "$GPU_ROWS"
        if [ "$LOW_MEMORY" -eq 0 ]; then
            pass "all visible GPUs meet ${MIN_GPU_MEMORY_MIB} MiB minimum"
        else
            fail "one or more GPUs are below ${MIN_GPU_MEMORY_MIB} MiB"
        fi
    fi
fi
echo

if [ "$RUN_DOCKER" -eq 1 ]; then
    echo "[4] Docker daemon, GPU, bind mount, and ${DOCKER_SHM_SIZE} shared memory"
    if ! command -v docker >/dev/null 2>&1; then
        fail "docker is unavailable"
    elif ! docker info >/dev/null 2>&1; then
        fail "Docker daemon is unavailable to this user"
    else
        pass "Docker daemon is available"
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet docker; then
            pass "Docker daemon is managed inside this host/VM"
        else
            warn "Docker works but local docker.service is not active; check for a mounted host Docker socket"
        fi

        PROBE_DIR="$(mktemp -d)"
        trap 'rm -rf "$PROBE_DIR"' EXIT
        printf 'host-ok\n' > "${PROBE_DIR}/host.txt"
        if docker run --rm --gpus all --shm-size="${DOCKER_SHM_SIZE}" \
            -e "MIN_DOCKER_SHM_MIB=${MIN_DOCKER_SHM_MIB}" \
            -v "${PROBE_DIR}:/probe" \
            "$CUDA_TEST_IMAGE" bash -lc '
                set -e
                nvidia-smi >/dev/null
                test "$(cat /probe/host.txt)" = host-ok
                shm_mib=$(df -Pm /dev/shm | awk "NR == 2 {print \$2}")
                test "$shm_mib" -ge "${MIN_DOCKER_SHM_MIB}"
                echo container-ok > /probe/result.txt
            '
        then
            if [ "$(cat "${PROBE_DIR}/result.txt" 2>/dev/null || true)" = "container-ok" ]; then
                pass "Docker GPU, bind mount, and ${DOCKER_SHM_SIZE} /dev/shm probe"
            else
                fail "Docker bind mount did not persist the probe result"
            fi
        else
            fail "Docker GPU/bind-mount/shared-memory probe failed"
        fi
        rm -rf "$PROBE_DIR"
        trap - EXIT
    fi
    echo
fi

if [ "$ALLOCATE_GIB" != "0" ]; then
    echo "[5] Real CUDA memory allocation"
    export ALLOCATE_GIB
    TORCH_CODE='import os, torch; gib=int(os.environ["ALLOCATE_GIB"]); assert torch.cuda.device_count()==1; free,total=torch.cuda.mem_get_info(); print("GPU:",torch.cuda.get_device_name()); print("Total GiB:",total/1024**3); x=torch.empty(gib*1024**3,dtype=torch.uint8,device="cuda"); x[::4096]=1; torch.cuda.synchronize(); print(f"{gib} GiB allocation passed")'
    if [ -n "$PYTORCH_TEST_IMAGE" ]; then
        if [ "$RUN_DOCKER" -ne 1 ]; then
            fail "--allocate-gib with PYTORCH_TEST_IMAGE also requires --docker"
        elif docker run --rm --gpus all -e ALLOCATE_GIB \
            "$PYTORCH_TEST_IMAGE" python -c "$TORCH_CODE"; then
            pass "allocated and touched ${ALLOCATE_GIB} GiB inside Docker"
        else
            fail "could not allocate ${ALLOCATE_GIB} GiB inside Docker"
        fi
    elif python3 -c 'import torch' >/dev/null 2>&1 && python3 -c "$TORCH_CODE"; then
        pass "allocated and touched ${ALLOCATE_GIB} GiB on host"
    else
        fail "PyTorch is unavailable or ${ALLOCATE_GIB} GiB allocation failed; set PYTORCH_TEST_IMAGE"
    fi
    echo
fi

echo "=========================================="
echo "Classification"
echo "=========================================="
if [ "${#CONTAINER_SIGNALS[@]}" -gt 0 ]; then
    echo "REJECT: container/Pod evidence was detected."
elif [ "$FAIL" -gt 0 ]; then
    echo "REJECT: no Pod marker was proven, but one or more host requirements failed."
elif [ -n "$VM_VIRT" ] && [ "$VM_VIRT" != "none" ]; then
    echo "ACCEPTABLE: full VM candidate; review warnings and require Docker tests before renting."
else
    echo "ACCEPTABLE: bare-metal candidate; review warnings and require Docker tests before renting."
fi
echo "Summary: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"

[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Install digest-pinned NuRec gRPC images and patch CARLA 0.9.16 integration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env_config.sh
source "${SCRIPT_DIR}/env_config.sh"

retry() {
    local attempt=1
    local max_attempts="${NETWORK_RETRIES:-5}"
    while ! "$@"; do
        if (( attempt >= max_attempts )); then
            return 1
        fi
        echo "[WARN] Attempt ${attempt}/${max_attempts} failed: $*" >&2
        sleep "$((attempt * 2))"
        attempt=$((attempt + 1))
    done
}

image_has_digest() {
    local image="$1"
    local digest="$2"
    local image_id repo_digests
    image_id="$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)"
    repo_digests="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image" 2>/dev/null || true)"
    [[ "$image_id" == "$digest" ]] || grep -Fq "@${digest}" <<< "$repo_digests"
}

verify_and_tag() {
    local source_image="$1"
    local target_image="$2"
    local digest="$3"
    if ! image_has_digest "$source_image" "$digest"; then
        echo "[ERROR] Digest mismatch for ${source_image}; expected ${digest}." >&2
        return 1
    fi
    docker tag "$source_image" "$target_image"
    image_has_digest "$target_image" "$digest"
}

ensure_ngc_image() {
    local target="$1"
    local mirror="$2"
    local digest="$3"
    if image_has_digest "$target" "$digest"; then
        echo "[OK] Reusing verified NGC image: ${target}"
        return
    fi
    if [[ -n "$mirror" ]]; then
        echo "[INFO] Pulling configured private domestic mirror: ${mirror}"
        retry docker pull "$mirror"
        verify_and_tag "$mirror" "$target" "$digest"
        echo "[OK] Private mirror digest matches ${target}."
        return
    fi

    echo "[INFO] Pulling official NVIDIA NGC image: ${target}"
    if ! retry docker pull "${target}@${digest}"; then
        if [[ -z "${NGC_API_KEY:-}" ]]; then
            echo "[ERROR] NGC pull failed. Set NGC_API_KEY or a verified private NUREC_*_MIRROR_IMAGE." >&2
            return 1
        fi
        printf '%s' "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin
        retry docker pull "${target}@${digest}"
    fi
    verify_and_tag "${target}@${digest}" "$target" "$digest"
}

apply_carla_patches() {
    [[ "$NUREC_APPLY_CARLA_PATCHES" == "1" ]] || {
        echo "[INFO] Skipping CARLA patches (NUREC_APPLY_CARLA_PATCHES=${NUREC_APPLY_CARLA_PATCHES})."
        return
    }
    local patch_root="${CLOSED_LOOP_BENCH_ROOT}/tools"
    local nurec_root="${CARLA_ROOT}/PythonAPI/examples/nvidia/nurec"
    local example="${nurec_root}/example_nurec_replay_save_images.py"
    local python_bin="${CONDA_ROOT}/envs/${CONDA_ENV_NAME}/bin/python"
    local -a patch_specs=(
        "patch_carla_nurec_runtime.py:${nurec_root}/nurec_integration.py"
        "patch_carla_nurec_cleanup.py:${nurec_root}/nurec_integration.py"
        "patch_carla_nurec_scenario.py:${nurec_root}/scenario.py"
        "patch_carla_nurec_replay.py:${example}"
        "patch_carla_nurec_server_command.py:${nurec_root}/nurec_render_service.py"
        "patch_carla_nurec_camera_config.py:${example}"
        "patch_carla_nurec_overlap_diagnostics.py:${example}"
        "patch_carla_nurec_actor_inventory.py:${example}"
    )
    [[ -x "$python_bin" ]] || { echo "[ERROR] Python not found: ${python_bin}" >&2; return 1; }
    [[ -d "$nurec_root" ]] || { echo "[ERROR] CARLA NuRec examples not found: ${nurec_root}" >&2; return 1; }
    local spec patch_name target
    for spec in "${patch_specs[@]}"; do
        patch_name="${spec%%:*}"
        target="${spec#*:}"
        [[ -f "${patch_root}/${patch_name}" ]] || {
            echo "[ERROR] Required versioned patch is missing: ${patch_root}/${patch_name}" >&2
            return 1
        }
        "$python_bin" "${patch_root}/${patch_name}" "$target"
    done
    echo "[OK] CARLA NuRec compatibility patches applied idempotently."
}

echo "=========================================="
echo "Stage 6: NuRec gRPC images + CARLA adapter"
echo "=========================================="
command -v docker >/dev/null 2>&1 || { echo "[ERROR] Run stage0_container_runtime.sh first." >&2; exit 1; }
docker info >/dev/null

ensure_ngc_image "$NUREC_MAIN_IMAGE" "$NUREC_MAIN_MIRROR_IMAGE" "$NUREC_MAIN_IMAGE_DIGEST"
ensure_ngc_image "$NUREC_TOOLS_IMAGE" "$NUREC_TOOLS_MIRROR_IMAGE" "$NUREC_TOOLS_IMAGE_DIGEST"

echo "[INFO] Verifying NuRec GPU access..."
docker run --rm --gpus all --shm-size="$NUREC_SHM_SIZE" --entrypoint nvidia-smi \
    "$NUREC_MAIN_IMAGE" --query-gpu=name,driver_version --format=csv,noheader

apply_carla_patches
echo "Stage 6 completed."

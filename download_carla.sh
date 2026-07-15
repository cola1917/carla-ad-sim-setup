#!/usr/bin/env bash
# Download the official CARLA 0.9.16 Ubuntu archive with resume and validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env_config.sh
source "${SCRIPT_DIR}/env_config.sh"

CARLA_DOWNLOAD_URL="${CARLA_DOWNLOAD_URL:-https://tiny.carla.org/carla-0-9-16-linux}"
FORCE=0

usage() {
    cat <<EOF
Usage: bash download_carla.sh [--force] [--url URL]

Downloads the official CARLA ${CARLA_VERSION} Ubuntu archive to:
  ${CARLA_TAR_FILE}

Options:
  --force    Replace an existing final archive and restart partial download.
  --url URL  Override the official release URL.
  -h         Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        --url)
            [ "$#" -ge 2 ] || { echo "--url requires a value" >&2; exit 2; }
            CARLA_DOWNLOAD_URL="$2"
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

if [ "$CARLA_VERSION" != "0.9.16" ]; then
    echo "[ERROR] This downloader is frozen to CARLA 0.9.16; CARLA_VERSION=${CARLA_VERSION}" >&2
    exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is required. Install it with: sudo apt-get install -y curl" >&2
    exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
    echo "[ERROR] tar is required." >&2
    exit 1
fi

mkdir -p "$(dirname "$CARLA_TAR_FILE")"
PART_FILE="${CARLA_TAR_FILE}.part"
CHECKSUM_FILE="${CARLA_TAR_FILE}.sha256"

if [ "$FORCE" -eq 1 ]; then
    rm -f "$CARLA_TAR_FILE" "$PART_FILE" "$CHECKSUM_FILE"
fi

if [ -f "$CARLA_TAR_FILE" ]; then
    echo "[INFO] Existing archive found; validating: ${CARLA_TAR_FILE}"
    if tar -tzf "$CARLA_TAR_FILE" >/dev/null; then
        sha256sum "$CARLA_TAR_FILE" | tee "$CHECKSUM_FILE"
        echo "[OK] Existing CARLA archive is readable; download skipped."
        exit 0
    fi
    echo "[ERROR] Existing archive is invalid. Re-run with --force." >&2
    exit 1
fi

echo "[INFO] Official CARLA release page: https://github.com/carla-simulator/carla/releases/tag/0.9.16"
echo "[INFO] Download URL: ${CARLA_DOWNLOAD_URL}"
echo "[INFO] Destination: ${CARLA_TAR_FILE}"
echo "[INFO] Partial downloads resume from: ${PART_FILE}"

curl \
    --fail \
    --location \
    --retry 10 \
    --retry-delay 5 \
    --retry-all-errors \
    --continue-at - \
    --output "$PART_FILE" \
    "$CARLA_DOWNLOAD_URL"

echo "[INFO] Validating gzip/tar structure..."
if ! tar -tzf "$PART_FILE" >/dev/null; then
    echo "[ERROR] Downloaded file is not a readable CARLA tar.gz archive: ${PART_FILE}" >&2
    exit 1
fi

mv "$PART_FILE" "$CARLA_TAR_FILE"
sha256sum "$CARLA_TAR_FILE" | tee "$CHECKSUM_FILE"
echo "[OK] CARLA ${CARLA_VERSION} downloaded and validated: ${CARLA_TAR_FILE}"

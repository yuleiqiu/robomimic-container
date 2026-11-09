#!/bin/bash
set -euo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-robomimic}"
CLEAN_WORKDIR=false
CONTAINER_ARGS=()

# Optional shared data disk. Bind it only when it is actually mounted and the
# per-user directory exists, so a missing disk does not break container
# creation.
SHARED_DISK_MOUNT="${SHARED_DISK_MOUNT:-/mnt/shared_disk}"
SHARED_DISK_DIR="${SHARED_DISK_DIR:-${SHARED_DISK_MOUNT}/yulei}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean)
            CLEAN_WORKDIR=true
            ;;
        --)
            shift
            CONTAINER_ARGS+=("$@")
            break
            ;;
        *)
            CONTAINER_ARGS+=("$1")
            ;;
    esac
    shift
done

mkdir -p home workdir/tmp workdir/var_tmp

if [ "${CLEAN_WORKDIR}" = true ]; then
    find workdir/tmp workdir/var_tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

SINGULARITY_NV_FLAG=""
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    SINGULARITY_NV_FLAG="--nv"
elif command -v lspci >/dev/null 2>&1 && lspci | grep -i nvidia >/dev/null; then
    SINGULARITY_NV_FLAG="--nv"
fi

GITCONFIG_BIND=""
if [ -f "${HOME}/.gitconfig" ]; then
    GITCONFIG_BIND="--bind=${HOME}/.gitconfig"
fi

SSH_BIND=""
if [ -d "${HOME}/.ssh" ]; then
    SSH_BIND="--bind=${HOME}/.ssh"
fi

# Share the host Claude Code status line (script + jq), read-only, so the host
# copy is the single source of truth. Each bind is skipped when the host file
# is missing. Singularity creates an empty placeholder under home/ as the
# mount point; with no bind the placeholder just yields an empty status line.
STATUSLINE_BINDS=()
for f in .claude/statusline.sh .local/bin/jq; do
    if [ -f "${HOME}/${f}" ]; then
        STATUSLINE_BINDS+=("--bind=${HOME}/${f}:${HOME}/${f}:ro")
    fi
done

SHARED_DISK_BIND=""
if ! mountpoint -q "${SHARED_DISK_MOUNT}"; then
    echo "WARNING: ${SHARED_DISK_MOUNT} is not mounted; skipping bind of ${SHARED_DISK_DIR}." >&2
elif [ ! -d "${SHARED_DISK_DIR}" ]; then
    echo "WARNING: ${SHARED_DISK_MOUNT} is mounted but ${SHARED_DISK_DIR} does not exist or is not accessible (sharedstorage group?); skipping its bind." >&2
else
    SHARED_DISK_BIND="--bind=${SHARED_DISK_DIR}:${SHARED_DISK_DIR}"
fi

exec singularity run \
    --contain \
    ${SINGULARITY_NV_FLAG} \
    ${GITCONFIG_BIND} \
    ${SSH_BIND} \
    --bind=/etc/hosts \
    --bind=/etc/localtime \
    ${SHARED_DISK_BIND} \
    ${STATUSLINE_BINDS[@]+"${STATUSLINE_BINDS[@]}"} \
    --workdir=workdir \
    --bind=scripts:/scripts \
    --home=home:${HOME} \
    "${SANDBOX_NAME}" \
    "${CONTAINER_ARGS[@]}"

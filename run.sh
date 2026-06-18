#!/bin/bash
set -euo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-robomimic}"
CLEAN_WORKDIR=false
CONTAINER_ARGS=()

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

singularity run \
    --contain \
    ${SINGULARITY_NV_FLAG} \
    ${GITCONFIG_BIND} \
    ${SSH_BIND} \
    --bind=/etc/hosts \
    --bind=/etc/localtime \
    --workdir=workdir \
    --bind=scripts:/scripts \
    --home=home:${HOME} \
    "${SANDBOX_NAME}" \
    "${CONTAINER_ARGS[@]}"

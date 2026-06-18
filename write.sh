#!/bin/bash
set -euo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-robomimic}"

mkdir -p home

GITCONFIG_BIND=""
if [ -f "${HOME}/.gitconfig" ]; then
    GITCONFIG_BIND="--bind=${HOME}/.gitconfig"
fi

SSH_BIND=""
if [ -d "${HOME}/.ssh" ]; then
    SSH_BIND="--bind=${HOME}/.ssh"
fi

singularity shell --fakeroot \
    --writable \
    --home=home:$HOME \
    ${GITCONFIG_BIND} \
    ${SSH_BIND} \
    "${SANDBOX_NAME}"

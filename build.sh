#!/bin/bash
set -euo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-robomimic}"

if [ -e "${SANDBOX_NAME}" ]; then
    echo "Error: ${SANDBOX_NAME} already exists. Remove it before rebuilding." >&2
    echo "For fakeroot sandbox cleanup notes, see AGENTS.md." >&2
    exit 1
fi

singularity build --fakeroot \
    --sandbox \
    "${SANDBOX_NAME}" \
    Singularity

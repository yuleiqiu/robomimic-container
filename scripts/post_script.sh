#!/bin/bash
set -euo pipefail

# Ensure standard mount point paths exist. Singularity skips binds/kernel mounts
# when the target path is missing in a writable sandbox.
mkdir -p /tmp /var/tmp /proc /sys /dev /run
touch /etc/hosts
if [ ! -e /etc/localtime ]; then
    touch /etc/localtime
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config \
    git git-lfs openssh-client ca-certificates \
    curl wget zip unzip \
    python3 python3-pip python3-venv \
    ffmpeg \
    rsync procps psmisc iproute2 mesa-utils gawk \
    libglib2.0-0 libgl1 libegl1 libglvnd0 libglvnd-dev \
    libx11-6 libxext6 libsm6 libxrender1 \
    libgl1-mesa-glx libegl1-mesa \
    freeglut3-dev libglfw3 libglew2.2 libosmesa6 libosmesa6-dev \
    tmux screen less nano vim tree htop \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Keep shell prompt consistent with other container templates.
CUSTOM_ENV=/.singularity.d/env/99-zz_custom_env.sh
cat >"${CUSTOM_ENV}" <<'EOF'
#!/bin/bash
PS1="[robomimic] Singularity> \w \$ "
EOF
chmod 755 "${CUSTOM_ENV}"

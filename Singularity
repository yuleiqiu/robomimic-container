bootstrap: docker
From: nvidia/cuda:12.2.2-base-ubuntu22.04

%labels
    Author Yulei Qiu
    Project robomimic

%environment
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
    export XDG_RUNTIME_DIR=/tmp
    export MUJOCO_GL=egl

%files
    scripts /scripts

%post
    bash /scripts/post_script.sh

%runscript
    if [ "$#" -gt 0 ]; then
        . /scripts/run_script.sh
        exec "$@"
    fi

    exec /bin/bash --rcfile /scripts/run_script.sh -i

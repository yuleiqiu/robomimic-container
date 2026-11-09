#!/bin/bash
# Run long jobs inside the container without opening an interactive shell.
#
# Each job runs `./run.sh -- bash -c "<command>"` in a detached host tmux
# session named job-<name>, so it survives closing the terminal or the agent
# session. Output goes to workdir/jobs/<name>.log, which ends with a line
# "# end <time> EXIT=<code>" once the job stops.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

JOBS_DIR=workdir/jobs
PREFIX=job-

usage() {
    cat <<'EOF'
Usage:
  ./job.sh start <name> '<command>'   start <command> in the container (bash -c, cwd = container $HOME)
  ./job.sh ls                         list jobs: running, or finished with exit code
  ./job.sh log <name> [lines]         show the last lines of the log (default 40)
  ./job.sh follow <name>              follow the log (Ctrl-C stops following, not the job)
  ./job.sh attach <name>              attach to the live tmux session (detach: Ctrl-b d)
  ./job.sh stop <name>                send Ctrl-C (graceful stop; exit code is logged)
  ./job.sh kill <name>                kill the tmux session and everything in it
  ./job.sh gpus                       show GPU memory use and running compute processes

Example:
  ./job.sh start m0_seed1 'cd ~/codes/constraint-il-transfer && CUDA_VISIBLE_DEVICES=0 \
      uv run python third_party/robomimic/robomimic/scripts/train.py --config <config>.json'
EOF
}

check_name() {
    if [[ ! "${1:-}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "job name must match [A-Za-z0-9_.-]+" >&2
        exit 2
    fi
}

running() {
    tmux has-session -t "=${PREFIX}$1" 2>/dev/null
}

action="${1:-}"
[ "$#" -gt 0 ] && shift

case "${action}" in
    start)
        [ "$#" -eq 2 ] || { usage >&2; exit 2; }
        name="$1"
        check_name "${name}"
        if running "${name}"; then
            echo "job ${name} is already running" >&2
            exit 1
        fi
        mkdir -p "${JOBS_DIR}"
        log="${JOBS_DIR}/${name}.log"
        if [ -e "${log}" ]; then
            mv "${log}" "${JOBS_DIR}/${name}.$(date -r "${log}" +%Y%m%d-%H%M%S).log"
        fi
        printf '%s\n' "$2" > "${JOBS_DIR}/${name}.cmd"
        tmux new-session -d -s "${PREFIX}${name}" -c "${PWD}" "bash ${PWD}/job.sh _run ${name}"
        echo "started ${PREFIX}${name}; log: ${PWD}/${log}"
        ;;
    _run)
        # Internal: executed inside the tmux session.
        name="$1"
        log="${JOBS_DIR}/${name}.log"
        command="$(cat "${JOBS_DIR}/${name}.cmd")"
        {
            echo "# job ${name}"
            echo "# start $(date -Is)"
            echo "# cmd ${command}"
        } > "${log}"
        # Ctrl-C reaches the job; this script and tee ignore it so the exit
        # code and the tail of the output are still written.
        trap ':' INT
        set +e
        ./run.sh -- bash -c "${command}" 2>&1 | tee -i -a "${log}"
        rc="${PIPESTATUS[0]}"
        echo "# end $(date -Is) EXIT=${rc}" | tee -a "${log}"
        ;;
    ls)
        shopt -s nullglob
        printf '%-24s %-10s %s\n' NAME STATUS STARTED
        for log in "${JOBS_DIR}"/*.log; do
            name="$(basename "${log}" .log)"
            [ -e "${JOBS_DIR}/${name}.cmd" ] || continue   # skip archived logs
            started="$(sed -n 's/^# start //p' "${log}" | head -n 1)"
            if running "${name}"; then
                status=running
            else
                status="$(sed -n 's/^# end .* \(EXIT=.*\)$/\1/p' "${log}" | tail -n 1)"
                status="${status:-stopped?}"
            fi
            printf '%-24s %-10s %s\n' "${name}" "${status}" "${started}"
        done
        ;;
    log)
        check_name "${1:-}"
        tail -n "${2:-40}" "${JOBS_DIR}/$1.log"
        ;;
    follow)
        check_name "${1:-}"
        tail -n 40 -f "${JOBS_DIR}/$1.log"
        ;;
    attach)
        check_name "${1:-}"
        exec tmux attach -t "=${PREFIX}$1"
        ;;
    stop)
        check_name "${1:-}"
        running "$1" || { echo "job $1 is not running" >&2; exit 1; }
        tmux send-keys -t "=${PREFIX}$1:" C-c
        echo "sent Ctrl-C to ${PREFIX}$1"
        ;;
    kill)
        check_name "${1:-}"
        running "$1" || { echo "job $1 is not running" >&2; exit 1; }
        tmux kill-session -t "=${PREFIX}$1"
        echo "# end $(date -Is) EXIT=killed" >> "${JOBS_DIR}/$1.log"
        echo "killed ${PREFIX}$1"
        ;;
    gpus)
        nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
        nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv
        ;;
    *)
        usage
        [ -z "${action}" ] || [ "${action}" = -h ] || [ "${action}" = --help ] || exit 2
        ;;
esac

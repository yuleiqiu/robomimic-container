# robomimic Singularity Container

This repository contains a Singularity sandbox recipe and wrapper scripts for GPU-based robomimic / robosuite / MuJoCo experiments.

It is a container workspace, not the robomimic source repository. Keep robomimic checkouts, Python environments, caches, logs, and experiment outputs in the persistent runtime home or in external bind mounts.

## Host Target

- Base image: `nvidia/cuda:12.2.2-base-ubuntu22.04`
- CUDA compatibility target: 12.2
- Known-good host driver family: NVIDIA 535
- Runtime rendering default: `MUJOCO_GL=egl` for headless MuJoCo use

The wrapper script enables Singularity `--nv` automatically when host NVIDIA tools are available. On SSH/headless machines, `glxinfo` or `glxgears` may fail with `unable to open display`; that is expected and does not by itself indicate CUDA or EGL failure.

## Repository Contents

- `Singularity`: container definition.
- `build.sh`: builds the writable sandbox.
- `run.sh`: starts the sandbox for normal use.
- `write.sh`: opens a writable fakeroot shell for system-level changes.
- `job.sh`: host-side helper that runs long jobs inside the container in detached tmux sessions, with logs.
- `scripts/post_script.sh`: build-time package provisioning.
- `scripts/run_script.sh`: runtime shell bootstrap.
- `workdir/.gitkeep`: keeps the runtime workdir placeholder in Git.

Generated runtime state is intentionally ignored:

- `robomimic/`: built sandbox image directory.
- `home/`: persistent container home, including uv/codex/opencode state, shell history, source checkouts, caches, and secrets.
- `workdir/tmp` and `workdir/var_tmp`: contained temporary directories.

## Build

```bash
./build.sh
```

By default this creates a writable sandbox named `robomimic/`.

To use a different sandbox directory:

```bash
SANDBOX_NAME=myproject ./build.sh
```

## Run

```bash
./run.sh
```

Run a command directly inside the container:

```bash
./run.sh nvidia-smi
./run.sh python3 --version
```

Clean only the contained temporary directories before starting:

```bash
./run.sh --clean
```

Runtime state is kept in:

- `home/`: mapped as the container home.
- `workdir/`: used by Singularity `--workdir` for contained temporary paths.

## Long-Running Jobs From the Host

Day-to-day work happens inside the container (`./run.sh`); there, long jobs can use the container's `tmux`/`screen` or `nohup`. `job.sh` is for the host side, mainly container maintenance: it starts a command inside the container (through `run.sh`) in a detached host tmux session named `job-<name>`. The job keeps running after the terminal or an agent session closes, and its output goes to `workdir/jobs/<name>.log`.

```bash
./job.sh gpus                      # GPU memory use and running processes
./job.sh start m0_seed1 'cd ~/codes/constraint-il-transfer && CUDA_VISIBLE_DEVICES=0 \
    uv run python third_party/robomimic/robomimic/scripts/train.py --config <config>.json'
./job.sh ls                        # running, or finished with EXIT=<code>
./job.sh log m0_seed1              # last 40 lines
./job.sh follow m0_seed1           # live log; Ctrl-C stops following only
./job.sh attach m0_seed1           # live terminal; detach with Ctrl-b d
./job.sh stop m0_seed1             # send Ctrl-C to the job
./job.sh kill m0_seed1             # kill the session
```

The command runs with `bash -c` from the container home, so paths inside it are container paths (`~/codes/...`).

## Shared Data Disk

`run.sh` bind-mounts the host shared disk directory into the container at the same path. The bind is optional: if the disk is not mounted, or the per-user directory is missing or not accessible, `run.sh` prints a warning and starts the container without it instead of failing.

The mount point must be a real mount (`mountpoint -q /mnt/shared_disk`), so an empty directory left behind at that path is never bound into the container by mistake.

The host mounts the disk (exFAT, USB) through systemd automount (`/etc/fstab` line with `x-systemd.automount`): it mounts on first access, also after the disk is replugged, so no `sudo` is needed. Access is limited to the `sharedstorage` group (`uid=0,gid=1006,umask=007`); group members can read and write the whole disk, everyone else is denied. To give someone access, an admin runs `sudo usermod -aG sharedstorage <user>`; the user must log out and back in (and restart any tmux server) before the new group applies. If the disk is unplugged, the first access waits up to 10 s (`x-systemd.device-timeout=10s`) before `run.sh` warns and continues.

Defaults and overrides:

- Mount point: `/mnt/shared_disk` (`SHARED_DISK_MOUNT`).
- Bound directory: `/mnt/shared_disk/yulei` (`SHARED_DISK_DIR`).

```bash
SHARED_DISK_DIR=/mnt/shared_disk/someuser ./run.sh
```

Check the disk before a long run if the experiment reads datasets or writes outputs there (listing the directory triggers the automount):

```bash
ls /mnt/shared_disk/yulei >/dev/null && findmnt -t fuseblk /mnt/shared_disk
```

## User Environment

Create user-level tools and Python environments inside the container home, not in the sandbox, unless they are true system dependencies.

Examples:

```bash
touch ~/.bashrc
curl -LsSf https://astral.sh/uv/install.sh | sh
```

If `uv` asks for `~/.local/bin` on `PATH`, add it to `~/.bashrc`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Install robomimic source and Python dependencies under `~/codes` or another user-owned location:

```bash
mkdir -p ~/codes
cd ~/codes
git clone https://github.com/ARISE-Initiative/robomimic.git
cd robomimic
```

Choose the Python environment manager and package versions appropriate for the experiment. A minimal uv-based layout would be:

```bash
uv venv --python 3.10
uv pip install -e .
```

After installing PyTorch, verify CUDA from inside the active environment:

```bash
python -c "import torch; print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"
```

## Writable Shell

Use this only when system-level changes are needed:

```bash
./write.sh
```

Prefer editing `Singularity` or `scripts/post_script.sh` and rebuilding over accumulating manual sandbox changes.

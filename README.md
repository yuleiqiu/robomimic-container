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

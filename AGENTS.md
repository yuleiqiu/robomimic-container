# AGENTS.md

This repository defines a Singularity container template for GPU-based robotics and imitation-learning experiments. It is currently instantiated as a robomimic container, but the scripts are intentionally project-name configurable through `SANDBOX_NAME`.

Treat this repository as a container recipe and runtime workspace, not as the robomimic source repository itself.

## Repository Layout

- `Singularity`: container definition. It starts from `nvidia/cuda:12.2.2-base-ubuntu22.04`, installs system dependencies in `%post`, copies `scripts/` into `/scripts`, and starts bash with `/scripts/run_script.sh`.
- `build.sh`: builds a writable Singularity sandbox. Default name: `robomimic/`.
- `run.sh`: runs the sandbox in contained mode for normal experiments. Default name: `robomimic/`.
- `write.sh`: opens the sandbox in writable fakeroot mode for system-level changes. Default name: `robomimic/`.
- `job.sh`: host-side helper that runs long jobs inside the container through `run.sh` in detached host tmux sessions, with logs in `workdir/jobs/`. For host-side maintenance; see "Agent Workflow".
- `scripts/post_script.sh`: build-time provisioning script. It creates standard Singularity mount targets, installs apt packages, and writes image-level prompt setup.
- `scripts/run_script.sh`: runtime shell bootstrap. It sources `~/.bashrc` if present; user-level uv initialization should live there.
- `workdir/`: runtime work directory used by `--workdir=workdir`; with `--contain`, Singularity maps container temporary locations such as `/tmp` and `/var/tmp` into this area.
- `robomimic/`: generated sandbox image directory. It is build output and may be deleted/rebuilt.
- `home/`: generated/persistent container home. It may contain uv envs, source checkouts, caches, W&B state, experiment outputs, and secrets. Inspect before deleting.

## Version Control Boundaries

Commit the container recipe and wrapper files:

- `Singularity`
- `build.sh`
- `run.sh`
- `write.sh`
- `job.sh`
- `scripts/post_script.sh`
- `scripts/run_script.sh`
- `README.md`
- `AGENTS.md`
- `.gitignore`
- `workdir/.gitkeep`

Do not commit generated or machine-local state:

- `robomimic/`
- `home/`
- `workdir/tmp`
- `workdir/var_tmp`
- `.agents/`
- `.codex/`
- logs, experiment outputs, credentials, shell history, source checkouts, and package caches

## Normal Workflow

Build:

```bash
./build.sh
```

Run experiments:

```bash
./run.sh
```

Make writable system changes:

```bash
./write.sh
```

Use `write.sh` sparingly. Prefer keeping project code, datasets, outputs, and user-level caches outside the sandbox when possible, then bind them in from user-owned directories.

To reuse the template for another project name:

```bash
SANDBOX_NAME=myproject ./build.sh
SANDBOX_NAME=myproject ./run.sh
SANDBOX_NAME=myproject ./write.sh
```

If changing the project name permanently, also update the image-level prompt in `scripts/post_script.sh` and the `Project` label in `Singularity`; `SANDBOX_NAME` only changes the sandbox directory used by the wrapper scripts.

## Agent Workflow

**Default: research agents run inside the container.** Start them from an interactive `./run.sh` shell (typically inside a host tmux window). Project docs, configs and agent memory use container paths (`/home/yulei/codes/<project>`), `uv` environments resolve correctly, and `--contain` limits what the agent can touch. Long jobs started inside the container can use the container's `tmux`/`screen` or `nohup`; background processes outlive the `run.sh` shell (checked 2026-11-09).

**Host-side agents are for container maintenance only:** editing the recipe (`Singularity`, wrapper scripts, `scripts/`), rebuilding or cleaning the sandbox, and machine-level checks such as GPU use across projects. Do not do project research work from the host: agent memory and history are keyed by path, so host sessions do not see the in-container memory.

When a host-side maintenance agent needs to run something in the container, it does so without an interactive shell. Verified 2026-11-09 (CUDA, MuJoCo EGL, uv project env, tectonic; job start, finish, failure, Ctrl-C stop and kill).

- **Paths.** Host `home/<path>` is container `$HOME/<path>`; for example host `home/codes/constraint-il-transfer` is `~/codes/constraint-il-transfer` inside the container. Read and edit project files through the host path. Project docs written for in-container use refer to container paths.
- **Run project code only inside the container.** The host also has `uv` on `PATH`, but project `.venv` interpreters are symlinks into the container home (`~/.local/share/uv/python/...`) and dangle on the host. Never run `uv`, project Python or project tools from the host.
- **Short commands** (seconds to minutes): `./run.sh` with arguments runs one command and exits. The runscript sources `~/.bashrc` first, so `uv` and `tectonic` are on `PATH`:

  ```bash
  ./run.sh -- bash -c 'cd ~/codes/<project> && uv run python <script.py> ...'
  ```

- **Long jobs** (e.g. a verification run during maintenance): use `job.sh`. Each job runs in a detached tmux session `job-<name>` on the host tmux server, so it survives closing the agent session or the terminal.

  ```bash
  ./job.sh gpus                                   # check before launching; the machine is shared
  ./job.sh start <name> 'cd ~/codes/<project> && CUDA_VISIBLE_DEVICES=0 MUJOCO_GL=egl uv run python ...'
  ./job.sh ls                                     # running, or EXIT=<code> / EXIT=killed
  ./job.sh log <name> [lines]                     # tail of workdir/jobs/<name>.log
  ./job.sh stop <name>                            # Ctrl-C: the job receives SIGINT; exit code is logged
  ./job.sh kill <name>                            # last resort: kills the tmux session
  ```

  The user can watch a job live with `./job.sh attach <name>` (detach with `Ctrl-b d`) or `./job.sh follow <name>`. Starting a name again archives the previous log as `<name>.<time>.log`.
- **Environment.** `run.sh` does not use `--cleanenv`, so host environment variables, including the agent's own session variables, reach container processes. Set experiment variables such as `CUDA_VISIBLE_DEVICES` and `MUJOCO_GL` explicitly in the command.
- **Temporary files.** Container `/tmp` is host `workdir/tmp/`. Job logs live in `workdir/jobs/`, which `./run.sh --clean` does not remove.
- **Root-level changes** (`write.sh`, fakeroot) stay with the user.

## Runtime Binds

`run.sh` currently uses:

- `--contain`: isolates the container from most host paths.
- `${SINGULARITY_NV_FLAG}`: adds `--nv` when host `nvidia-smi -L` succeeds, with `lspci` detection as a fallback.
- optional host `${HOME}/.gitconfig`: convenient for git identity/config.
- optional host `${HOME}/.ssh`: convenient for private git access, but sensitive.
- `--bind=/etc/hosts`: preserves host name resolution details.
- `--bind=/etc/localtime`: keeps logs and timestamps aligned with the host.
- optional host `/mnt/shared_disk/yulei` (`SHARED_DISK_DIR`, mount point `SHARED_DISK_MOUNT`): shared data disk. Bound only when the disk is actually mounted and the directory exists and is accessible; otherwise `run.sh` prints a warning and starts without it. The host automounts it via systemd (`x-systemd.automount` in `/etc/fstab`), and only the `sharedstorage` group can access it (`uid=0,gid=1006,umask=007`; set up 2026-11-09). Changing the mount or group membership needs sudo and stays with the user.
- `--workdir=workdir`: gives contained runtime directories a host-backed location.
- `--bind=scripts:/scripts`: makes runtime use the current repository copy of `scripts/run_script.sh` without rebuilding.
- `--home=home:${HOME}`: maps repository-local `home/` as the container home.

Do not re-add `--bind=/dev` by default. This container is used for simulation training, not real camera/robot hardware. `--nv` should expose the GPU pieces needed for training.

SSH/headless environments commonly fail GLX display tests such as `glxinfo` and `glxgears` with `unable to open display`. That is not a CUDA failure. Prefer checking `nvidia-smi`, PyTorch CUDA availability, and MuJoCo EGL behavior for this container.

## Temporary Files

`run.sh` preserves `workdir` by default because repeated experiments may benefit from temporary caches.

Clean temporary runtime directories explicitly:

```bash
./run.sh --clean
```

The clean path only removes immediate contents under `workdir/tmp` and `workdir/var_tmp`.

## Clean Rebuild

A clean rebuild normally means removing generated runtime state:

```bash
rm -rf workdir
rm -rf home
rm -rf robomimic
./build.sh
mkdir -p home workdir
```

Before deleting `home/`, inspect it carefully. It may contain:

- `home/.local/share/uv`
- `home/.cache`
- source checkouts such as `home/codes/robomimic`
- W&B logs
- experiment outputs
- credentials or API keys in shell/config files

`home/` is usually owned by the normal user and can generally be deleted without fakeroot. Verify with:

```bash
find home ! -user "$(id -u)" -print
find home -type d \( ! -readable -o ! -writable -o ! -executable \) -print
```

If both commands print nothing, ordinary `rm -rf home` should work.

## Fakeroot Sandbox Cleanup

The generated sandbox can contain directories owned by mapped users such as `nobody:yulei` or `nobody:nogroup`. This is a normal side effect of `singularity build --fakeroot --sandbox`: container-internal users like `root`, `_apt`, or systemd users are mapped onto host filesystem ownership.

Problematic examples seen in earlier sandbox builds:

```text
robomimic/var/cache/apt/archives/partial
robomimic/var/lib/apt/lists/partial
robomimic/var/lib/apt/lists/auxfiles
robomimic/run/systemd/netif
```

The apt `partial` directories may be especially annoying because they can be `700` and owned by `nobody`, so the normal user cannot enter them. In that case, host-side `rm -rf robomimic` may fail.

First test whether fakeroot works in the user's actual shell:

```bash
singularity exec --fakeroot --writable robomimic id
```

If it prints `uid=0(root) gid=0(root)`, use fakeroot to remove or relax the known troublesome paths inside the sandbox:

```bash
singularity exec --fakeroot --writable robomimic rm -rf \
  /var/lib/apt/lists/partial \
  /var/cache/apt/archives/partial \
  /run/systemd/netif
```

Then delete the sandbox from the host:

```bash
rm -rf robomimic
```

If deletion still fails, relax permissions from inside fakeroot:

```bash
singularity exec --fakeroot --writable robomimic chmod -R u+rwX \
  /var/lib/apt/lists \
  /var/cache/apt/archives \
  /run/systemd
```

Then retry:

```bash
rm -rf robomimic
```

If `singularity exec --fakeroot --writable robomimic id` fails with an error about `/usr/bin/newuidmap`, the current execution environment cannot start fakeroot. In that case:

- Ask the user to run the fakeroot cleanup from their normal login shell.
- Do not assume sudo is available.
- Do not try destructive workarounds.
- As a temporary workaround, rename the sandbox to free the expected build path, but note that this does not reclaim disk space:

```bash
mv robomimic robomimic.broken
```

## Agent Safety Notes

- Do not delete `home/`, `robomimic/`, `workdir/`, datasets, or experiment outputs unless the user explicitly asks.
- Do not use `sudo` unless the user explicitly requests it and confirms they have access.
- Prefer `rg`/`find`/`du` inspections before changing cleanup behavior.
- Use `apply_patch` for repository edits.
- Run `bash -n` after editing shell scripts.
- Keep secrets out of committed files and long-lived templates. If an API key appears in `home/.bashrc` or similar runtime state, point it out and recommend rotating/removing it.

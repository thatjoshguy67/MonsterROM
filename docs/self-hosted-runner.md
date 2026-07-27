# Self-hosted runner setup (Windows + WSL2)

The `build` job in `.github/workflows/ci.yml` runs on a self-hosted runner so
that downloaded firmware survives between runs. GitHub-hosted runners are
wiped after every job, which means re-downloading ~15 GB per target (about an
hour) before every build attempt. With a self-hosted runner the build system's
`.downloaded` / `.extracted` markers make repeat runs skip straight to the
ROM build.

The job still reports to GitHub exactly like a hosted one: live logs, step
status and artifacts all appear in the Actions tab.

## 1. Requirements

- Windows 10/11 with WSL2 and Ubuntu 24.04
- ~200 GB free disk (two firmwares per target, extracted images, work dir)
- The repo **must not** be public while a self-hosted runner is enabled for
  it, unless you are certain no untrusted workflow can reach the runner.
  `pull_request` has been removed as a trigger for this reason.

## 2. Install Ubuntu 24.04

```powershell
wsl --install -d Ubuntu-24.04
```

## 3. Install build dependencies (once)

The workflow no longer installs packages per run, so do it here:

```bash
sudo apt update && sudo apt install -y \
  attr bc brotli ccache clang cmake cpio curl ffmpeg file git jq lz4 lld make \
  openjdk-17-jdk p7zip-full protobuf-compiler python3 python3-venv rsync \
  vim-common webp zip unzip zstd \
  libbrotli-dev libbz2-dev libgtest-dev libprotobuf-dev libunwind-dev \
  libpcre2-dev libzstd-dev
```

## 4. Check the kernel can mount EROFS and F2FS

`scripts/extract_fw.sh` mounts the stock images read-only, so the WSL kernel
needs both filesystems:

```bash
sudo modprobe erofs f2fs && echo OK
```

If this fails, build a WSL2 kernel with `CONFIG_EROFS_FS=y` and
`CONFIG_F2FS_FS=y` from https://github.com/microsoft/WSL2-Linux-Kernel and
point `%UserProfile%\.wslconfig` at it:

```ini
[wsl2]
kernel=C:\\Users\\<you>\\wsl-kernel\\bzImage
```

## 5. Allow passwordless sudo for the runner user

The build calls `sudo mount`. A runner running as a service has no terminal,
so a password prompt would hang the job until it times out.

```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/unica-runner
sudo chmod 0440 /etc/sudoers.d/unica-runner
```

## 6. Register the runner

In the repo: **Settings -> Actions -> Runners -> New self-hosted runner**,
pick **Linux / x64**. GitHub shows a registration token valid for one hour;
copy the commands from that page, which look like:

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/<version>/<file>.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
./config.sh --url https://github.com/<owner>/<repo> --token <TOKEN>
```

Accept the defaults, but keep the labels `self-hosted,linux,x64` - the
workflow's `runs-on` matches on them.

Clone the work dir on a Linux filesystem (the default `~/actions-runner/_work`
is fine). Never place it under `/mnt/c`: Windows drives cannot store Linux
ownership or extended attributes, which the fs_config/file_context generation
depends on.

## 7. Run it

Foreground, for a first test:

```bash
cd ~/actions-runner && ./run.sh
```

As a service, so it starts with WSL - first enable systemd by adding this to
`/etc/wsl.conf` and running `wsl --shutdown` from Windows:

```ini
[boot]
systemd=true
```

then:

```bash
cd ~/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
```

The runner must be online for jobs to start; while the PC is off or asleep
they simply queue.

## 8. Trigger a build

Actions -> CI -> **Run workflow**, or push to `seventeen`. The first run still
downloads firmware; later runs reuse it and go straight to the ROM build.

## Notes

- `shellcheck` and `generate-matrix` still run on GitHub-hosted runners: they
  are quick and need no local state.
- To free space, delete `out/target/<codename>` but keep `out/odin` and
  `out/fw` - those hold the cached firmware.
- To go back to GitHub-hosted builds, set `runs-on: ubuntu-24.04`, drop
  `clean: false`, and restore the disk-cleanup and apt steps from git history.

# msl — macOS Subsystem for Linux

Run Arch Linux ARM on macOS using Apple's [Virtualization.framework](https://developer.apple.com/documentation/virtualization).

## Install

```bash
brew tap xt9y/msl
brew install msl
```

## Setup

Download the Arch Linux ARM image (~1GB) and configure VM resources:

```bash
msl --setup
# with custom resources:
msl --setup --disk-size 16 --ram-size 4 --cpu-cores 4
# or using short flags:
msl --setup -ds 16 -rs 4 -cc 4
```

| Flag | Short | Default | Description |
|---|---|---|---|
| `--disk-size` | `-ds` | 8 | Disk image size in GB |
| `--ram-size` | `-rs` | 2 | RAM size in GB |
| `--cpu-cores` | `-cc` | 2 | Number of vCPUs |

Configuration is stored in `~/.msl/config.json` and used by `--start`.

## Usage

```bash
msl --start       # boot the VM (auto-setup if needed)
msl --shell       # interactive shell
msl --exec "cmd"  # run a command
msl --upgrade     # update all guest packages (pacman -Syu)
msl --stop        # stop the VM
msl --status      # check if running
msl --uninstall   # remove all msl data (~/.msl)
msl --version     # show version
msl --help        # show help
```

## Directory sharing

The host `/Users` directory is available inside the VM via virtiofs:

```bash
msl --exec "mount -t virtiofs MacShare /mnt"
```

## GUI applications

`msl --setup` installs and configures [XQuartz](https://www.xquartz.org) automatically. The guest daemon probes the VM's gateway IP and sets `DISPLAY` accordingly. A socat TCP bridge (port 6000 → `/tmp/.X11-unix/X0`) is started automatically and health-checked every 30 seconds while the daemon runs.

```bash
msl --exec "pacman -S --noconfirm xorg-xeyes"
msl --exec xeyes
```

## Security

- **Downloads**: All rootfs and kernel downloads use HTTPS with retry and resume support.
- **VSOCK auth**: A 32-byte random token is generated at setup and written to both the host (`~/.msl/token`) and the guest (`/etc/msld-token`). Every VSOCK connection is authenticated before the mode byte is accepted.
- **Root access**: The guest root account is passwordless by design — the VM is accessible only via VSOCK (host-only, not network-routable). Set a password if you enable SSH.
- **PID locking**: The daemon uses `flock`-based atomic PID writes with stale-PID cleanup and process name verification.
- **Signal handling**: SIGTERM/SIGINT trigger graceful VM shutdown. Shell mode restores terminal settings on exit.
- **Logging**: Errors are written to `/tmp/msl-daemon.log`.

## Build from source

```bash
make
```

Requires: Xcode 15+, Xcode Command Line Tools, and `aarch64-linux-musl-gcc` (for the guest daemon).

### Release

```bash
# Bump MSLVersion in Sources/Setup.swift first!
make release MSG="v1.2.0: description"
```

This builds, verifies version, commits, tags, pushes, and updates the Homebrew tap automatically.

## Uninstall

```bash
msl --uninstall          # removes ~/.msl (disk images, kernel, config)
brew uninstall msl msld  # removes the binaries
brew untap xt9y/msl      # removes the tap
```

## License

MIT
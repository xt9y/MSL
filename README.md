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
msl setup
# with custom resources:
msl setup --disk-size 16 --ram-size 4 --cpu-cores 4
```

| Flag | Default | Description |
|---|---|---|
| `--disk-size` | 8 | Disk image size in GB |
| `--ram-size` | 2 | RAM size in GB |
| `--cpu-cores` | 2 | Number of vCPUs |

Configuration is stored in `~/.msl/config.json`.

## Usage

```bash
msl start        # boot the VM
msl shell        # interactive shell
msl exec "cmd"   # run a command
msl stop         # stop the VM
msl status       # check if running
msl help         # show help
```

## GUI applications

`msl setup` installs [XQuartz](https://www.xquartz.org) automatically for GUI forwarding:

```bash
msl exec "pacman -S --noconfirm xorg-xeyes"
msl exec xeyes
```

## Build from source

```bash
make
```

Requires: Xcode 15+, Xcode Command Line Tools, and `aarch64-linux-musl-gcc` (for the guest daemon).

## Uninstall

```bash
msl uninstall            # removes ~/.msl (disk images, kernel, config)
brew uninstall msl msld  # removes the binaries
brew untap xt9y/msl      # removes the tap
```

## Security

- **Root is passwordless** inside the VM by design. The VM runs exclusively on
  Apple's Virtualization.framework with VSOCK-only access from the host — there
  is no network login, SSH daemon, or remote console. Users who enable SSH
  should set a root password with `msl exec "passwd"`.
- **VSOCK authentication** — every guest connection must present a random 32-byte
  token written to `~/.msl/token` at setup time. The guest daemon (`msld`)
  verifies it with a constant-time comparison to prevent timing side-channels.
- **Concurrent connection limit** — the guest daemon caps forked children at 64
  concurrent connections and reaps them via a `SIGCHLD` handler, preventing
  both zombie accumulation and trivial DoS.
- **Trust model** — `msl setup` downloads the rootfs from `archlinuxarm.org`
  and the kernel from `ports.ubuntu.com`, verifying integrity against the
  checksum published by each origin. This protects against transport
  corruption but not against a compromised origin. Kernel/modules `.deb` files
  are similarly verified against per-file SHA256 checksums when available.

## License

MIT
# msl — macOS Subsystem for Linux

Run Arch Linux ARM on macOS using Apple's [Virtualization.framework](https://developer.apple.com/documentation/virtualization).

## Install

```bash
brew tap xt9y/msl
brew install msl
```

## Setup

Download the Arch Linux ARM image (~1GB):

```bash
msl --setup
```

## Usage

```bash
msl --start       # boot the VM
msl --shell       # interactive shell
msl --exec "cmd"  # run a command
msl --stop        # stop the VM
msl --status      # check if running
msl --version     # show version
```

## Directory sharing

The host `/Users` directory is available inside the VM via virtiofs:

```bash
msl --exec "mount -t virtiofs MacShare /mnt"
```

## GUI applications

`msl --setup` installs and configures [XQuartz](https://www.xquartz.org) automatically. The guest daemon sets `DISPLAY` to the host's X server over the VM's NAT network, so GUI apps launched via `--exec` or `--shell` appear as native windows on your Mac.

```bash
msl --exec "pacman -S --noconfirm xorg-xeyes"
msl --exec xeyes
```

## Build from source

```bash
make
```

Requires: Xcode 15+, Xcode Command Line Tools, and `aarch64-linux-musl-gcc` (for the guest daemon).

## License

MIT

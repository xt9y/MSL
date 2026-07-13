#!/bin/bash
set -euo pipefail

# Build the Arch Linux ARM disk image for msl
# This script creates arch.img and extracts the kernel.
# Run once per release, upload artifacts to GitHub Releases.

OUTPUT_DIR="${1:-.}"
SIZE_MB="${2:-4096}"
ARCH_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"

echo "==> Building msl disk image"
echo "    Output: ${OUTPUT_DIR}/arch.img"
echo "    Size:   ${SIZE_MB}MB"
echo "    Rootfs: ${ARCH_URL}"
echo

# Check for required tools
for cmd in dd curl mkfs.ext4 losetup mount umount; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "error: $cmd not found. Install e2fsprogs and util-linux."
        exit 1
    fi
done

# Create empty disk image
echo "==> Creating ${SIZE_MB}MB disk image..."
dd if=/dev/zero of="${OUTPUT_DIR}/arch.img" bs=1M count="${SIZE_MB}" status=progress

# Format as ext4
echo "==> Formatting as ext4..."
mkfs.ext4 -F -L msl-root "${OUTPUT_DIR}/arch.img"

# Mount the image
echo "==> Mounting image..."
MOUNT_POINT=$(mktemp -d)
sudo mount -o loop "${OUTPUT_DIR}/arch.img" "${MOUNT_POINT}"
trap "sudo umount '${MOUNT_POINT}' 2>/dev/null || true; rm -rf '${MOUNT_POINT}'" EXIT

# Download and extract Arch Linux ARM rootfs
echo "==> Downloading Arch Linux ARM rootfs..."
TARBALL="${OUTPUT_DIR}/archlinuxarm.tar.gz"
if [ ! -f "$TARBALL" ]; then
    curl -L -o "$TARBALL" "$ARCH_URL"
fi

echo "==> Extracting rootfs (this may take a while)..."
sudo bsdtar -xpf "$TARBALL" -C "${MOUNT_POINT}"

# Configure the image
echo "==> Configuring image..."

# Copy kernel and initramfs from the extracted image
echo "==> Extracting kernel..."
cp "${MOUNT_POINT}/boot/Image" "${OUTPUT_DIR}/kernel" 2>/dev/null || {
    echo "warning: kernel not found at /boot/Image, looking for alternatives..."
    find "${MOUNT_POINT}/boot" -name "Image" -o -name "vmlinuz*" | head -1 | while read k; do
        cp "$k" "${OUTPUT_DIR}/kernel"
    done
}

# Set up console on hvc0
echo "==> Enabling serial console..."
sudo sed -i 's/^#Console=.*/Console=hvc0/' "${MOUNT_POINT}/etc/systemd/system.conf" 2>/dev/null || true
sudo mkdir -p "${MOUNT_POINT}/etc/systemd/system/getty.target.wants"
sudo ln -sf /usr/lib/systemd/system/serial-getty@.service \
    "${MOUNT_POINT}/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service" 2>/dev/null || true

# Configure VirtioFS mount
echo "==> Configuring VirtioFS mount..."
sudo mkdir -p "${MOUNT_POINT}/Users"
cat <<'FSTAB' | sudo tee -a "${MOUNT_POINT}/etc/fstab" >/dev/null
MacShare  /Users  virtiofs  rw,noatime  0  0
FSTAB

# Set root password (default: msl)
echo "==> Setting root password..."
echo "root:msl" | sudo chroot "${MOUNT_POINT}" chpasswd 2>/dev/null || true

# Enable network DHCP
echo "==> Enabling network..."
sudo mkdir -p "${MOUNT_POINT}/etc/systemd/network"
cat <<'NETWORK' | sudo tee "${MOUNT_POINT}/etc/systemd/network/20-wired.network" >/dev/null
[Match]
Name=eth0

[Network]
DHCP=ipv4
NETWORK

# Cleanup
echo "==> Cleaning up..."
sudo umount "${MOUNT_POINT}"
rm -rf "${MOUNT_POINT}"

echo
echo "==> Done!"
echo "    Disk:  ${OUTPUT_DIR}/arch.img ($(du -h "${OUTPUT_DIR}/arch.img" | cut -f1))"
if [ -f "${OUTPUT_DIR}/kernel" ]; then
    echo "    Kernel: ${OUTPUT_DIR}/kernel ($(du -h "${OUTPUT_DIR}/kernel" | cut -f1))"
fi
echo
echo "Upload both files to the GitHub release."

#!/usr/bin/env bash
#
# mk-update-rootfs-ko.sh - update an existing rootfs image with the compiled
# kernel modules (.ko).
#
# Usage:
#   ./build.sh update-rootfs-ko
#   ./build.sh mk-update-rootfs-ko.sh
#   ./mk-update-rootfs-ko.sh [SOC] [TARGET]
#
# By default the target image is discovered from .config:
#   RK_CHIP          -> SOC
#   ROOTFS_DESKTOP   -> TARGET (gnome maps to gnome-full, etc.)
#   ROOTFS_TYPE/VER  -> rootfs directory, e.g. ubuntu26.10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RK_SDK_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RK_CONFIG="$RK_SDK_DIR/.config"

die()
{
	echo "error: $*" >&2
	exit 1
}

purple()
{
	printf '\033[35m%s\033[0m\n' "$*"
}

[ -f "$RK_CONFIG" ] && [ -s "$RK_CONFIG" ] || die "SDK config not found: $RK_CONFIG"
# shellcheck disable=SC1090
. "$RK_CONFIG"

ROOTFS_TYPE="${ROOTFS_TYPE:-ubuntu}"
ROOTFS_VERSION="${ROOTFS_VERSION:-}"
ROOTFS_DESKTOP="${ROOTFS_DESKTOP:-}"

[ -n "$ROOTFS_VERSION" ] || die "ROOTFS_VERSION is not set in $RK_CONFIG"
[ -n "$ROOTFS_DESKTOP" ] || die "ROOTFS_DESKTOP is not set in $RK_CONFIG"

SOC="${1:-${SOC:-${RK_CHIP:-}}}"

case "$ROOTFS_DESKTOP" in
	gnome|gnome-full)
		TARGET="${2:-${TARGET:-gnome-full}}"
		;;
	xfce|xfce-full)
		TARGET="${2:-${TARGET:-xfce-full}}"
		;;
	lite)
		TARGET="${2:-${TARGET:-lite}}"
		;;
	*)
		TARGET="${2:-${TARGET:-$ROOTFS_DESKTOP}}"
		;;
esac

[ -n "$SOC" ] || die "SOC/RK_CHIP is not set; pass it as the first argument or set RK_CHIP in .config"
[ -n "$TARGET" ] || die "cannot determine TARGET from ROOTFS_DESKTOP: $ROOTFS_DESKTOP"

ROOTFS_DIR="$RK_SDK_DIR/${ROOTFS_TYPE}${ROOTFS_VERSION}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$ROOTFS_DIR/ubuntu-${SOC}-${TARGET}-rootfs.img}"
KERNEL_MODULES_DIR="${KERNEL_MODULES_DIR:-$RK_SDK_DIR/output/rootfs/lib/modules}"

[ -f "$ROOTFS_IMAGE" ] || die "rootfs image not found: $ROOTFS_IMAGE"
[ -d "$KERNEL_MODULES_DIR" ] || die "kernel modules dir not found: $KERNEL_MODULES_DIR"
[ -n "$(find "$KERNEL_MODULES_DIR" -type f -name '*.ko*' 2>/dev/null | head -n1)" ] || \
	die "no .ko files found under $KERNEL_MODULES_DIR"

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/update-rootfs-ko.XXXXXX")"

cleanup()
{
	sudo umount "$MOUNT_POINT" 2>/dev/null || true
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

purple "==> Updating rootfs image with kernel modules"
purple "    ROOTFS_IMAGE       = $ROOTFS_IMAGE"
purple "    KERNEL_MODULES_DIR = $KERNEL_MODULES_DIR"
purple "    MOUNT_POINT        = $MOUNT_POINT"

purple "==> Mounting rootfs image"
sudo mount -o loop "$ROOTFS_IMAGE" "$MOUNT_POINT"

purple "==> Copying kernel modules"
sudo mkdir -p "$MOUNT_POINT/lib/modules"
sudo cp -rpf "$KERNEL_MODULES_DIR/." "$MOUNT_POINT/lib/modules/"
sudo find "$MOUNT_POINT/lib/modules" -type l \( -name build -o -name source \) -delete
sudo sync

KERNEL_VERSION="$(find "$KERNEL_MODULES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | head -n1)" || true

purple "    Copied from: $KERNEL_MODULES_DIR"
if [ -n "$KERNEL_VERSION" ]; then
	purple "    Copied to:   $MOUNT_POINT/lib/modules/$KERNEL_VERSION  (image path: /lib/modules/$KERNEL_VERSION)"
else
	purple "    Copied to:   $MOUNT_POINT/lib/modules  (image path: /lib/modules)"
fi

purple "==> Unmounting rootfs image"
sudo umount "$MOUNT_POINT"

purple "==> Done: $ROOTFS_IMAGE updated"

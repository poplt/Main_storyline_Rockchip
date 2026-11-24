#!/usr/bin/env bash
#
# mk-upoverlay-rootfs.sh - update an existing rootfs image with the overlay
# files (overlay/, overlay-firmware/, and overlay-debug/ for debug builds).

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

fix_rootfs_mode()
{
	local root="$1" mode="$2" path="$3"
	local target="$path" link i

	for i in 1 2 3 4 5; do
		[ -L "$root$target" ] || break
		link="$(readlink "$root$target" || true)"
		[ -n "$link" ] || break
		case "$link" in
			/*) target="$link" ;;
			*) target="$(dirname "$target")/$link" ;;
		esac
	done

	[ -e "$root$target" ] && sudo chmod "$mode" "$root$target"
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
OVERLAY_DIR="$ROOTFS_DIR/overlay"
OVERLAY_FIRMWARE_DIR="$ROOTFS_DIR/overlay-firmware"
OVERLAY_DEBUG_DIR="$ROOTFS_DIR/overlay-debug"

[ -f "$ROOTFS_IMAGE" ] || die "rootfs image not found: $ROOTFS_IMAGE"
[ -d "$OVERLAY_DIR" ] || die "overlay dir not found: $OVERLAY_DIR"
[ -d "$OVERLAY_FIRMWARE_DIR" ] || die "overlay-firmware dir not found: $OVERLAY_FIRMWARE_DIR"

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/upoverlay-rootfs.XXXXXX")"

cleanup()
{
	sudo umount "$MOUNT_POINT" 2>/dev/null || true
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

purple "==> Updating rootfs image with overlay"
purple "    ROOTFS_IMAGE  = $ROOTFS_IMAGE"
purple "    OVERLAY_DIR   = $OVERLAY_DIR"
purple "    FIRMWARE_DIR  = $OVERLAY_FIRMWARE_DIR"
purple "    MOUNT_POINT   = $MOUNT_POINT"

purple "==> Mounting rootfs image"
sudo mount -o loop "$ROOTFS_IMAGE" "$MOUNT_POINT"

purple "==> Copying overlay"
sudo cp -rpf "$OVERLAY_DIR/." "$MOUNT_POINT/"
sudo chown -hR 0:0 "$MOUNT_POINT/etc" "$MOUNT_POINT/usr"
fix_rootfs_mode "$MOUNT_POINT" 755 /etc

purple "==> Copying overlay-firmware"
sudo cp -rpf "$OVERLAY_FIRMWARE_DIR/." "$MOUNT_POINT/"
sudo chown -hR 0:0 "$MOUNT_POINT/usr"

if [ "${VERSION:-release}" = "debug" ] && [ -d "$OVERLAY_DEBUG_DIR" ]; then
	purple "==> Copying overlay-debug"
	sudo cp -rpf "$OVERLAY_DEBUG_DIR/." "$MOUNT_POINT/"
	sudo chown -hR 0:0 "$MOUNT_POINT/usr" "$MOUNT_POINT/rockchip-test"
fi

fix_rootfs_mode "$MOUNT_POINT" 4755 /usr/bin/sudo
fix_rootfs_mode "$MOUNT_POINT" 4755 /usr/bin/su

sudo sync

purple "==> Unmounting rootfs image"
sudo umount "$MOUNT_POINT"

purple "==> Done: $ROOTFS_IMAGE updated"

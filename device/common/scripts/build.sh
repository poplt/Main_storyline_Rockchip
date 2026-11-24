#!/bin/bash
#
# Minimal RockChip-style SDK entry script.
#
# Usage:
#   ./build.sh init
#   ./build.sh kernel
#   ./build.sh kernel-config
#   ./build.sh u-boot
#	./build.sh ubuntu-roofts
#   ./build.sh fm
#   ./build.sh fm-uboot
#   ./build.sh fm-boot
#   ./build.sh part

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RK_SDK_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RK_SCRIPTS_DIR="$SCRIPT_DIR"
RK_CONFIG="$RK_SDK_DIR/.config"
LOG_DIR="$RK_SDK_DIR/output/log"

purple()
{
	printf '\033[35m%s\033[0m\n' "$*"
}

run_logged()
{
	local name="$1"; shift

	mkdir -p "$LOG_DIR"
	LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
	echo "Log file: $LOG_FILE"

	"$@" 2>&1 | tee "$LOG_FILE"
	return "${PIPESTATUS[0]}"
}

load_config()
{
	# Make sure the SDK configuration exists before running a build command.
	# From then on every script only reads this single .config file.
	if [ ! -f "$RK_CONFIG" ] || [ ! -s "$RK_CONFIG" ]; then
		purple "==> SDK .config not found, running mk-init.sh"
		"$RK_SCRIPTS_DIR/mk-init.sh"
	fi

	if [ -f "$RK_CONFIG" ] && [ -s "$RK_CONFIG" ]; then
		# shellcheck disable=SC1090
		. "$RK_CONFIG"
	fi
}

usage()
{
	cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  init      Select chip/board config and generate .config.
  kernel    Build the kernel and pack it into an extboot partition image.
  kerneldeb   Build linux-image/headers deb packages (LubanCat-style).
  kernel-config    Open menuconfig and save changes back to the kernel defconfig.
  u-boot    Build mainline U-Boot and copy images to output/uboot.
  ubuntu-rootfs	   Build Filesystem based on ubuntu-base
  update-rootfs-ko   Update an existing rootfs image with compiled .ko modules.
  upoverlay-rootfs   Update an existing rootfs image with overlay files.
  fm        Flash both U-Boot and extboot, then reset.
  fm-loader   Download the Rockchip USB loader only, then stay in loader mode.
  fm-uboot  Flash output/uboot/u-boot-rockchip.bin to eMMC LBA 0x40.
  fm-boot   Flash output/extboot.img to eMMC boot partition LBA 0x8000.
            Pass -1 to skip the final reset.
  part      Write the chip GPT partition table, then print it.
EOF
}

case "${1:-}" in
	init)
		shift
		"$RK_SCRIPTS_DIR/mk-init.sh" --force "$@"
		;;
	kernel)
		load_config
		shift
		run_logged kernel "$RK_SCRIPTS_DIR/mk-kernel.sh" "$@"
		;;
	kerneldeb)
		load_config
		shift
		run_logged kerneldeb "$RK_SCRIPTS_DIR/mk-kerneldeb.sh" "$@"
		;;
	kernel-config)
		load_config
		shift
		"$RK_SCRIPTS_DIR/mk-kernel-config.sh" "$@"
		;;
	u-boot)
		load_config
		shift
		run_logged u-boot "$RK_SCRIPTS_DIR/mk-uboot.sh" "$@"
		;;
	ubuntu-rootfs)
		load_config
		shift
		run_logged ubuntu-rootfs "$RK_SCRIPTS_DIR/mk-ubuntu-rootfs.sh" "$@"
		;;
	update-rootfs-ko|mk-update-rootfs-ko.sh)
		load_config
		shift
		run_logged update-rootfs-ko "$RK_SCRIPTS_DIR/mk-update-rootfs-ko.sh" "$@"
		;;
	upoverlay-rootfs|mk-upoverlay-rootfs.sh)
		load_config
		shift
		run_logged upoverlay-rootfs "$RK_SCRIPTS_DIR/mk-upoverlay-rootfs.sh" "$@"
		;;
	fm)
		shift
		run_logged fm "$RK_SCRIPTS_DIR/mk-fm.sh" "$@"
		;;
	fm-loader)
		load_config
		shift
		run_logged fm-loader "$RK_SCRIPTS_DIR/mk-fm-loader.sh" "$@"
		;;
	fm-uboot)
		shift
		run_logged fm-uboot "$RK_SCRIPTS_DIR/mk-fm-uboot.sh" "$@"
		;;
	fm-boot)
		shift
		run_logged fm-boot "$RK_SCRIPTS_DIR/mk-fm-boot.sh" "$@"
		;;
	part)
		load_config
		shift
		run_logged part "$RK_SCRIPTS_DIR/mk-part.sh" "$@"
		;;

	help|-h|--help|"")
		usage
		;;
	*)
		echo "Unknown command: $1" >&2
		usage
		exit 1
		;;
esac

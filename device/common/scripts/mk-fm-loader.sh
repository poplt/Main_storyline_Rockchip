#!/usr/bin/env bash
#
# mk-fm-loader.sh - download the Rockchip USB loader into a board in Maskrom
# mode. This is the "db <Loader>" step only; the device is left in loader mode
# so it is ready for the next wl/wlx write command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RK_SDK_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RK_CONFIG="$RK_SDK_DIR/.config"

RKDEVTOOL="/usr/local/bin/rkdeveloptool"

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

[ -n "${RK_CHIP:-}" ] || die "RK_CHIP is empty in $RK_CONFIG"

find_loader()
{
	local loader

	loader="$(find "$RK_SDK_DIR/output" -type f \
		\( -name "${RK_CHIP}_spl_loader_*.bin" \
		   -o -name "${RK_CHIP}_*_loader_*.bin" \
		   -o -name "*_${RK_CHIP}_*_loader_*.bin" \
		   -o -name "*${RK_CHIP}*_loader*.bin" \) 2>/dev/null \
		| sort | tail -n 1 || true)"
	if [ -z "$loader" ]; then
		loader="$(find "$RK_SDK_DIR/rkbin" -type f \
			\( -name "${RK_CHIP}_loader_*.bin" \
			   -o -name "MiniLoaderAll.bin" \) 2>/dev/null \
			| sort | tail -n 1)"
	fi
	if [ -z "$loader" ]; then
		loader="$(find "$RK_SDK_DIR/rkbin/bin" -type f \
			-name "${RK_CHIP}_usbplug_*.bin" 2>/dev/null \
			| sort | tail -n 1)"
	fi

	[ -n "$loader" ] || die "no USB loader found for chip '$RK_CHIP'"
	printf '%s\n' "$loader"
}

RKDEVTOOL_LOADER="${FM_LOADER:-$(find_loader)}"

[ -x "$RKDEVTOOL" ] || die "rkdeveloptool not found: $RKDEVTOOL"
[ -f "$RKDEVTOOL_LOADER" ] || die "loader not found: $RKDEVTOOL_LOADER"

purple "==> Loader download parameters"
purple "    RKDEVTOOL = $RKDEVTOOL"
purple "    LOADER    = $RKDEVTOOL_LOADER"

purple "==> Detecting Maskrom device"
if ! sudo "$RKDEVTOOL" ld; then
	die "no Rockchip device found in Maskrom mode"
fi

purple "==> Downloading USB loader"
sudo "$RKDEVTOOL" db "$RKDEVTOOL_LOADER"

purple "==> Loader downloaded; device is ready for wl/wlx writes"

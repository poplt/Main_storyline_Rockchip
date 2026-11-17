#!/usr/bin/env bash
#
# mk-ubuntu-rootfs.sh - dispatch to the ubuntu rootfs builder selected by .config.
#
# The SDK .config selects the rootfs with:
#   ROOTFS_TYPE="ubuntu"
#   ROOTFS_VERSION="26.10"
#   ROOTFS_DESKTOP="gnome"
#
# Those three values are combined into a directory name such as "ubuntu26.10",
# and this script then runs <RK_SDK_DIR>/ubuntu26.10/mk-ubuntu-rootfs.sh.

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

usage()
{
	cat <<EOF
Usage: $(basename "$0") [release|debug]

Reads $RK_CONFIG and runs the matching ubuntu rootfs builder.
The version defaults to "release"; pass "debug" to include debug packages.
EOF
}

BUILD_VERSION="${1:-}"
case "$BUILD_VERSION" in
	release|debug)
		shift
		;;
	"")
		;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		die "unknown argument: $BUILD_VERSION"
		;;
esac

[ -f "$RK_CONFIG" ] && [ -s "$RK_CONFIG" ] || die "SDK config not found: $RK_CONFIG"
# shellcheck disable=SC1090
. "$RK_CONFIG"

ROOTFS_TYPE="${ROOTFS_TYPE:-}"
ROOTFS_VERSION="${ROOTFS_VERSION:-}"
ROOTFS_DESKTOP="${ROOTFS_DESKTOP:-}"

[ -n "$ROOTFS_TYPE" ] || die "ROOTFS_TYPE is not set in $RK_CONFIG"
[ -n "$ROOTFS_VERSION" ] || die "ROOTFS_VERSION is not set in $RK_CONFIG"
[ -n "$ROOTFS_DESKTOP" ] || die "ROOTFS_DESKTOP is not set in $RK_CONFIG"
[ "$ROOTFS_TYPE" = "ubuntu" ] || die "unsupported ROOTFS_TYPE: $ROOTFS_TYPE (only ubuntu is supported)"

ROOTFS_DIR="$RK_SDK_DIR/${ROOTFS_TYPE}${ROOTFS_VERSION}"
ROOTFS_SCRIPT="$ROOTFS_DIR/mk-ubuntu-rootfs.sh"

[ -d "$ROOTFS_DIR" ] || die "ubuntu rootfs directory not found: $ROOTFS_DIR"
[ -x "$ROOTFS_SCRIPT" ] || die "ubuntu rootfs builder not found or not executable: $ROOTFS_SCRIPT"

# The rootfs builder below reads these environment variables instead of
# positional arguments:
#   SOC     - chip number (rk3588/rk3588s, rk3576, ...)
#   TARGET  - desktop flavour used to locate ubuntu-base-<TARGET>-arm64-*.tar.gz
#   VERSION - release or debug
SOC="${SOC:-${RK_CHIP:-}}"
VERSION="${VERSION:-${BUILD_VERSION:-release}}"

case "$ROOTFS_DESKTOP" in
	gnome|gnome-full)
		TARGET="${TARGET:-gnome-full}"
		;;
	xfce|xfce-full)
		TARGET="${TARGET:-xfce-full}"
		;;
	lite)
		TARGET="${TARGET:-lite}"
		;;
	*)
		TARGET="${TARGET:-$ROOTFS_DESKTOP}"
		;;
esac

[ -n "$SOC" ] || die "SOC/RK_CHIP is not set in $RK_CONFIG"
[ -n "$TARGET" ] || die "cannot determine TARGET from ROOTFS_DESKTOP: $ROOTFS_DESKTOP"

purple "==> Ubuntu rootfs build parameters"
purple "    ROOTFS_DIR     = $ROOTFS_DIR"
purple "    ROOTFS_SCRIPT  = $ROOTFS_SCRIPT"
purple "    SOC            = $SOC"
purple "    TARGET         = $TARGET"
purple "    VERSION        = $VERSION"

export SOC TARGET VERSION

cd "$ROOTFS_DIR"
exec "$ROOTFS_SCRIPT"

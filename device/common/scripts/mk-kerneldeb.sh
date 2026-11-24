#!/usr/bin/env bash
#
# mk-kerneldeb.sh - build kernel deb packages (linux-image / linux-headers /
# linux-libc-dev) with the kernel's bindeb-pkg target, LubanCat style.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RK_SDK_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RK_CONFIG="$RK_SDK_DIR/.config"
KERNEL_DIR="$RK_SDK_DIR/kernel"

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

ARCH="arm64"
CROSS_COMPILE="aarch64-linux-gnu-"
ROCKCHIP_CHIP="${RK_CHIP:-}"
KERNEL_CFG="${RK_KERNEL_CFG:-}"
KERNEL_JOBS="${KERNEL_JOBS:-$(nproc)}"
DPKG_FLAGS="${DPKG_FLAGS:--d}"
KERNEL_DEFCONFIG=""

[ -n "$KERNEL_CFG" ] || die "RK_KERNEL_CFG is empty; cannot determine kernel defconfig"
KERNEL_DEFCONFIG="$KERNEL_DIR/arch/$ARCH/configs/$KERNEL_CFG"
[ -f "$KERNEL_DEFCONFIG" ] || die "kernel defconfig not found: $KERNEL_DEFCONFIG"

purple "==> Kernel deb build parameters"
purple "    KERNEL_DIR      = $KERNEL_DIR"
purple "    ARCH            = $ARCH"
purple "    CROSS_COMPILE   = $CROSS_COMPILE"
purple "    ROCKCHIP_CHIP   = ${ROCKCHIP_CHIP:-<none>}"
purple "    DEFCONFIG       = $KERNEL_CFG"
purple "    DEFCONFIG_FILE  = $KERNEL_DEFCONFIG"
purple "    JOBS            = $KERNEL_JOBS"

purple "==> Applying kernel defconfig: $KERNEL_CFG"
make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
	ROCKCHIP_CHIP="$ROCKCHIP_CHIP" "$KERNEL_CFG"

purple "==> Building kernel deb packages (bindeb-pkg)"
make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
	ROCKCHIP_CHIP="$ROCKCHIP_CHIP" DPKG_FLAGS="$DPKG_FLAGS" \
	bindeb-pkg -j"$KERNEL_JOBS"

purple "==> Kernel deb packages generated under: $RK_SDK_DIR"
find "$RK_SDK_DIR" -maxdepth 1 -type f -name 'linux-*.deb' -printf '%f\n' | sort

#!/usr/bin/env bash
# Compila la ISO de LIBIAN TV. Debe ejecutarse como root dentro de Debian trixie
# (p. ej. docker run --privileged debian:trixie). Lo usa el workflow de GitHub Actions
# y también sirve en local:
#   sudo docker run --rm --privileged -v "$PWD":/work -w /work debian:trixie scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

. /etc/os-release
[ "${VERSION_CODENAME:-}" = "trixie" ] || { echo "ERROR: se necesita Debian trixie (hay: ${PRETTY_NAME:-?})"; exit 1; }

apt-get update
apt-get install -y --no-install-recommends \
    live-build debootstrap xorriso squashfs-tools \
    syslinux syslinux-common syslinux-utils isolinux \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
    ca-certificates curl git python3 libarchive-tools file xz-utils zstd cpio rsync gnupg

scripts/preflight.sh

lb clean --purge >/dev/null 2>&1 || true
lb config
scripts/fetch-vacuumtube.sh
echo "== lb config =="; cat config/common 2>/dev/null | head -60 || true

set +e
lb build 2>&1 | tee build.log
build_rc=${PIPESTATUS[0]}
set -e
if [ "$build_rc" -ne 0 ]; then
    echo "ERROR: lb build terminó con código $build_rc"
    exit "$build_rc"
fi

mkdir -p output
iso=$(find . -maxdepth 1 -type f -name '*.iso' | head -n1)
[ -n "$iso" ] || { echo "ERROR: lb build no generó ninguna ISO"; exit 1; }
cp -v "$iso" output/libian-tv-amd64.iso

scripts/verify-iso.sh output/libian-tv-amd64.iso
( cd output && sha256sum libian-tv-amd64.iso | tee SHA256SUMS )
cp build.log output/build.log

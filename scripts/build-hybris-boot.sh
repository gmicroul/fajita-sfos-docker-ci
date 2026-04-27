#!/bin/bash
# build-hybris-boot.sh - 在 Sailfish SDK 中生成 initramfs
# busybox 从 URL 下载（实体机提取的版本）
# 用法: bash build-hybris-boot.sh (生成 /tmp/hybris-initramfs.gz)

set -e

DEVICE="${DEVICE:-fajita}"
DATA_PART="/dev/sda17"
OUT="/tmp/hybris-initramfs.gz"
BUSYBOX_URL="${BUSYBOX_URL:-https://github.com/gmicroul/fajita-sfos-ci/releases/download/droid-boot/busybox}"

echo "=== 生成 hybris initramfs for $DEVICE ==="

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

zypper -n install -y git 2>/dev/null || true
git clone --depth 1 https://github.com/mer-hybris/hybris-boot.git
cd hybris-boot

sed -e "s|%DATA_PART%|$DATA_PART|g" \
    -e 's|%BOOTLOGO%|1|g' \
    -e 's|%NEVERBOOT%|0|g' \
    -e 's|%ALWAYSDEBUG%|0|g' \
    init-script > initramfs/init
chmod +x initramfs/init

bash fixup-mountpoints "$DEVICE" initramfs/init
echo "init fixup done"

# 下载实体机的 busybox
curl -L -o initramfs/bin/busybox "$BUSYBOX_URL" 2>/dev/null || true
chmod +x initramfs/bin/busybox 2>/dev/null || true
echo "busybox: $(ls -la initramfs/bin/busybox)"

(cd initramfs && find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$OUT")
echo "initramfs: $(ls -la $OUT)"
rm -rf "$WORKDIR"
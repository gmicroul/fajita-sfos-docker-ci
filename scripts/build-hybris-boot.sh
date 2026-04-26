#!/bin/bash
# build-hybris-boot.sh - 在 Sailfish SDK 中只生成 initramfs.gz
# mkbootimg 在 host 上做（ubunto apt 装好了）
# 用法: bash build-hybris-boot.sh (生成 /tmp/hybris-initramfs.gz)

set -e

DEVICE="${DEVICE:-fajita}"
DATA_PART="/dev/sda17"
OUT="/tmp/hybris-initramfs.gz"

echo "=== 生成 hybris initramfs for $DEVICE ==="

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

zypper -n install -y git busybox 2>/dev/null || true
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

cp /usr/bin/busybox initramfs/bin/busybox 2>/dev/null || cp /bin/busybox initramfs/bin/busybox 2>/dev/null || true
chmod +x initramfs/bin/busybox 2>/dev/null || true

(cd initramfs && find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$OUT")
echo "initramfs done: $(ls -la $OUT)"
rm -rf "$WORKDIR"
#!/bin/bash
# build-hybris-boot.sh - 在 Sailfish SDK 中生成 initramfs (不含 busybox)
# busybox 由 host 编译 arm64 版本后替换
# 用法: bash build-hybris-boot.sh (生成 /tmp/hybris-initramfs-no-busybox.gz)

set -e

DEVICE="${DEVICE:-fajita}"
DATA_PART="/dev/sda17"
OUT="/tmp/hybris-initramfs-no-busybox.gz"

echo "=== 生成 hybris initramfs (不含 busybox) for $DEVICE ==="

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

# 不复制 busybox，创建占位文件，由 host 端替换
touch initramfs/bin/busybox

(cd initramfs && find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$OUT")
echo "initramfs: $(ls -la $OUT)"
rm -rf "$WORKDIR"
#!/bin/bash
# build-hybris-boot.sh - 在 Sailfish SDK 中生成 initramfs.gz（sed + fixup-mountpoints + cpio）
# 用法: bash build-hybris-boot.sh <compiled_Image.gz-dtb> <output>  (output参数忽略，initramfs写固定路径)

set -e

DEVICE="fajita"
DATA_PART="/dev/sda17"
OUTPUT_INITRAMFS="/tmp/hybris-initramfs.gz"

echo "=== 生成 hybris initramfs for $DEVICE ==="
echo "DATA_PART: $DATA_PART"

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

# 下载 hybris-boot 源码
zypper -n install -y git 2>/dev/null || true
git clone --depth 1 https://github.com/mer-hybris/hybris-boot.git
cd hybris-boot

# 生成 init 脚本
sed -e "s|%DATA_PART%|$DATA_PART|g" \
    -e 's|%BOOTLOGO%|1|g' \
    -e 's|%NEVERBOOT%|0|g' \
    -e 's|%ALWAYSDEBUG%|0|g' \
    init-script > initramfs/init
chmod +x initramfs/init

# 运行 fixup-mountpoints
bash fixup-mountpoints "$DEVICE" initramfs/init
echo "init 脚本已生成并 fixup"

# busybox
if [ -f /usr/bin/busybox ]; then
    cp /usr/bin/busybox initramfs/bin/busybox
elif [ -f /bin/busybox ]; then
    cp /bin/busybox initramfs/bin/busybox
else
    zypper -n install -y busybox 2>/dev/null || true
    cp /usr/bin/busybox initramfs/bin/busybox 2>/dev/null || cp /bin/busybox initramfs/bin/busybox 2>/dev/null || true
fi
chmod +x initramfs/bin/busybox 2>/dev/null || true

# 打包 initramfs
(cd initramfs && find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$OUTPUT_INITRAMFS")
echo "initramfs 生成完成: $(ls -la $OUTPUT_INITRAMFS)"

rm -rf "$WORKDIR"
#!/bin/bash
# build-hybris-boot.sh - 在 Sailfish SDK 中生成 hybris-boot.img
# 用法: bash build-hybris-boot.sh <Image.gz-dtb> <output-boot.img>

set -e

IMAGE_GZ_DTB="$1"
OUTPUT="$2"
DEVICE="${DEVICE:-fajita}"
DATA_PART="/dev/sda17"
BUSYBOX_URL="${BUSYBOX_URL:-https://github.com/gmicroul/fajita-sfos-ci/releases/download/droid-boot/busybox}"

if [ ! -f "$IMAGE_GZ_DTB" ]; then
    echo "错误: $IMAGE_GZ_DTB 不存在"
    exit 1
fi

echo "=== 构建 hybris-boot.img for $DEVICE ==="

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

zypper -n install -y git android-tools-mkbootimg curl 2>/dev/null || true
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

curl -L -o initramfs/bin/busybox "$BUSYBOX_URL" 2>/dev/null || true
chmod +x initramfs/bin/busybox 2>/dev/null || true
echo "busybox: $(ls -la initramfs/bin/busybox)"

(cd initramfs && find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$WORKDIR/initramfs.gz")

mkbootimg \
    --kernel "$IMAGE_GZ_DTB" \
    --ramdisk "$WORKDIR/initramfs.gz" \
    --cmdline 'androidboot.hardware=qcom androidboot.console=ttyMSM0 video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 ehci-hcd.park=3 lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=2048 androidboot.configfs=true androidboot.usbcontroller=a600000.dwc3 firmware_class.path=/vendor/firmware_mnt/image loop.max_part=7 selinux=0' \
    --base 0x80000000 \
    --pagesize 4096 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --second_offset 0x00f00000 \
    --tags_offset 0x00000100 \
    --output "$OUTPUT"

echo "=== 构建完成 ==="
ls -la "$OUTPUT"
rm -rf "$WORKDIR"
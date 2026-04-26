#!/bin/bash
# build-hybris-boot.sh - 在 Sailfish SDK 中构建 hybris-boot.img
# 用法: bash build-hybris-boot.sh <compiled_Image.gz> <output_hybris-boot.img>

set -e

IMAGE_GZ="$1"
OUTPUT="$2"

if [ ! -f "$IMAGE_GZ" ]; then
    echo "错误: $IMAGE_GZ 不存在"
    exit 1
fi

DEVICE="fajita"
# fajita 的 userdata 分区是 sda17
DATA_PART="/dev/sda17"

echo "=== 构建 hybris-boot.img for $DEVICE ==="
echo "内核: $IMAGE_GZ"
echo "DATA_PART: $DATA_PART"

# 在 Sailfish SDK 容器里需要 mkbootimg 和 cpio/gzip
# mkbootimg 在 Sailfish SDK 中可能叫 android-tools 或 mkbootimg
# 先确保工具存在
which mkbootimg > /dev/null 2>&1 || zypper -n install -y mkbootimg 2>/dev/null || {
    echo "mkbootimg 不可用，尝试安装 android-tools..."
    zypper -n install -y android-tools 2>/dev/null || true
}

# 确保 busybox 存在
which busybox > /dev/null 2>&1 || {
    echo "安装 busybox..."
    zypper -n install -y busybox 2>/dev/null || true
}

WORKDIR=$(mktemp -d)
echo "工作目录: $WORKDIR"

# 下载 hybris-boot 源码
cd "$WORKDIR"
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

# 处理 busybox: 用系统的 busybox 复制进去
if [ -f /bin/busybox ]; then
    cp /bin/busybox initramfs/bin/busybox
elif [ -f /usr/bin/busybox ]; then
    cp /usr/bin/busybox initramfs/bin/busybox
else
    echo "警告: 找不到 busybox，尝试下载..."
    curl -L -o initramfs/bin/busybox "https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-armv7l" 2>/dev/null || true
fi
chmod +x initramfs/bin/busybox 2>/dev/null || true

# 打包 initramfs
(cd initramfs && find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$WORKDIR/initramfs.gz")
echo "initramfs 打包完成: $(ls -la $WORKDIR/initramfs.gz)"

# 用 mkbootimg 创建 hybris-boot.img
# fajita 的 boot image 参数（从设备 config.gz 和 hybris-boot.img 获取）
mkbootimg \
    --kernel "$IMAGE_GZ" \
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

# 清理
rm -rf "$WORKDIR"
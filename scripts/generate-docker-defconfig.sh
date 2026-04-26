#!/bin/bash
# generate-docker-defconfig.sh
# 基于实体机运行内核的 config.gz 创建 defconfig，只补 Docker 缺失项
# 用法: bash generate-docker-defconfig.sh <config.gz路径> <输出defconfig路径>

set -e

if [ $# -lt 2 ]; then
    echo "用法: $0 <config.gz> <输出defconfig路径>"
    echo "示例: $0 config.gz arch/arm64/configs/fajita_docker_defconfig"
    exit 1
fi

CONFIG_GZ="$1"
OUTPUT="$2"

if [ ! -f "$CONFIG_GZ" ]; then
    echo "错误: $CONFIG_GZ 不存在"
    exit 1
fi

echo "=== 从实体机内核配置生成 Docker defconfig ==="
echo "源: $CONFIG_GZ"
echo "输出: $OUTPUT"

# 1. 解压 device config 到输出
zcat "$CONFIG_GZ" > "$OUTPUT"
echo "已写入 $(wc -l < "$OUTPUT") 行"

# 2. 追加 Docker 必需配置（基于 check-config.sh 的 missing 项）
cat >> "$OUTPUT" << 'DOCKER_CFG'

# === Docker 支持 - 基于实体机 check-config 缺失项补齐 ===
CONFIG_BRIDGE_NETFILTER=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_MATCH_IPVS=y
CONFIG_IP6_NF_NAT=y
CONFIG_BLK_CGROUP=y
CONFIG_BLK_DEV_THROTTLING=y
CONFIG_CGROUP_PERF=y
CONFIG_CGROUP_HUGETLB=y
CONFIG_CGROUP_NET_PRIO=y
CONFIG_CFS_BANDWIDTH=y
CONFIG_CFQ_GROUP_IOSCHED=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_VXLAN=y
CONFIG_BRIDGE_VLAN_FILTERING=y
CONFIG_IPVLAN=y
CONFIG_DUMMY=y

# DTB 追加 - 指定要嵌入的 dtb 文件
CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES=""

DOCKER_CFG

echo "已追加 Docker 必须配置"
echo "完成: $(wc -l < "$OUTPUT") 行"
#!/bin/sh
# 把系统盘剩余空间分成 ext4 数据分区，挂到 /mnt/data（日志、vnstat、统计数据）
#   用法：sh data-disk.sh [/dev/sda]
#   不动现有分区、不需要重启；已有文件系统的分区绝不格式化
#   x86 的 sysupgrade 在新固件分区布局不变时会保留这个分区
set -e
DISK=${1:-/dev/sda}; MNT=/mnt/data
case "$DISK" in *[0-9]) PART=${DISK}p3 ;; *) PART=${DISK}3 ;; esac   # nvme0n1 / mmcblk0 → p3

apk add -q fdisk partx-utils e2fsprogs block-mount

if [ ! -b "$PART" ]; then
	# 新建第 3 分区占满剩余空间；GPT 盘会顺带把备份分区表移到磁盘末尾
	printf 'n\n3\n\n\nw\n' | fdisk "$DISK"
	partx -a -n 3 "$DISK" 2>/dev/null || true   # fdisk 通常已通知内核，失败无妨
	sleep 1
	[ -b "$PART" ] || { echo "内核还没识别 $PART，重启后再运行一次本脚本"; exit 1; }
fi
block info "$PART" | grep -q 'TYPE=' || mkfs.ext4 -q -F -L data -m 1 "$PART"

UUID=$(block info "$PART" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
[ -n "$UUID" ] || { echo "读不到 $PART 的 UUID"; exit 1; }
uci -q delete fstab.data || true
uci set fstab.data=mount
uci set fstab.data.uuid="$UUID"
uci set fstab.data.target="$MNT"
uci set fstab.data.fstype='ext4'
uci set fstab.data.options='rw,noatime'
uci set fstab.data.enabled='1'
uci commit fstab

# block-mount 可能已把它自动挂到 /mnt/sda3 之类，先卸掉再按 fstab 挂
awk -v p="$PART" -v m="$MNT" '$1==p && $2!=m {print $2}' /proc/mounts | while read -r m; do
	umount "$m" && rmdir "$m" 2>/dev/null || true
done
mkdir -p "$MNT"
grep -q " $MNT " /proc/mounts || block mount
df -h "$MNT"

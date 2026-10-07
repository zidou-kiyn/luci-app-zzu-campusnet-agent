#!/bin/sh
# 用法: sh speedtest.sh <秒数> <每线并发> <线路...>
# 所有线路同时开始，每条线路 N 个并发下载，统计各线路与总和速率 (Mbps)
SECS=$1; N=$2; shift 2
U1="https://dldir1v6.qq.com/weixin/Windows/WeChatSetup.exe"
U2="https://mirrors.aliyun.com/ubuntu-releases/24.04/ubuntu-24.04.3-desktop-amd64.iso"
D=/tmp/st; rm -rf $D; mkdir -p $D
for dev in "$@"; do
	for i in $(seq 1 $N); do
		[ $((i % 2)) -eq 0 ] && URL=$U2 || URL=$U1
		curl -sL -o /dev/null --interface "$dev" -m "$SECS" -w '%{size_download}\n' "$URL" > "$D/$dev.$i" 2>/dev/null &
	done
done
wait
TOTAL=0
for dev in "$@"; do
	B=$(cat $D/$dev.* | awk '{s+=$1} END {printf "%d", s}')
	MBPS=$(awk -v b="$B" -v t="$SECS" 'BEGIN {printf "%.0f", b*8/t/1000000}')
	TOTAL=$((TOTAL + MBPS))
	printf "  %-7s %4s Mbps\n" "$dev" "$MBPS"
done
[ $# -gt 1 ] && printf "  %-7s %4s Mbps\n" "合计" "$TOTAL"

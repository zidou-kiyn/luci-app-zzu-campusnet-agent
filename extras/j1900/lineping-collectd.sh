#!/bin/sh
# collectd exec 插件（以 nobody 运行）：读 /usr/sbin/lineping 的结果，按 ping 插件格式上报
H="${COLLECTD_HOSTNAME:-localhost}"; I="${COLLECTD_INTERVAL:-30}"; I=${I%.*}
while :; do
	for f in /var/run/lineping/*; do
		[ -f "$f" ] || continue
		case "$f" in *.tmp) continue ;; esac
		[ -n "$(find "$f" -mmin -2)" ] || continue   # 守护进程停了就不报旧数据
		d=${f##*/}
		read loss avg sd < "$f"
		echo "PUTVAL \"$H/ping/ping_droprate-$d\" interval=$I N:$loss"
		echo "PUTVAL \"$H/ping/ping-$d\" interval=$I N:$avg"
		echo "PUTVAL \"$H/ping/ping_stddev-$d\" interval=$I N:$sd"
	done
	sleep $I
done

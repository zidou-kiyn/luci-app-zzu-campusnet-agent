#!/bin/sh
# 应用 j1900-setup.sh 写入的配置（后台运行，日志 /tmp/apply.log）
exec >/tmp/apply.log 2>&1
set -x
sleep 2
/etc/init.d/network stop
for d in wanct1 wanct2 wancm1 wancm2; do ip link del "$d" 2>/dev/null; done
sysctl -p /etc/sysctl.d/99-multiwan.conf 2>/dev/null
/etc/init.d/network start
. /lib/functions/network.sh
n=0
while [ $n -lt 60 ]; do
	network_flush_cache; ok=0
	for l in wanct1 wanct2 wancm1 wancm2; do a=""; network_get_ipaddr a "$l"; [ -n "$a" ] && ok=$((ok+1)); done
	[ $ok -eq 4 ] && break
	n=$((n+1)); sleep 1
done
sysctl -p /etc/sysctl.d/99-multiwan.conf
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
/etc/init.d/odhcpd restart 2>/dev/null
/etc/init.d/zzucampusnetagent enable
/etc/init.d/zzucampusnetagent restart
/etc/init.d/zzunetmon enable 2>/dev/null; /etc/init.d/zzunetmon restart 2>/dev/null
/usr/sbin/zzucampusnetagent watchdog
echo APPLY_DONE

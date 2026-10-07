#!/bin/sh
# AdGuard Home 直接面对客户端：AGH :53，dnsmasq :54（只做 DHCP + .lan 本地解析）
exec >/tmp/agh-front.log 2>&1
set -x
Y=/etc/adguardhome/adguardhome.yaml
/etc/init.d/adguardhome stop

# AGH 监听 0.0.0.0:53（WAN 方向由防火墙 input REJECT 挡住）
awk '
/^dns:/ {indns=1}
/^[a-z]/ && !/^dns:/ {indns=0}
indns && /^  bind_hosts:/ {print; print "    - 0.0.0.0"; skip=1; next}
skip && /^    - / {next}
{skip=0}
indns && /^  port: / {print "  port: 53"; next}
{print}
' $Y > /tmp/agh.yaml && cp /tmp/agh.yaml $Y

# dnsmasq 让出 53
uci set dhcp.@dnsmasq[0].port='54'
uci -q delete dhcp.@dnsmasq[0].server
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].localuse='0'        # 路由器自身查 127.0.0.1:53，即 AGH
uci set dhcp.@dnsmasq[0].dns_redirect='0'    # 必须为 0，否则查询被劫持到 :54 导致 REFUSED
uci set dhcp.@dnsmasq[0].cachesize='8000'
uci set dhcp.@dnsmasq[0].min_cache_ttl='3600'
uci set dhcp.@dnsmasq[0].use_stale_cache='3600'
uci -q delete dhcp.lan.dhcp_option
uci add_list dhcp.lan.dhcp_option='6,192.168.31.1'
uci -q delete dhcp.lanct.dhcp_option
uci add_list dhcp.lanct.dhcp_option='6,192.168.32.1'
uci commit dhcp

# 劫持局域网明文 DNS（发往其他 IP 的 53 端口 → 路由器 AGH；发给路由器本身的不重写）
for z in lan:192.168.31.1 lanct:192.168.32.1; do
	ip=${z#*:}; z=${z%%:*}
	uci -q delete firewall.dns_hijack_$z
	uci set firewall.dns_hijack_$z=redirect
	uci set firewall.dns_hijack_$z.name="Hijack-DNS-$z"
	uci set firewall.dns_hijack_$z.src="$z"
	uci set firewall.dns_hijack_$z.proto='tcp udp'
	uci set firewall.dns_hijack_$z.src_dport='53'
	uci set firewall.dns_hijack_$z.src_dip="!$ip"
	uci set firewall.dns_hijack_$z.dest_port='53'
	uci set firewall.dns_hijack_$z.target='DNAT'
done
uci commit firewall

/etc/init.d/dnsmasq restart
/etc/init.d/adguardhome start
/etc/init.d/firewall reload
sleep 3
echo AGH_FRONT_DONE

#!/bin/sh
# 切换时打开 J1900 的 31 网段 DHCP（延时，等小米先转成 AP）
exec >/tmp/dhcp-on.log 2>&1
sleep 20
uci -q delete dhcp.lan.ignore
uci set dhcp.lan.dhcpv4='server'
uci set dhcp.lan.force='1'
uci commit dhcp
/etc/init.d/dnsmasq restart
/etc/init.d/odhcpd restart
echo DHCP_ON

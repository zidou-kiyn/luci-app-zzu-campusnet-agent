#!/bin/sh
# Redmi AX5400 → 纯 AP（后台运行，日志 /tmp/ap.log）
#   可选：先把 irq-pin.sh 传到 /root/，会装成 /usr/sbin/irq-pin.sh 并开机执行（中断固定，替代 irqbalance）
#   WAN 口接 J1900：不带 tag = 31 网段 (br-lan)，VLAN 32 = 32 网段 (br-lanct)
#   Lyra-5G + LAN1-3 → br-lan；Lyra-2.4G → br-lanct；删除 Lyra-CUCC-5G
#   管理地址 192.168.31.2，网关/DNS 192.168.31.1
exec >/tmp/ap.log 2>&1
set -x
sleep 3

# ── 停掉不再需要的服务 ──
for s in zzucampusnetagent zzunetmon sqm https-dns-proxy adblock-fast adguardhome dnsmasq odhcpd firewall; do
	[ -x /etc/init.d/$s ] && { /etc/init.d/$s stop; /etc/init.d/$s disable; }
done
sed -i -E '/zzucampusnetagent|zzunetmon|adblock-fast/d' /etc/crontabs/root
/etc/init.d/cron restart
rm -f /etc/hotplug.d/iface/99-multipath /etc/hotplug.d/iface/90-zzunetmon \
      /etc/sysctl.d/99-multiwan.conf /etc/sysctl.d/99-multipath-hash.conf

# ── network ──
for s in wanct1 wanct2 wancm1 wancm2 wanct1_dev wanct2_dev wancm1_dev wancm2_dev wan_dev wan wan6 lancm lancm_dev; do
	uci -q delete network.$s
done
while uci -q delete network.@rule[0]; do :; done
while uci -q delete network.@route[0]; do :; done
BR=$(uci show network | sed -n "s/^network\.\(@device\[[0-9]*\]\)\.name='br-lan'$/\1/p")
uci -q del_list network.$BR.ports='wan'
uci add_list network.$BR.ports='wan'
uci set network.lan.proto='static'
uci -q delete network.lan.ipaddr
uci set network.lan.ipaddr='192.168.31.2/24'
uci set network.lan.gateway='192.168.31.1'
uci -q delete network.lan.dns
uci add_list network.lan.dns='192.168.31.1'
uci -q delete network.lan.ip6assign
uci set network.vlan32=device
uci set network.vlan32.type='8021q'
uci set network.vlan32.ifname='wan'
uci set network.vlan32.vid='32'
uci set network.vlan32.name='wan.32'
uci set network.lanct_dev=device
uci set network.lanct_dev.name='br-lanct'
uci set network.lanct_dev.type='bridge'
uci -q delete network.lanct_dev.ports
uci add_list network.lanct_dev.ports='wan.32'
uci set network.lanct=interface
uci set network.lanct.proto='none'
uci set network.lanct.device='br-lanct'
uci commit network

# ── dhcp：AP 不发地址 ──
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.dhcpv4='disabled'
uci -q delete dhcp.lancm
uci -q delete dhcp.lancm_dns
for l in wan wanct1 wanct2 wancm1 wancm2; do uci -q delete dhcp.$l; done
uci commit dhcp

# ── wireless ──
uci set wireless.default_radio1.network='lan'     # Lyra-5G  → 联通
uci set wireless.default_radio0.network='lanct'   # Lyra-2.4G → 电信
uci -q delete wireless.lancm_ap                    # 删除 Lyra-CUCC-5G
uci commit wireless

# ── 中断固定（AP 只有转发 + WiFi，固定分配比 irqbalance 更稳）──
if [ -f /root/irq-pin.sh ]; then
	cp /root/irq-pin.sh /usr/sbin/irq-pin.sh; chmod +x /usr/sbin/irq-pin.sh
	grep -q irq-pin.sh /etc/rc.local || sed -i '/^exit 0/i /usr/sbin/irq-pin.sh' /etc/rc.local
	[ -x /etc/init.d/irqbalance ] && { /etc/init.d/irqbalance stop; /etc/init.d/irqbalance disable; }
fi

# ── 应用 ──
/etc/init.d/network stop
for d in wanct1 wanct2 wancm1 wancm2; do ip link del "$d" 2>/dev/null; done
ip addr flush dev wan 2>/dev/null
/etc/init.d/network start
sleep 5
wifi reload
[ -x /usr/sbin/irq-pin.sh ] && /usr/sbin/irq-pin.sh
echo AP_DONE

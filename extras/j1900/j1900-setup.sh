#!/bin/sh
# J1900 主路由配置（由小米 Lyra 迁移）
#   31 网段 lan   (br-lan  = eth0 不带 tag)  → 联通组 (main 表)  Lyra-5G + 有线
#   32 网段 lanct (br-lanct = eth0.32 tag)   → 电信组 (wanct 表) Lyra-2.4G
#   WAN: eth1 上 4 条 macvlan，MAC 沿用小米
#   192.168.1.1 保留为 lan 上的管理地址（救援用）
#   需先把 extras/99-multipath 传到 /root/
set -e
[ -f /root/99-multipath ] || { echo '缺少 /root/99-multipath'; exit 1; }
GW=10.172.255.254

# ── system ──
uci set system.@system[0].hostname='Lyra'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].timezone='CST-8'
uci commit system

# ── 路由表 ──
sed -i -E '/^1(00|0[1-4])[[:space:]]+(wanct|wancm|wanct1|wanct2|wancm1|wancm2)$/d' /etc/iproute2/rt_tables
cat >> /etc/iproute2/rt_tables <<'EOF'
100	wanct
101	wanct1
102	wanct2
103	wancm1
104	wancm2
EOF

# ── network ──
uci -q delete network.wan || true
uci -q delete network.wan6 || true
uci set network.globals.packet_steering='2'

# lan：31 网段 + 管理地址 192.168.1.1
uci -q delete network.lan.ipaddr || true
uci -q delete network.lan.ip6assign || true
uci add_list network.lan.ipaddr='192.168.31.1/24'
uci add_list network.lan.ipaddr='192.168.1.1/24'

# lanct：VLAN 32
uci -q delete network.vlan32 || true
uci set network.vlan32=device
uci set network.vlan32.type='8021q'
uci set network.vlan32.ifname='eth0'
uci set network.vlan32.vid='32'
uci set network.vlan32.name='eth0.32'
uci -q delete network.lanct_dev || true
uci set network.lanct_dev=device
uci set network.lanct_dev.name='br-lanct'
uci set network.lanct_dev.type='bridge'
uci add_list network.lanct_dev.ports='eth0.32'
uci -q delete network.lanct || true
uci set network.lanct=interface
uci set network.lanct.proto='static'
uci set network.lanct.device='br-lanct'
uci set network.lanct.ipaddr='192.168.32.1/24'

# 4 条 WAN 线路（MAC 沿用小米）
add_line() { # name mac
	uci -q delete "network.$1_dev" || true
	uci set "network.$1_dev=device"
	uci set "network.$1_dev.name=$1"
	uci set "network.$1_dev.type=macvlan"
	uci set "network.$1_dev.ifname=eth1"
	uci set "network.$1_dev.mode=bridge"
	uci set "network.$1_dev.macaddr=$2"
	uci set "network.$1_dev.ipv6=0"
	uci -q delete "network.$1" || true
	uci set "network.$1=interface"
	uci set "network.$1.proto=dhcp"
	uci set "network.$1.device=$1"
	uci set "network.$1.peerdns=0"
	uci add_list "network.$1.dns=223.5.5.5"
	uci add_list "network.$1.dns=119.29.29.29"
	uci set "network.$1.ip4table=$1"
}
# MAC 用环境变量传入（换路由器时沿用旧路由器的 MAC，校园网 IP 不变）
# 未设置时随机生成本地管理地址（02:xx:...）
rand_mac() { hexdump -n5 -e '"02" 5/1 ":%02x"' /dev/urandom; }
add_line wanct1 "${MAC_WANCT1:-$(rand_mac)}"
add_line wanct2 "${MAC_WANCT2:-$(rand_mac)}"
add_line wancm1 "${MAC_WANCM1:-$(rand_mac)}"
add_line wancm2 "${MAC_WANCM2:-$(rand_mac)}"

# 策略路由：局域网互访/直连网段先查 main（不含默认路由）；32 网段默认走电信组表
for r in rule_local rule_lanct; do uci -q delete "network.$r" || true; done
uci set network.rule_local=rule
uci set network.rule_local.lookup='main'
uci set network.rule_local.suppress_prefixlength='0'
uci set network.rule_local.priority='999'
uci set network.rule_lanct=rule
uci set network.rule_lanct.in='lanct'
uci set network.rule_lanct.src='192.168.32.0/24'
uci set network.rule_lanct.lookup='wanct'
uci set network.rule_lanct.priority='1000'
uci commit network

# ── firewall ──
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci set firewall.@defaults[0].fullcone='1'
WZ=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
uci -q delete "firewall.$WZ.network" || true
for n in wanct1 wanct2 wancm1 wancm2; do uci add_list "firewall.$WZ.network=$n"; done
uci set "firewall.$WZ.masq=1"
uci set "firewall.$WZ.mtu_fix=1"
uci -q delete firewall.lanct || true
uci set firewall.lanct=zone
uci set firewall.lanct.name='lanct'
uci add_list firewall.lanct.network='lanct'
uci set firewall.lanct.input='ACCEPT'
uci set firewall.lanct.output='ACCEPT'
uci set firewall.lanct.forward='ACCEPT'
for f in lanct_wan lan_lanct lanct_lan; do uci -q delete "firewall.$f" || true; done
uci set firewall.lanct_wan=forwarding;  uci set firewall.lanct_wan.src='lanct'; uci set firewall.lanct_wan.dest='wan'
uci set firewall.lan_lanct=forwarding;  uci set firewall.lan_lanct.src='lan';   uci set firewall.lan_lanct.dest='lanct'
uci set firewall.lanct_lan=forwarding;  uci set firewall.lanct_lan.src='lanct'; uci set firewall.lanct_lan.dest='lan'
uci commit firewall

# ── dhcp / dns（AdGuard Home 装好前先用明文公共 DNS）──
uci -q delete dhcp.wan || true
uci set dhcp.@dnsmasq[0].noresolv='1'
uci -q delete dhcp.@dnsmasq[0].server || true
uci add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci add_list dhcp.@dnsmasq[0].server='119.29.29.29'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ra='disabled'
uci -q delete dhcp.lan.ra_slaac || true
# 切换前先不在 31 网段发 DHCP（此时 eth0 对面还是小米 WAN），切换时再打开
uci set dhcp.lan.ignore='1'
uci -q delete dhcp.lanct || true
uci set dhcp.lanct=dhcp
uci set dhcp.lanct.interface='lanct'
uci set dhcp.lanct.start='100'
uci set dhcp.lanct.limit='150'
uci set dhcp.lanct.leasetime='12h'
uci set dhcp.lanct.dhcpv6='disabled'
uci set dhcp.lanct.ra='disabled'
for l in wanct1 wanct2 wancm1 wancm2; do
	uci -q delete "dhcp.$l" || true
	uci set "dhcp.$l=dhcp"; uci set "dhcp.$l.interface=$l"; uci set "dhcp.$l.ignore=1"
done
# 静态租约
while uci -q delete dhcp.@host[0]; do :; done
add_host() { # name ip mac
	local s; s=$(uci add dhcp host)
	[ -n "$1" ] && uci set "dhcp.$s.name=$1"
	uci set "dhcp.$s.ip=$2"; uci set "dhcp.$s.mac=$3"
}
# 示例：add_host '设备名' 192.168.31.x 'aa:bb:cc:dd:ee:ff'
# 也可放到 /root/hosts.txt（每行：名称 IP MAC），存在时自动导入
if [ -f /root/hosts.txt ]; then
	while read -r n i m; do [ -n "$m" ] && add_host "$n" "$i" "$m"; done < /root/hosts.txt
fi
uci commit dhcp

# ── sysctl：同网段多出口防 ARP 串线；多路哈希按连接 ──
for d in wanct1 wanct2 wancm1 wancm2; do
	echo "net.ipv4.conf.$d.arp_ignore=1"
	echo "net.ipv4.conf.$d.arp_announce=2"
	echo "net.ipv4.conf.$d.rp_filter=2"
done > /etc/sysctl.d/99-multiwan.conf
echo "net.ipv4.fib_multipath_hash_policy=1" > /etc/sysctl.d/99-multipath-hash.conf
sysctl -w net.ipv4.fib_multipath_hash_policy=1 >/dev/null

# ── 组路由 hotplug：联通组 → main，电信组 → wanct ──
# 与 extras/99-multipath 相同，需先一起传到 /root/
cp /root/99-multipath /etc/hotplug.d/iface/99-multipath
chmod +x /etc/hotplug.d/iface/99-multipath

# ── 认证插件配置（填好账号密码的 zzucampusnetagent.example 先传到 /tmp/zzucampusnetagent.cfg）──
[ -f /tmp/zzucampusnetagent.cfg ] && cp /tmp/zzucampusnetagent.cfg /etc/config/zzucampusnetagent
uci -q delete zzucampusnetagent.netmon.iface || true
uci add_list zzucampusnetagent.netmon.iface='lan'
uci add_list zzucampusnetagent.netmon.iface='lanct'
uci commit zzucampusnetagent

echo "config written"

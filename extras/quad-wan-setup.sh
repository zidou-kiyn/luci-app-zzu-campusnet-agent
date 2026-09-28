#!/bin/sh
# quad-wan-setup.sh — 4 线聚合一键配置（在 dual-isp-setup.sh、dual-isp-sqm.sh 之后运行）
#   电信组 → 主 LAN (192.168.31.0/24)：wanct1(A号) + wanct2(B号)  多路负载均衡
#   移动组 → lancm  (192.168.32.0/24)：wancm1(A号) + wancm2(A号)  多路负载均衡
#
# 路由设计：
#   - 每条线路一张自己的路由表（netifd ip4table），netifd 自动加 "from <线路IP> lookup <线路表>"，
#     保证路由器自身发出的包（认证、DoH）源 IP 与出口一致。校园网按 MAC 识别会话，
#     源 IP 与出口不一致时，认证请求会被算到另一条线上（看门狗误判、登录串号）
#   - 组表只放多路默认路由，由 hotplug 99-multipath 维护：电信组 = main 表，移动组 = wancm 表
#   - 多路哈希按连接（L4 五元组）：单任务多线程下载可叠加；同组线路出口 IP 相同，换线不掉网站登录
#
# 用法: ACCT_B=<B号账号> PASS_B=<B号密码> sh quad-wan-setup.sh   安装
#       sh quad-wan-setup.sh remove                                 卸载（回到双线）
# 安装/卸载会重启网络，四条线路断开约 30 秒；DHCP 可能分到新 IP，脚本结尾会立即补登认证。

GW=10.172.255.254
CM_GROUP=wancm                 # 移动组路由表（dual-isp-setup.sh 创建，id 100）
LINES="wanct1 wanct2 wancm1 wancm2"

# ── 固定 MAC（同一 MAC 续租同一 IP）：沿用已有配置，首次随机生成；可用环境变量覆盖 ──
pick_mac() { # 设备名
	local m; m=$(uci -q get "network.$1_dev.macaddr")
	[ -n "$m" ] && echo "$m" || hexdump -n5 -e '"02" 5/1 ":%02x"' /dev/urandom
}
MAC_WANCT2="${MAC_WANCT2:-$(pick_mac wanct2)}"
MAC_WANCM2="${MAC_WANCM2:-$(pick_mac wancm2)}"

wan_zone() { uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p"; }

# netifd 停止时不会删除 macvlan：残留设备会导致同名设备认领失败、新设备套不上原 MAC，
# 因此先停网、删掉各线路设备，再启动
restart_net() {
	/etc/init.d/network stop
	for d in $LINES; do ip link del "$d" 2>/dev/null; done
	/etc/init.d/network start
	/etc/init.d/firewall restart
}

remove() {
	echo ">>> 拆除 4 线配置..."
	for s in wanct2_dev wanct2 wancm2_dev wancm2; do uci -q delete "network.$s"; done
	uci -q delete network.wanct1.ip4table          # 主线路默认路由回到 main 表
	uci set "network.wancm1.ip4table=$CM_GROUP"    # 移动线路回到组表
	Z=$(wan_zone)
	uci -q del_list "firewall.$Z.network=wanct2"
	uci -q del_list "firewall.$Z.network=wancm2"
	uci -q delete zzucampusnetagent.wanct2
	uci -q delete zzucampusnetagent.wancm2
	uci commit network; uci commit firewall; uci commit zzucampusnetagent
	sed -i -E '/^10[1-4][[:space:]]+(wanct1|wanct2|wancm1|wancm2)$/d' /etc/iproute2/rt_tables
	rm -f /etc/hotplug.d/iface/99-multipath /etc/sysctl.d/99-multiwan.conf /etc/sysctl.d/99-multipath-hash.conf
	sysctl -w net.ipv4.fib_multipath_hash_policy=0 >/dev/null
	for t in 101 102 103 104; do ip route flush table $t 2>/dev/null; done
	restart_net
	/etc/init.d/zzucampusnetagent reload 2>/dev/null
	echo "<<< 已拆除"
	exit 0
}

[ "$1" = "remove" ] && remove

ACCT_B="${ACCT_B:?请设置环境变量 ACCT_B（B 号账号）}"
PASS_B="${PASS_B:?请设置环境变量 PASS_B（B 号密码）}"

for n in wanct1 wancm1; do
	uci -q get "network.$n" >/dev/null || { echo "缺少接口 $n：请先运行 dual-isp-setup.sh 与 dual-isp-sqm.sh"; exit 1; }
done

# ── 路由表：每条线路一张 ──
sed -i -E '/^10[1-4][[:space:]]+(wanct1|wanct2|wancm1|wancm2)$/d' /etc/iproute2/rt_tables
cat >> /etc/iproute2/rt_tables <<'EOF'
101	wanct1
102	wanct2
103	wancm1
104	wancm2
EOF

echo ">>> 创建 wanct2 (B号电信) 和 wancm2 (A号移动#2)..."
add_line() { # name mac
	uci -q delete "network.$1_dev"
	uci set "network.$1_dev=device"
	uci set "network.$1_dev.name=$1"
	uci set "network.$1_dev.type=macvlan"
	uci set "network.$1_dev.ifname=wan"
	uci set "network.$1_dev.mode=bridge"
	uci set "network.$1_dev.macaddr=$2"
	uci set "network.$1_dev.ipv6=0"
	uci -q delete "network.$1"
	uci set "network.$1=interface"
	uci set "network.$1.proto=dhcp"
	uci set "network.$1.device=$1"
	uci set "network.$1.peerdns=0"
}
add_line wanct2 "$MAC_WANCT2"
add_line wancm2 "$MAC_WANCM2"
for n in $LINES; do uci set "network.$n.ip4table=$n"; done
uci commit network

# ── 防火墙：新接口加入 wan 区域（NAT）──
Z=$(wan_zone)
for n in wanct2 wancm2; do
	uci -q get "firewall.$Z.network" | grep -qw "$n" || uci add_list "firewall.$Z.network=$n"
done
uci commit firewall

# ── 认证插件：主线路绑定 wanct1，新增两条线路 ──
echo ">>> 配置认证线路..."
uci set zzucampusnetagent.config.iface='wanct1'
[ "$(uci -q get zzucampusnetagent.config.name)" = "主线路" ] && uci set zzucampusnetagent.config.name='电信1'
uci set zzucampusnetagent.wanct2=line
uci set zzucampusnetagent.wanct2.enabled='1'
uci set zzucampusnetagent.wanct2.name='电信2'
uci set zzucampusnetagent.wanct2.iface='wanct2'
uci set zzucampusnetagent.wanct2.isp='telecom'
uci set zzucampusnetagent.wanct2.account="$ACCT_B"
uci set zzucampusnetagent.wanct2.password="$PASS_B"
uci set zzucampusnetagent.wancm2=line
uci set zzucampusnetagent.wancm2.enabled='1'
uci set zzucampusnetagent.wancm2.name='移动2'
uci set zzucampusnetagent.wancm2.iface='wancm2'
uci set zzucampusnetagent.wancm2.isp='cmcc'
# wancm2 的 account/password 留空 → 继承主账号 A
uci reorder zzucampusnetagent.wanct2=1
uci -q get zzucampusnetagent.wancm1 >/dev/null && uci reorder zzucampusnetagent.wancm1=2
uci reorder zzucampusnetagent.wancm2=3
uci commit zzucampusnetagent

# ── sysctl：同网段多出口防 ARP 串线；多路哈希按连接 ──
for d in $LINES; do
	echo "net.ipv4.conf.$d.arp_ignore=1"
	echo "net.ipv4.conf.$d.arp_announce=2"
	echo "net.ipv4.conf.$d.rp_filter=2"
done > /etc/sysctl.d/99-multiwan.conf
echo "net.ipv4.fib_multipath_hash_policy=1" > /etc/sysctl.d/99-multipath-hash.conf
sysctl -w net.ipv4.fib_multipath_hash_policy=1 >/dev/null

# ── Hotplug：维护两个组表的多路默认路由（与 extras/99-multipath 相同）──
echo ">>> 安装 multipath 热插拔脚本..."
cat > /etc/hotplug.d/iface/99-multipath << 'HOTPLUG_EOF'
#!/bin/sh
# /etc/hotplug.d/iface/99-multipath（由 quad-wan-setup.sh 安装）
# 每条线路有自己的路由表（netifd ip4table，按源 IP 选表，保证源 IP 与出口一致）；
# 这里只维护两个“组表”的多路默认路由：
#   电信组 → main  表：wanct1 + wanct2
#   移动组 → wancm 表：wancm1 + wancm2
# 各线网关同为校园网网关，组表内没有直连路由，因此 nexthop 用 onlink。
[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ] || exit 0

GW=10.172.255.254

build() {
	local tbl="$1" NH="" n=0 dev ip; shift
	for dev in "$@"; do
		ip link show "$dev" up >/dev/null 2>&1 || continue
		ip=$(ip -4 -br addr show dev "$dev" 2>/dev/null | awk '{print $3}')
		[ -z "$ip" ] && continue
		NH="$NH nexthop via $GW dev $dev weight 1 onlink"
		n=$((n + 1))
	done
	while ip route del default table "$tbl" 2>/dev/null; do :; done
	[ "$n" -gt 0 ] && ip route add default table "$tbl" $NH
	logger -t multipath "$tbl: $n path(s)"
}

case "$INTERFACE" in
	wanct1|wanct2) build main  wanct1 wanct2 ;;
	wancm1|wancm2) build wancm wancm1 wancm2 ;;
esac
HOTPLUG_EOF
chmod +x /etc/hotplug.d/iface/99-multipath

# ── 应用 ──
echo ">>> 重启网络（线路断开约 30 秒）..."
for t in 101 102 103 104; do ip route flush table $t 2>/dev/null; done
restart_net

echo ">>> 等待四条线路获取 IP..."
. /lib/functions/network.sh
n=0
while [ $n -lt 60 ]; do
	network_flush_cache; ok=0
	for l in $LINES; do a=""; network_get_ipaddr a "$l"; [ -n "$a" ] && ok=$((ok+1)); done
	[ $ok -eq 4 ] && break
	n=$((n+1)); sleep 1
done

[ -x /etc/init.d/https-dns-proxy ] && /etc/init.d/https-dns-proxy restart
/etc/init.d/dnsmasq restart
/etc/init.d/zzucampusnetagent reload 2>/dev/null
zzucampusnetagent watchdog     # IP 变化导致掉认证时立即补登

echo ""
echo "=== 接口 ==="
ip -br addr show | grep -E 'wanct|wancm'
echo ""
echo "=== 组表 ==="
echo "电信组 (main):";  ip route show default
echo "移动组 ($CM_GROUP):"; ip route show default table $CM_GROUP
echo ""
echo "=== 认证线路 ==="
zzucampusnetagent status
echo ""
echo ">>> 完成！如需卸载: sh $0 remove"

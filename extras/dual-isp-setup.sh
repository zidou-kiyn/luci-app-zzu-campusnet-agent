#!/bin/sh
# ============================================================
#  双运营商分流：同一校园网账号在同一根网线上同时登录两个运营商
#  - 主线路（原 WAN）保持不变，现有 WiFi/LAN 继续走它
#  - 在 WAN 上建 macvlan 虚拟 WAN（第二个 MAC → 第二个校园网 IP）
#  - 新建独立网段 + 专用 WiFi，该网段固定走虚拟 WAN（断线不回落主线路）
#  - 在插件里添加对应的“额外线路”，自动认证/保活
#
#  用法（在路由器上）：  sh dual-isp-setup.sh            安装/更新
#                        sh dual-isp-setup.sh remove     移除
#  可用环境变量覆盖下面的默认值，例如：
#    SSID=My-CMCC RADIO=radio1 SUBNET=192.168.32 ISP=cmcc sh dual-isp-setup.sh
# ============================================================

PARENT="${PARENT:-wan}"                 # 主 WAN 设备
IFACE="${IFACE:-wancm}"                 # 虚拟 WAN 逻辑接口名 / 设备名
LAN="${LAN:-lancm}"                     # 专用网段逻辑接口名
BRIDGE="${BRIDGE:-br-cmcc}"
SUBNET="${SUBNET:-192.168.32}"          # 专用网段 x.x.x.0/24，网关 .1
TABLE_ID="${TABLE_ID:-100}"
TABLE="${TABLE:-cmcc}"
ZONE="${ZONE:-cmcc}"
RADIO="${RADIO:-radio1}"                # 挂在哪个射频上（radio1 通常为 5G）
SSID="${SSID:-OpenWrt-CMCC-5G}"
KEY="${KEY:-}"                          # 留空 = 沿用该射频上默认 WiFi 的密码
ISP="${ISP:-cmcc}"
NAME="${NAME:-移动下载}"
DNS="${DNS:-223.5.5.5,119.29.29.29}"    # 下发给专用网段客户端的 DNS（经虚拟 WAN 出去，CDN 按该运营商调度）
MAC="${MAC:-}"                          # 留空 = 首次随机生成并固定

S="$(echo "$IFACE" | tr -c 'A-Za-z0-9_\n' '_')"   # UCI 段名前缀

if [ "$1" = "remove" ]; then
	for c in "network.${S}_dev" "network.$IFACE" "network.${S}_br" "network.$LAN" \
	         "network.${S}_rule" "network.${S}_strict" "network.${S}_main" \
	         "dhcp.$LAN" "firewall.${S}_zone" "firewall.${S}_fwd" "wireless.${S}_ap" \
	         "zzucampusnetagent.$S"; do
		uci -q delete "$c"
	done
	Z=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
	[ -n "$Z" ] && uci -q del_list "firewall.$Z.network=$IFACE"
	uci commit; rm -f /etc/sysctl.d/99-zzu-multiwan.conf
	/etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/dnsmasq reload
	/etc/init.d/zzucampusnetagent reload 2>/dev/null; wifi reload
	echo "==> 已移除"; exit 0
fi

# 固定 MAC：同一 MAC 续租同一 IP，认证不易失效
if [ -z "$MAC" ]; then
	MAC=$(uci -q get "network.${S}_dev.macaddr")
	[ -z "$MAC" ] && MAC=$(hexdump -n5 -e '"02" 5/1 ":%02x"' /dev/urandom)
fi

grep -q "^$TABLE_ID[[:space:]]" /etc/iproute2/rt_tables || echo "$TABLE_ID	$TABLE" >> /etc/iproute2/rt_tables

# ---- network ----
uci -q delete "network.${S}_dev"
uci set "network.${S}_dev=device"
uci set "network.${S}_dev.name=$IFACE"
uci set "network.${S}_dev.type=macvlan"
uci set "network.${S}_dev.ifname=$PARENT"
uci set "network.${S}_dev.mode=bridge"
uci set "network.${S}_dev.macaddr=$MAC"

uci -q delete "network.$IFACE"
uci set "network.$IFACE=interface"
uci set "network.$IFACE.proto=dhcp"
uci set "network.$IFACE.device=$IFACE"
uci set "network.$IFACE.peerdns=0"
uci set "network.$IFACE.ip4table=$TABLE"     # 路由进独立表，不影响主线路默认路由

# 网桥必须有独立 MAC：只挂一个 WiFi 时网桥会沿用该 WiFi 接口的 MAC（=BSSID），
# 在 NSS WiFi 卸载的高通平台上会导致客户端发给路由器的单播（含 ARP 应答）收不到，
# 表现为能拿到 IP 但“无法访问互联网”
BRMAC=$(uci -q get "network.${S}_br.macaddr")
[ -z "$BRMAC" ] && BRMAC=$(hexdump -n5 -e '"02" 5/1 ":%02x"' /dev/urandom)
uci -q delete "network.${S}_br"
uci set "network.${S}_br=device"
uci set "network.${S}_br.name=$BRIDGE"
uci set "network.${S}_br.type=bridge"
uci set "network.${S}_br.bridge_empty=1"
uci set "network.${S}_br.macaddr=$BRMAC"

uci -q delete "network.$LAN"
uci set "network.$LAN=interface"
uci set "network.$LAN.proto=static"
uci set "network.$LAN.device=$BRIDGE"
uci set "network.$LAN.ipaddr=$SUBNET.1/24"

# 专用网段 → 独立表；表为空（虚拟 WAN 断开）时不可达，不回落主线路
# 必须限定 in=$LAN（iif 网桥）：否则路由器自己以 $SUBNET.1 为源发给客户端的包
# （DNS 应答、LuCI 等）也会命中该规则被送去 WAN，表现为能上网但系统提示“无法访问互联网”
uci -q delete "network.${S}_rule"
uci set "network.${S}_rule=rule"
uci set "network.${S}_rule.in=$LAN"
uci set "network.${S}_rule.src=$SUBNET.0/24"
uci set "network.${S}_rule.lookup=$TABLE"
uci set "network.${S}_rule.priority=1000"
uci -q delete "network.${S}_strict"
uci set "network.${S}_strict=rule"
uci set "network.${S}_strict.in=$LAN"
uci set "network.${S}_strict.src=$SUBNET.0/24"
uci set "network.${S}_strict.action=unreachable"
uci set "network.${S}_strict.priority=1001"
# netifd 会给 ip4table 接口加 "to <校园网子网> lookup 表"(优先级 20000)，
# 会把路由器发往校园网内网的未绑定流量（含主线路 DHCP 续租）错送到虚拟 WAN；
# 这里先查 main 表（忽略默认路由），让它们仍走主线路
uci -q delete "network.${S}_main"
uci set "network.${S}_main=rule"
uci set "network.${S}_main.lookup=main"
uci set "network.${S}_main.suppress_prefixlength=0"
uci set "network.${S}_main.priority=15000"

# 同网段双出口：防止主 WAN 代答虚拟 WAN 的 ARP（否则认证服务器看到的 MAC 会串）
cat > /etc/sysctl.d/99-zzu-multiwan.conf <<'C'
net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
C
sysctl -q -p /etc/sysctl.d/99-zzu-multiwan.conf

# ---- dhcp ----
uci -q delete "dhcp.$LAN"
uci set "dhcp.$LAN=dhcp"
uci set "dhcp.$LAN.interface=$LAN"
uci set "dhcp.$LAN.start=100"
uci set "dhcp.$LAN.limit=150"
uci set "dhcp.$LAN.leasetime=12h"
[ -n "$DNS" ] && uci add_list "dhcp.$LAN.dhcp_option=6,$DNS"

# ---- firewall ----
Z=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
uci -q get "firewall.$Z.network" | grep -qw "$IFACE" || uci add_list "firewall.$Z.network=$IFACE"
uci -q delete "firewall.${S}_zone"
uci set "firewall.${S}_zone=zone"
uci set "firewall.${S}_zone.name=$ZONE"
uci add_list "firewall.${S}_zone.network=$LAN"
uci set "firewall.${S}_zone.input=ACCEPT"
uci set "firewall.${S}_zone.output=ACCEPT"
uci set "firewall.${S}_zone.forward=REJECT"
uci -q delete "firewall.${S}_fwd"
uci set "firewall.${S}_fwd=forwarding"
uci set "firewall.${S}_fwd.src=$ZONE"
uci set "firewall.${S}_fwd.dest=wan"

# ---- wireless ----
if [ -z "$KEY" ]; then
	KEY=$(uci show wireless | sed -n "s/^wireless\.\([^.]*\)\.device='$RADIO'$/\1/p" | while read -r sec; do
		uci -q get "wireless.$sec.key" && break; done)
fi
uci -q delete "wireless.${S}_ap"
uci set "wireless.${S}_ap=wifi-iface"
uci set "wireless.${S}_ap.device=$RADIO"
uci set "wireless.${S}_ap.network=$LAN"
uci set "wireless.${S}_ap.mode=ap"
uci set "wireless.${S}_ap.ssid=$SSID"
if [ -n "$KEY" ]; then
	uci set "wireless.${S}_ap.encryption=psk2"
	uci set "wireless.${S}_ap.key=$KEY"
else
	uci set "wireless.${S}_ap.encryption=none"
fi

# ---- 插件：额外线路 + 掉线自动重登 ----
if uci -q get zzucampusnetagent.config >/dev/null; then
	uci -q delete "zzucampusnetagent.$S"
	uci set "zzucampusnetagent.$S=line"
	uci set "zzucampusnetagent.$S.enabled=1"
	uci set "zzucampusnetagent.$S.name=$NAME"
	uci set "zzucampusnetagent.$S.iface=$IFACE"
	uci set "zzucampusnetagent.$S.isp=$ISP"
	uci set zzucampusnetagent.config.watchdog=1
fi

uci commit
/etc/init.d/network reload
/etc/init.d/firewall reload
/etc/init.d/dnsmasq reload
/etc/init.d/zzucampusnetagent reload 2>/dev/null

. /lib/functions/network.sh
i=0; ADDR=""
while [ $i -lt 30 ]; do network_flush_cache; network_get_ipaddr ADDR "$IFACE"; [ -n "$ADDR" ] && break; sleep 1; i=$((i+1)); done
echo "==> $IFACE 获取到 IP: ${ADDR:-（暂未获取，稍后在 LuCI 查看）}"
[ -n "$ADDR" ] && command -v zzucampusnetagent >/dev/null && zzucampusnetagent login "$S"; echo
wifi reload
echo "==> 完成：连接 WiFi「$SSID」即走 $ISP 线路（$SUBNET.0/24）"

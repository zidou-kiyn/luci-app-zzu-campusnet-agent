#!/bin/sh
# ============================================================
#  双运营商分流：同一校园网账号在同一根网线上同时登录两个运营商
#  - 主线路（原 WAN）保持不变，现有 WiFi/LAN 继续走它
#  - 在 WAN 上建 macvlan 虚拟 WAN（第二个 MAC → 第二个校园网 IP）
#  - 新建独立网段 + 专用 WiFi，该网段固定走虚拟 WAN（断线不回落主线路）
#  - 专用网段用独立 dnsmasq 实例，上游为经虚拟 WAN 出口的公共加密 DNS（DoH），
#    CDN 按该运营商调度；未装 https-dns-proxy 时退化为经虚拟 WAN 的明文公共 DNS
#  - 在插件里添加对应的“额外线路”，自动认证/保活
#
#  用法（在路由器上）：  sh dual-isp-setup.sh            安装/更新
#                        sh dual-isp-setup.sh remove     移除
#  可用环境变量覆盖下面的默认值，例如：
#    SSID=My-CMCC RADIO=radio1 SUBNET=192.168.32 ISP=cmcc sh dual-isp-setup.sh
# ============================================================

# 命名约定：线路 = wan<运营商><序号>（逻辑接口名 = 设备名），如 wanct1 / wancm1；
#           专用网段 = lan<运营商>，网桥 br-<网段>，防火墙区同名；运营商组路由表 = wan<运营商>
PARENT="${PARENT:-wan}"                 # 物理 WAN 设备
IFACE="${IFACE:-wancm1}"                # 虚拟 WAN 逻辑接口名 / 设备名
LAN="${LAN:-lancm}"                     # 专用网段逻辑接口名
BRIDGE="${BRIDGE:-br-$LAN}"
SUBNET="${SUBNET:-192.168.32}"          # 专用网段 x.x.x.0/24，网关 .1
TABLE_ID="${TABLE_ID:-100}"
TABLE="${TABLE:-wancm}"                 # 该运营商的组路由表
ZONE="${ZONE:-$LAN}"                    # 专用网段防火墙区
RADIO="${RADIO:-radio1}"                # 挂在哪个射频上（radio1 通常为 5G）
SSID="${SSID:-OpenWrt-CMCC-5G}"
KEY="${KEY:-}"                          # 留空 = 沿用该射频上默认 WiFi 的密码
ISP="${ISP:-cmcc}"
NAME="${NAME:-移动1}"
MAC="${MAC:-}"                          # 留空 = 首次随机生成并固定
ENC="${ENC:-}"                          # 留空 = 支持 WPA3 则 sae-mixed，否则 psk2
# 专用网段 DNS：两个 DoH 进程以专用用户运行，该用户的流量按 uidrange 规则走虚拟 WAN
DOH1_URL="${DOH1_URL:-https://dns.alidns.com/dns-query}"; DOH1_BOOT="${DOH1_BOOT:-223.5.5.5,223.6.6.6}"
DOH2_URL="${DOH2_URL:-https://doh.pub/dns-query}";         DOH2_BOOT="${DOH2_BOOT:-119.29.29.29,119.28.28.28}"
DOH_PORT1="${DOH_PORT1:-5055}"; DOH_PORT2="${DOH_PORT2:-5056}"
DNS_UID="${DNS_UID:-6053}"
PLAIN_DNS="${PLAIN_DNS:-223.5.5.5 119.29.29.29}"   # 未装 https-dns-proxy 时的明文上游

S="$(echo "$IFACE" | tr -c 'A-Za-z0-9_\n' '_')"   # 线路相关 UCI 段名前缀（macvlan、插件线路）
L="$(echo "$LAN" | tr -c 'A-Za-z0-9_\n' '_')"     # 网段相关 UCI 段名前缀（网桥、规则、防火墙、WiFi、DNS）
DNSI="${L}_dns"                                     # 专用 dnsmasq 实例名（不能与 dhcp.$LAN 重名）
DNSU="dns$L"                                        # DoH 进程运行用户

# 除专用实例外的 dnsmasq 段（主实例）
other_dnsmasq() {
	uci show dhcp | sed -n "s/^dhcp\.\([^.]*\)=dnsmasq$/\1/p" | grep -vx "$DNSI"
}

if [ "$1" = "remove" ]; then
	for c in "network.${S}_dev" "network.$IFACE" "network.${L}_dev" "network.$LAN" \
	         "network.${L}_rule" "network.${L}_strict" "network.main_suppress" \
	         "network.${L}_dnsuid" "network.${L}_dnsuid_strict" \
	         "dhcp.$LAN" "dhcp.$DNSI" "https-dns-proxy.${L}_ali" "https-dns-proxy.${L}_tx" \
	         "firewall.$L" "firewall.${L}_wan" "wireless.${L}_ap" \
	         "zzucampusnetagent.$S"; do
		uci -q delete "$c"
	done
	for d in $(other_dnsmasq); do uci -q del_list "dhcp.$d.notinterface=$LAN"; done
	[ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update)" = "-" ] && \
		uci set https-dns-proxy.config.dnsmasq_config_update='*'
	Z=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
	[ -n "$Z" ] && uci -q del_list "firewall.$Z.network=$IFACE"
	uci commit; rm -f /etc/sysctl.d/99-zzu-multiwan.conf
	/etc/init.d/network reload; /etc/init.d/firewall reload
	[ -x /etc/init.d/https-dns-proxy ] && /etc/init.d/https-dns-proxy restart
	/etc/init.d/dnsmasq restart
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
# 重建时保留已有的 ipv6 开关（关闭 IPv6 时会设 ipv6=0）；未设置过则沿用父设备的
V6=$(uci -q get "network.${S}_dev.ipv6")
if [ -z "$V6" ]; then
	PSEC=$(uci show network | sed -n "s/^network\.\([^.]*\)\.name='$PARENT'$/\1/p" | head -1)
	[ -n "$PSEC" ] && V6=$(uci -q get "network.$PSEC.ipv6")
fi
uci -q delete "network.${S}_dev"
uci set "network.${S}_dev=device"
uci set "network.${S}_dev.name=$IFACE"
uci set "network.${S}_dev.type=macvlan"
uci set "network.${S}_dev.ifname=$PARENT"
uci set "network.${S}_dev.mode=bridge"
uci set "network.${S}_dev.macaddr=$MAC"
[ -n "$V6" ] && uci set "network.${S}_dev.ipv6=$V6"

uci -q delete "network.$IFACE"
uci set "network.$IFACE=interface"
uci set "network.$IFACE.proto=dhcp"
uci set "network.$IFACE.device=$IFACE"
uci set "network.$IFACE.peerdns=0"
uci set "network.$IFACE.ip4table=$TABLE"     # 路由进独立表，不影响主线路默认路由

# 网桥必须有独立 MAC：只挂一个 WiFi 时网桥会沿用该 WiFi 接口的 MAC（=BSSID），
# 在 NSS WiFi 卸载的高通平台上会导致客户端发给路由器的单播（含 ARP 应答）收不到，
# 表现为能拿到 IP 但“无法访问互联网”
BRMAC=$(uci -q get "network.${L}_dev.macaddr")
[ -z "$BRMAC" ] && BRMAC=$(hexdump -n5 -e '"02" 5/1 ":%02x"' /dev/urandom)
uci -q delete "network.${L}_dev"
uci set "network.${L}_dev=device"
uci set "network.${L}_dev.name=$BRIDGE"
uci set "network.${L}_dev.type=bridge"
uci set "network.${L}_dev.bridge_empty=1"
uci set "network.${L}_dev.macaddr=$BRMAC"

uci -q delete "network.$LAN"
uci set "network.$LAN=interface"
uci set "network.$LAN.proto=static"
uci set "network.$LAN.device=$BRIDGE"
uci set "network.$LAN.ipaddr=$SUBNET.1/24"

# 专用网段 → 独立表；表为空（虚拟 WAN 断开）时不可达，不回落主线路
# 必须限定 in=$LAN（iif 网桥）：否则路由器自己以 $SUBNET.1 为源发给客户端的包
# （DNS 应答、LuCI 等）也会命中该规则被送去 WAN，表现为能上网但系统提示“无法访问互联网”
uci -q delete "network.${L}_rule"
uci set "network.${L}_rule=rule"
uci set "network.${L}_rule.in=$LAN"
uci set "network.${L}_rule.src=$SUBNET.0/24"
uci set "network.${L}_rule.lookup=$TABLE"
uci set "network.${L}_rule.priority=1000"
uci -q delete "network.${L}_strict"
uci set "network.${L}_strict=rule"
uci set "network.${L}_strict.in=$LAN"
uci set "network.${L}_strict.src=$SUBNET.0/24"
uci set "network.${L}_strict.action=unreachable"
uci set "network.${L}_strict.priority=1001"
# netifd 会给 ip4table 接口加 "to <校园网子网> lookup 表"(优先级 20000)，
# 会把路由器发往校园网内网的未绑定流量（含主线路 DHCP 续租）错送到虚拟 WAN；
# 这里先查 main 表（忽略默认路由），让它们仍走主线路
uci -q delete "network.main_suppress"
uci set "network.main_suppress=rule"
uci set "network.main_suppress.lookup=main"
uci set "network.main_suppress.suppress_prefixlength=0"
uci set "network.main_suppress.priority=15000"

# 同网段双出口：防止主 WAN 代答虚拟 WAN 的 ARP（否则认证服务器看到的 MAC 会串）
cat > /etc/sysctl.d/99-zzu-multiwan.conf <<'C'
net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
C
sysctl -q -p /etc/sysctl.d/99-zzu-multiwan.conf

# ---- DNS：专用网段独立 dnsmasq 实例，经虚拟 WAN 的加密 DNS 解析 ----
# 有 https-dns-proxy → 新增两个 DoH 进程，以专用用户 $DNSU 运行；该用户流量按 uidrange
#   规则查虚拟 WAN 的路由表（不依赖 IP，虚拟 WAN 换 IP 也无需改配置），表空时不可达不泄漏到主线路
# 无 https-dns-proxy → 退化为绑定虚拟 WAN 的明文公共 DNS
if [ -x /etc/init.d/https-dns-proxy ]; then
	. /lib/functions.sh
	group_exists "$DNSU" || group_add "$DNSU" "$DNS_UID"
	user_exists "$DNSU"  || user_add "$DNSU" "$DNS_UID" "$DNS_UID" "$DNSU" "/var/run/$DNSU" /bin/false
	# 优先级须在 netifd 的“from <线路 IP> lookup <线路表>”(10000) 之后：TCP 建连时内核会带上
	# 已选定的源 IP 重新查路由，若先命中本规则，多线路时可能换到另一条线（源 IP 与出口不一致）
	uci -q delete "network.${L}_dnsuid"
	uci set "network.${L}_dnsuid=rule"
	uci set "network.${L}_dnsuid.uidrange=$DNS_UID"
	uci set "network.${L}_dnsuid.lookup=$TABLE"
	uci set "network.${L}_dnsuid.priority=12000"
	uci -q delete "network.${L}_dnsuid_strict"
	uci set "network.${L}_dnsuid_strict=rule"
	uci set "network.${L}_dnsuid_strict.uidrange=$DNS_UID"
	uci set "network.${L}_dnsuid_strict.action=unreachable"
	uci set "network.${L}_dnsuid_strict.priority=12001"

	# https-dns-proxy 默认会把所有 DoH 进程写进所有 dnsmasq 实例（主实例也会用上走虚拟 WAN 的 DoH），
	# 改为不自动改写；主实例此前由它写入的 server=127.0.0.1#5053... 已持久化在 UCI 中，保持不变
	uci set https-dns-proxy.config.dnsmasq_config_update='-'
	for x in "${L}_ali $DOH1_URL $DOH1_BOOT $DOH_PORT1" "${L}_tx $DOH2_URL $DOH2_BOOT $DOH_PORT2"; do
		set -- $x
		uci -q delete "https-dns-proxy.$1"
		uci set "https-dns-proxy.$1=https-dns-proxy"
		uci set "https-dns-proxy.$1.resolver_url=$2"
		uci set "https-dns-proxy.$1.bootstrap_dns=$3"
		uci set "https-dns-proxy.$1.listen_addr=127.0.0.1"
		uci set "https-dns-proxy.$1.listen_port=$4"
		uci set "https-dns-proxy.$1.user=$DNSU"
		uci set "https-dns-proxy.$1.group=$DNSU"
	done
	UPSTREAMS="127.0.0.1#$DOH_PORT1 127.0.0.1#$DOH_PORT2"
else
	UPSTREAMS=""; for d in $PLAIN_DNS; do UPSTREAMS="$UPSTREAMS $d@$IFACE"; done
fi

# 主实例不再服务专用网段
for d in $(other_dnsmasq); do
	uci -q del_list "dhcp.$d.notinterface=$LAN"; uci add_list "dhcp.$d.notinterface=$LAN"
done
uci -q delete "dhcp.$DNSI"
uci set "dhcp.$DNSI=dnsmasq"
for kv in domainneeded=1 boguspriv=1 localise_queries=1 rebind_protection=1 rebind_localhost=1 \
          local=/$L/ domain=$L expandhosts=1 authoritative=1 readethers=0 \
          leasefile=/tmp/dhcp.leases.$L noresolv=1 localuse=0 localservice=1 \
          cachesize=10000 dnsforwardmax=1000 filter_aaaa=1 ednspacket_max=1232; do
	uci set "dhcp.$DNSI.${kv%%=*}=${kv#*=}"
done
uci add_list "dhcp.$DNSI.interface=$LAN"
uci add_list "dhcp.$DNSI.notinterface=loopback"   # 127.0.0.1:53 归主实例
for u in $UPSTREAMS; do uci add_list "dhcp.$DNSI.server=$u"; done
# 并发问所有上游取最快；缓存过期后先返回旧结果再后台刷新（最多超期 1 小时）
uci set "dhcp.$DNSI.extraconftext=all-servers\nuse-stale-cache=3600"

# ---- dhcp（由专用实例提供，客户端 DNS 即路由器自己）----
uci -q delete "dhcp.$LAN"
uci set "dhcp.$LAN=dhcp"
uci set "dhcp.$LAN.interface=$LAN"
uci set "dhcp.$LAN.instance=$DNSI"
uci set "dhcp.$LAN.start=100"
uci set "dhcp.$LAN.limit=150"
uci set "dhcp.$LAN.leasetime=12h"

# ---- firewall ----
Z=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
uci -q get "firewall.$Z.network" | grep -qw "$IFACE" || uci add_list "firewall.$Z.network=$IFACE"
uci -q delete "firewall.$L"
uci set "firewall.$L=zone"
uci set "firewall.$L.name=$ZONE"
uci add_list "firewall.$L.network=$LAN"
uci set "firewall.$L.input=ACCEPT"
uci set "firewall.$L.output=ACCEPT"
uci set "firewall.$L.forward=REJECT"
uci -q delete "firewall.${L}_wan"
uci set "firewall.${L}_wan=forwarding"
uci set "firewall.${L}_wan.src=$ZONE"
uci set "firewall.${L}_wan.dest=wan"

# ---- wireless ----
if [ -z "$KEY" ]; then
	KEY=$(uci show wireless | sed -n "s/^wireless\.\([^.]*\)\.device='$RADIO'$/\1/p" | while read -r sec; do
		uci -q get "wireless.$sec.key" && break; done)
fi
uci -q delete "wireless.${L}_ap"
uci set "wireless.${L}_ap=wifi-iface"
uci set "wireless.${L}_ap.device=$RADIO"
uci set "wireless.${L}_ap.network=$LAN"
uci set "wireless.${L}_ap.mode=ap"
uci set "wireless.${L}_ap.ssid=$SSID"
if [ -z "$ENC" ]; then
	hostapd -vsae >/dev/null 2>&1 && ENC=sae-mixed || ENC=psk2
fi
if [ -n "$KEY" ]; then
	uci set "wireless.${L}_ap.encryption=$ENC"
	uci set "wireless.${L}_ap.key=$KEY"
else
	uci set "wireless.${L}_ap.encryption=none"
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
# DoH 进程需在 uidrange 规则就绪后启动；新增 dnsmasq 实例需 restart 而非 reload
i=0; until ip rule | grep -q "iif $BRIDGE lookup $TABLE" || [ $i -ge 15 ]; do sleep 1; i=$((i+1)); done
[ -x /etc/init.d/https-dns-proxy ] && /etc/init.d/https-dns-proxy restart
/etc/init.d/dnsmasq restart
/etc/init.d/zzucampusnetagent reload 2>/dev/null

. /lib/functions/network.sh
i=0; ADDR=""
while [ $i -lt 30 ]; do network_flush_cache; network_get_ipaddr ADDR "$IFACE"; [ -n "$ADDR" ] && break; sleep 1; i=$((i+1)); done
echo "==> $IFACE 获取到 IP: ${ADDR:-（暂未获取，稍后在 LuCI 查看）}"
[ -n "$ADDR" ] && command -v zzucampusnetagent >/dev/null && zzucampusnetagent login "$S"; echo
wifi reload
echo "==> 完成：连接 WiFi「$SSID」即走 $ISP 线路（$SUBNET.0/24）"

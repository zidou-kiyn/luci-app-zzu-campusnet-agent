#!/bin/sh
# quad-wan-setup.sh — 4 线聚合一键配置
#   主 LAN (192.168.31.0/24): wanct(A电信) + wanbt(B电信)  多路负载均衡
#   CMCC (192.168.32.0/24):   wancm(A移动) + wancm2(A移动2) 多路负载均衡
#
# 用法: sh quad-wan-setup.sh          安装
#       sh quad-wan-setup.sh remove   卸载

set -e
GW=10.172.255.254

# ── 固定 MAC（保持 DHCP 租约稳定）──
MAC_WANBT="02:00:00:00:00:02"
MAC_WANCM2="02:00:00:00:00:03"

# ── B 号凭据（请替换为实际值）──
ACCT_B="${ACCT_B:?请设置环境变量 ACCT_B}"
PASS_B="${PASS_B:?请设置环境变量 PASS_B}"

remove() {
    echo ">>> 拆除 quad-wan 配置..."
    # 删 UCI 网络
    for s in wanbt_dev wanbt wancm2_dev wancm2; do
        uci -q delete network.$s 2>/dev/null
    done
    # 删 UCI 防火墙
    uci -q delete firewall.wanbt_fwd 2>/dev/null
    # 把 wanbt/wancm2 从 wan zone 移除
    local nets
    nets=$(uci -q get firewall.@zone[1].network 2>/dev/null)
    local new=""
    for n in $nets; do
        case "$n" in wanbt|wancm2) ;; *) new="$new $n" ;; esac
    done
    uci set firewall.@zone[1].network="$new"
    # 删 zzucampusnetagent 线路
    uci -q delete zzucampusnetagent.wanbt 2>/dev/null
    uci -q delete zzucampusnetagent.wancm2 2>/dev/null
    # 删 hotplug 脚本
    rm -f /etc/hotplug.d/iface/99-multipath
    # 提交 + 重启
    uci commit network; uci commit firewall; uci commit zzucampusnetagent
    /etc/init.d/network restart
    /etc/init.d/firewall restart
    /etc/init.d/zzucampusnetagent restart 2>/dev/null
    echo "<<< 已拆除"
    exit 0
}

[ "$1" = "remove" ] && remove

echo ">>> 创建 wanbt (B号电信) 和 wancm2 (A号移动#2)..."

# ── wanbt: B 号电信 ──
uci set network.wanbt_dev=device
uci set network.wanbt_dev.name='wanbt'
uci set network.wanbt_dev.type='macvlan'
uci set network.wanbt_dev.ifname='wan'
uci set network.wanbt_dev.mode='bridge'
uci set network.wanbt_dev.macaddr="$MAC_WANBT"
uci set network.wanbt_dev.ipv6='0'

uci set network.wanbt=interface
uci set network.wanbt.proto='dhcp'
uci set network.wanbt.device='wanbt'
uci set network.wanbt.peerdns='0'
uci set network.wanbt.ip4table='wanbt'

# ARP 防串线
uci set network.wanbt.arp_ignore='1'
uci set network.wanbt.arp_announce='2'

# ── wancm2: A 号移动 #2 ──
uci set network.wancm2_dev=device
uci set network.wancm2_dev.name='wancm2'
uci set network.wancm2_dev.type='macvlan'
uci set network.wancm2_dev.ifname='wan'
uci set network.wancm2_dev.mode='bridge'
uci set network.wancm2_dev.macaddr="$MAC_WANCM2"
uci set network.wancm2_dev.ipv6='0'

uci set network.wancm2=interface
uci set network.wancm2.proto='dhcp'
uci set network.wancm2.device='wancm2'
uci set network.wancm2.peerdns='0'
uci set network.wancm2.ip4table='wancm2'

uci set network.wancm2.arp_ignore='1'
uci set network.wancm2.arp_announce='2'

uci commit network

# ── 防火墙：把新接口加入 wan zone（masquerade）──
echo ">>> 配置防火墙..."
WAN_NETS=$(uci -q get firewall.@zone[1].network)
echo "$WAN_NETS" | grep -q wanbt  || uci add_list firewall.@zone[1].network='wanbt'
echo "$WAN_NETS" | grep -q wancm2 || uci add_list firewall.@zone[1].network='wancm2'
uci commit firewall

# ── zzucampusnetagent 线路 ──
echo ">>> 配置认证线路..."
uci set zzucampusnetagent.wanbt=line
uci set zzucampusnetagent.wanbt.enabled='1'
uci set zzucampusnetagent.wanbt.name='电信B'
uci set zzucampusnetagent.wanbt.iface='wanbt'
uci set zzucampusnetagent.wanbt.isp='telecom'
uci set zzucampusnetagent.wanbt.account="$ACCT_B"
uci set zzucampusnetagent.wanbt.password="$PASS_B"

uci set zzucampusnetagent.wancm2=line
uci set zzucampusnetagent.wancm2.enabled='1'
uci set zzucampusnetagent.wancm2.name='移动A2'
uci set zzucampusnetagent.wancm2.iface='wancm2'
uci set zzucampusnetagent.wancm2.isp='cmcc'
# account/password 留空 → 继承主账号 A

uci commit zzucampusnetagent

# ── Hotplug 多路负载均衡脚本 ──
echo ">>> 创建 multipath 热插拔脚本..."
cat > /etc/hotplug.d/iface/99-multipath << 'HOTPLUG_EOF'
#!/bin/sh
# 4 线聚合多路负载均衡
# 电信组 (main table): wanct + wanbt
# 移动组 (cmcc table): wancm + wancm2
[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ] || exit 0

. /lib/functions/network.sh
GW=10.172.255.254

get_v4() { local _ip; network_get_ipaddr _ip "$1" && echo "$_ip"; }

update_multipath() {
    local table="$1"; shift  # table name/number
    local NH="" count=0
    while [ "$#" -ge 1 ]; do
        local iface="$1"; shift
        local dev
        # 获取底层设备名（netifd 接口名 → 设备名）
        network_flush_cache
        dev=$(uci -q get "network.${iface}.device")
        [ -z "$dev" ] && continue
        ip link show "$dev" up >/dev/null 2>&1 || continue
        local ip
        ip=$(get_v4 "$iface")
        [ -z "$ip" ] && continue
        NH="$NH nexthop via $GW dev $dev weight 1"
        count=$((count + 1))
    done
    [ "$count" -eq 0 ] && return
    if [ "$table" = "main" ]; then
        ip route replace default $NH 2>/dev/null
    else
        ip route replace default $NH table "$table" 2>/dev/null
    fi
    logger -t multipath "$table: $count nexthop(s) active"
}

case "$INTERFACE" in
    wan|wanbt)
        update_multipath main wan wanbt
        ;;
    wancm|wancm2)
        update_multipath cmcc wancm wancm2
        ;;
esac
HOTPLUG_EOF
chmod +x /etc/hotplug.d/iface/99-multipath

# ── 应用 ──
echo ">>> 重启网络 + 防火墙..."
/etc/init.d/network restart
sleep 3
/etc/init.d/firewall restart
/etc/init.d/zzucampusnetagent restart 2>/dev/null

# ── 等待接口上线 ──
echo ">>> 等待新接口 DHCP..."
n=0
while [ $n -lt 30 ]; do
    . /lib/functions/network.sh; network_flush_cache
    ip_bt=""; ip_cm2=""
    network_get_ipaddr ip_bt wanbt 2>/dev/null
    network_get_ipaddr ip_cm2 wancm2 2>/dev/null
    [ -n "$ip_bt" ] && [ -n "$ip_cm2" ] && break
    n=$((n+1)); sleep 1
done

echo ""
echo "=== 接口状态 ==="
ip -br addr show | grep -E 'wanct|wanbt|wancm'
echo ""
echo "=== 路由表 ==="
echo "main:"; ip route show default
echo "cmcc:"; ip route show default table cmcc 2>/dev/null
echo ""
echo "=== 认证线路 ==="
zzucampusnetagent status
echo ""
echo ">>> 完成！如需卸载: sh $0 remove"

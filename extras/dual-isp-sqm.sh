#!/bin/sh
# ============================================================
#  双线路分别限速（SQM / cake），配合 dual-isp-setup.sh 使用
#
#  为什么要把主线路也改成 macvlan：
#    macvlan 的流量会先经过父设备 wan 的 tc ingress 钩子，SQM 直接挂在 wan
#    或物理口上会把两条线路的流量算在一起。把主线路也挪到 macvlan（wanct1）后，
#    wan 只做“底座”不带 IP，每条线路的 SQM 只看得到自己的流量。
#    wanct1 沿用原 WAN 的 MAC（wan 本身换成随机 MAC），因此主线路 IP / 认证不变。
#    主线路逻辑接口同时从 wan 改名为 wanct1（与设备同名），防火墙 wan 区域、dhcp 段随之更新；
#    若有其它软件按逻辑名引用 wan（如 upnp / ddns），需改成 wanct1。
#
#  用法（在路由器上）：  sh dual-isp-sqm.sh           安装/更新
#                        sh dual-isp-sqm.sh remove    还原（主线路回到 wan，删除两条 SQM）
#  速率单位 kbit/s，建议取实测的 90%~95%：
#    CT_DOWN=142000 CT_UP=50000 CM_DOWN=285000 CM_UP=50000 sh dual-isp-sqm.sh
# ============================================================

PARENT="${PARENT:-wan}"          # 物理 WAN 设备
MAIN_OLD="${MAIN_OLD:-wan}"      # 主线路原逻辑接口名
MAIN="${MAIN:-wanct1}"           # 主线路新逻辑接口名
MAIN_DEV="${MAIN_DEV:-$MAIN}"    # 主线路新 macvlan 设备名（与逻辑名一致）
CM_DEV="${CM_DEV:-wancm1}"       # 第二线路 macvlan 设备名（dual-isp-setup.sh 创建）
CT_DOWN="${CT_DOWN:-142000}"; CT_UP="${CT_UP:-50000}"
CM_DOWN="${CM_DOWN:-285000}"; CM_UP="${CM_UP:-50000}"

PS="$(echo "$PARENT" | tr -c 'A-Za-z0-9_\n' '_')_dev"
MS="$(echo "$MAIN_DEV" | tr -c 'A-Za-z0-9_\n' '_')_dev"

# 找到（或创建）物理 WAN 的 device 段
parent_sec() {
	local s
	s=$(uci show network | sed -n "s/^network\.\([^.]*\)\.name='$PARENT'$/\1/p" | head -1)
	if [ -z "$s" ]; then
		s="$PS"; uci set "network.$s=device"; uci set "network.$s.name=$PARENT"
	fi
	echo "$s"
}

# 逻辑接口改名，并同步防火墙 wan 区域与 dhcp 段里的引用
rename_iface() { # from to
	local z d
	uci -q get "network.$1" >/dev/null || return 0
	uci -q get "network.$2" >/dev/null && return 0
	uci rename "network.$1=$2"
	z=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
	if [ -n "$z" ] && uci -q get "firewall.$z.network" | grep -qw "$1"; then
		uci del_list "firewall.$z.network=$1"; uci add_list "firewall.$z.network=$2"
	fi
	for d in $(uci show dhcp | sed -n "s/^dhcp\.\([^.]*\)\.interface='$1'$/\1/p"); do
		uci set "dhcp.$d.interface=$2"
		[ "$d" = "$1" ] && uci rename "dhcp.$d=$2"
	done
	uci commit firewall; uci commit dhcp
}

del_sqm() {
	for s in $(uci -q show sqm | sed -n "s/^sqm\.\([^.]*\)=queue$/\1/p"); do
		case "$(uci -q get sqm.$s.interface)" in
			"$MAIN_DEV"|"$CM_DEV"|eth0|"$PARENT") uci -q delete "sqm.$s" ;;
		esac
	done
}

add_sqm() { # name dev down up
	uci set "sqm.$1=queue"
	uci set "sqm.$1.enabled=1"
	uci set "sqm.$1.interface=$2"
	uci set "sqm.$1.download=$3"
	uci set "sqm.$1.upload=$4"
	uci set "sqm.$1.qdisc=cake"
	uci set "sqm.$1.script=piece_of_cake.qos"
	uci set "sqm.$1.linklayer=ethernet"
	uci set "sqm.$1.overhead=22"
	uci set "sqm.$1.debug_logging=0"
	uci set "sqm.$1.verbosity=5"
}

P=$(parent_sec)

if [ "$1" = "remove" ]; then
	MAC=$(uci -q get "network.$MS.macaddr")
	uci -q delete "network.$MS"
	rename_iface "$MAIN" "$MAIN_OLD"; MAIN="$MAIN_OLD"
	uci set "network.$MAIN.device=$PARENT"
	uci -q get network.wan6 >/dev/null && uci set "network.wan6.device=$PARENT"
	uci -q delete "network.$P.macaddr"
	del_sqm
	uci commit network; uci commit sqm
	/etc/init.d/sqm stop; /etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/sqm start
	echo "==> 已还原：主线路回到 $PARENT（原 MAC ${MAC:-未知}）。如需整体限速请在 LuCI → 网络 → SQM 重新配置。"
	exit 0
fi

# 原 WAN MAC：优先取已有 macvlan 的（重复执行时），否则取物理口当前 MAC
MAC=$(uci -q get "network.$MS.macaddr")
[ -z "$MAC" ] && MAC=$(cat "/sys/class/net/$PARENT/address")
PMAC=$(uci -q get "network.$P.macaddr")
[ -z "$PMAC" ] && PMAC=$(hexdump -n5 -e '"02" 5/1 ":%02x"' /dev/urandom)

uci set "network.$P.macaddr=$PMAC"

uci -q delete "network.$MS"
uci set "network.$MS=device"
uci set "network.$MS.name=$MAIN_DEV"
uci set "network.$MS.type=macvlan"
uci set "network.$MS.ifname=$PARENT"
uci set "network.$MS.mode=bridge"
uci set "network.$MS.macaddr=$MAC"
[ "$(uci -q get "network.$P.ipv6")" = "0" ] && uci set "network.$MS.ipv6=0"

rename_iface "$MAIN_OLD" "$MAIN"
uci set "network.$MAIN.device=$MAIN_DEV"
uci -q get network.wan6 >/dev/null && uci set "network.wan6.device=$MAIN_DEV"

# 两条 cake + ifb 很吃 CPU；小核数路由网卡中断往往只在 CPU0，打开 RPS（全部 CPU）分摊软中断
# 实测 2 核 A53@1GHz：两线同时满载总吞吐约 140M → 230M
uci set network.globals.packet_steering='2'

del_sqm
add_sqm "$MAIN_DEV" "$MAIN_DEV" "$CT_DOWN" "$CT_UP"
add_sqm "$CM_DEV"   "$CM_DEV"   "$CM_DOWN" "$CM_UP"

uci commit network; uci commit sqm
/etc/init.d/sqm stop
/etc/init.d/network reload
/etc/init.d/firewall reload

. /lib/functions/network.sh
i=0; ADDR=""
while [ $i -lt 30 ]; do network_flush_cache; network_get_ipaddr ADDR "$MAIN"; [ -n "$ADDR" ] && break; sleep 1; i=$((i+1)); done
echo "==> 主线路 $MAIN → $MAIN_DEV ($MAC)，IP: ${ADDR:-未获取}"
[ -x /usr/libexec/network/packet-steering.uc ] && /usr/libexec/network/packet-steering.uc 2
/etc/init.d/sqm enable; /etc/init.d/sqm start
# 若 IP 变化导致掉认证，立即补登（插件掉线检测也会兜底）
command -v zzucampusnetagent >/dev/null && zzucampusnetagent watchdog
tc qdisc show | grep -E "cake.*(ifb4)?($MAIN_DEV|$CM_DEV)" 
echo "==> 完成：$MAIN_DEV ↓${CT_DOWN} ↑${CT_UP}，$CM_DEV ↓${CM_DOWN} ↑${CM_UP} (kbit/s)"

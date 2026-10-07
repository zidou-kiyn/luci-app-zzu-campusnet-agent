#!/bin/sh
# Nikki 白名单模式配置
set -e
# ── 代理范围：只代理局域网白名单设备，不代理路由器自身 ──
uci set nikki.proxy.router_proxy='0'
uci set nikki.proxy.lan_proxy='1'
uci -q delete nikki.proxy.lan_inbound_interface || true
uci add_list nikki.proxy.lan_inbound_interface='lan'
uci add_list nikki.proxy.lan_inbound_interface='lanct'
uci set nikki.proxy.bypass_china_mainland_ip='1'
uci set nikki.proxy.bypass_china_mainland_ip6='1'
# 删除默认的"全部设备都代理"规则 → 白名单（无匹配 = 不代理）
while uci -q delete nikki.@lan_access_control[0]; do :; done

# ── fake-ip 过滤：国内/局域网/联网检测域名返回真实 IP，才能被"绕过大陆 IP"直连 ──
uci set nikki.mixin.fake_ip_filter='1'
uci -q delete nikki.mixin.fake_ip_filters || true
for d in '+.lan' '+.local' 'geosite:private' 'geosite:cn' \
         '+.msftconnecttest.com' '+.msftncsi.com' '+.ntp.org' 'time.*.com' 'time.*.gov' \
         '+.market.xiaomi.com' '+.push.apple.com' 'localhost.ptlogin2.qq.com' '+.stun.*.*' '+.stun.*.*.*'; do
	uci add_list nikki.mixin.fake_ip_filters="$d"
done

# ── DNS：国内交给 AdGuard Home（保留去广告），国外 DoH 走代理 ──
set_ns() { # type enabled servers...
	local t=$1 en=$2 s; shift 2
	s=$(uci show nikki | sed -n "s/^nikki\.\(@nameserver\[[0-9]*\]\)\.type='$t'$/\1/p" | head -1)
	[ -n "$s" ] || return 0
	uci set "nikki.$s.enabled=$en"
	uci -q delete "nikki.$s.nameserver" || true
	for x in "$@"; do uci add_list "nikki.$s.nameserver=$x"; done
}
set_ns default-nameserver 1 '223.5.5.5' '119.29.29.29'
set_ns nameserver 1 '127.0.0.1:53'
set_ns proxy-server-nameserver 1 'https://223.5.5.5/dns-query' 'https://1.12.12.12/dns-query'
set_ns direct-nameserver 0 '127.0.0.1:53'
for s in $(uci show nikki | sed -n "s/^nikki\.\(@nameserver_policy\[[0-9]*\]\)=nameserver_policy$/\1/p"); do
	case "$(uci get nikki.$s.matcher)" in
	'geosite:private,cn')
		uci -q delete "nikki.$s.nameserver" || true
		uci add_list "nikki.$s.nameserver=127.0.0.1:53" ;;
	'geosite:geolocation-!cn')
		uci -q delete "nikki.$s.nameserver" || true
		uci add_list "nikki.$s.nameserver=https://1.1.1.1/dns-query#🚀 节点选择"
		uci add_list "nikki.$s.nameserver=https://8.8.8.8/dns-query#🚀 节点选择" ;;
	esac
done
uci set nikki.mixin.dns_nameserver='1'
uci set nikki.mixin.dns_nameserver_policy='1'
uci set nikki.mixin.proxy_server_nameserver_policy='0'

# ── 防"代理套代理"：连本订阅节点服务器的流量一律直连（置于订阅规则之前）──
/etc/nikki/scripts/node-direct.sh

uci set nikki.mixin.selection_cache='1'
uci set nikki.config.enabled='1'
uci commit nikki
echo NIKKI_CONFIGURED

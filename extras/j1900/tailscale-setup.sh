#!/bin/sh
# Tailscale：在外面访问路由器和两个网段；可作出口节点（在外面用校园网出口）
#   用法：sh tailscale-setup.sh   → 打印登录链接，在浏览器里登录后脚本才结束
#   登录后到 Tailscale 后台 → Machines → 本机：
#     Edit route settings：勾选两个网段和 Use as exit node；Disable key expiry
#   国内直连官方中转很慢，自建中转见 derper/README.md
set -e
apk add -q tailscale

# tailscale0 单独一个区域：可访问路由器本身、两个网段，以及作为出口节点上网
uci -q delete firewall.tailscale || true
for f in ts_lan ts_lanct ts_wan; do uci -q delete firewall.$f || true; done
uci set firewall.tailscale=zone
uci set firewall.tailscale.name='tailscale'
uci set firewall.tailscale.device='tailscale0'
uci set firewall.tailscale.input='ACCEPT'
uci set firewall.tailscale.output='ACCEPT'
uci set firewall.tailscale.forward='ACCEPT'
for d in lan lanct wan; do
	uci set firewall.ts_$d=forwarding
	uci set firewall.ts_$d.src='tailscale'
	uci set firewall.ts_$d.dest="$d"
done
uci commit firewall
fw4 -q reload

/etc/init.d/tailscale enable
/etc/init.d/tailscale start
sleep 3

# 不接管 DNS（路由器用自己的 AGH），不接收别人发布的网段（避免影响策略路由）
tailscale up --hostname=j1900 \
	--advertise-routes=192.168.31.0/24,192.168.32.0/24 \
	--advertise-exit-node \
	--accept-dns=false --accept-routes=false
tailscale status

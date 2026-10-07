#!/bin/sh
# 从订阅中提取节点服务器 IP，生成 Nikki 前置规则：IP-CIDR,<ip>/32,DIRECT,no-resolve
# 作用：白名单设备自己也开 Clash 时，它连节点的流量不再被路由器二次代理
# 只替换本脚本生成的规则（option tag 'node-direct'），其它自定义规则保留
# 订阅文件路径可用第一个参数指定，默认取订阅目录下第一个 yaml
SUB=${1:-$(ls /etc/nikki/subscriptions/*.yaml 2>/dev/null | head -1)}
[ -n "$SUB" ] && [ -f "$SUB" ] || exit 0
# 逐条删除（每删一条重新查找，避免 @rule[N] 下标前移导致漏删）
# 删除对象：本脚本生成的（tag=node-direct）+ 旧版本生成的无 tag IP-CIDR DIRECT 规则
find_one() {
	local i=0
	while uci -q get "nikki.@rule[$i]" >/dev/null; do
		t=$(uci -q get "nikki.@rule[$i].tag")
		if [ "$t" = "node-direct" ] || { [ -z "$t" ] && [ "$(uci -q get nikki.@rule[$i].type)" = "IP-CIDR" ] && [ "$(uci -q get nikki.@rule[$i].node)" = "DIRECT" ]; }; then
			echo "@rule[$i]"; return 0
		fi
		i=$((i + 1))
	done
	return 1
}
while s=$(find_one); do uci delete "nikki.$s"; done
awk '/^proxies:/{p=1;next} /^[a-z-]+:/{p=0} p' "$SUB" | grep -oE 'server: *[0-9.]+' | grep -oE '[0-9.]+$' | sort -u | while read ip; do
	s=$(uci add nikki rule)
	uci set "nikki.$s.enabled=1"
	uci set "nikki.$s.tag=node-direct"
	uci set "nikki.$s.type=IP-CIDR"
	uci set "nikki.$s.matcher=$ip/32"
	uci set "nikki.$s.node=DIRECT"
	uci set "nikki.$s.no_resolve=1"
done
uci set nikki.mixin.rule='1'
uci commit nikki
echo "node-direct: $(uci show nikki | grep -c "tag='node-direct'") rules"

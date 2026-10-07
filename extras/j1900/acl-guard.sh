#!/bin/sh
# Nikki 白名单保护：没有填 IP / IP6 / MAC 的访问控制条目会匹配"所有设备"，
# 若其开启了 DNS 或代理，自动停用并重启 nikki，防止误把全家都送进代理
changed=0
i=0
while uci -q get "nikki.@lan_access_control[$i]" >/dev/null; do
	s="nikki.@lan_access_control[$i]"
	if [ "$(uci -q get $s.enabled)" = "1" ] && [ -z "$(uci -q get $s.ip)$(uci -q get $s.ip6)$(uci -q get $s.mac)" ] \
	   && { [ "$(uci -q get $s.proxy)" = "1" ] || [ "$(uci -q get $s.dns)" = "1" ]; }; then
		uci set "$s.enabled=0"
		changed=1
		logger -t nikki-acl-guard "disabled lan_access_control[$i]: no ip/mac set (would match ALL devices)"
	fi
	i=$((i + 1))
done
if [ "$changed" = 1 ]; then
	uci commit nikki
	/etc/init.d/nikki restart >/dev/null 2>&1
fi

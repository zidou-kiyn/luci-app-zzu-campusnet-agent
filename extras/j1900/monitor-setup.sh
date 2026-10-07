#!/bin/sh
# 监控：vnstat2（按天/月流量）+ luci-app-statistics（历史曲线）+ 每条线路延迟 + 系统日志写硬盘
#   前提：已运行 data-disk.sh（/mnt/data 已挂载）；lineping、lineping-collectd.sh 已传到 /root/
#   查看：LuCI → 状态 → vnStat 流量监控；LuCI → 统计 → 图表（Ping 页 = 4 条线路的延迟 / 丢包）
set -e
D=/mnt/data
grep -q " $D " /proc/mounts || { echo "$D 未挂载，先运行 data-disk.sh"; exit 1; }
for f in lineping lineping-collectd.sh; do [ -f /root/$f ] || { echo "缺少 /root/$f"; exit 1; }; done
mkdir -p $D/log $D/vnstat $D/rrd

apk add -q vnstat2 luci-app-vnstat2 luci-i18n-vnstat2-zh-cn \
	luci-app-statistics luci-i18n-statistics-zh-cn \
	collectd-mod-cpu collectd-mod-load collectd-mod-memory collectd-mod-interface \
	collectd-mod-thermal collectd-mod-conntrack collectd-mod-exec

# ── 每条线路延迟 ──
# collectd 自带 ping 插件只能走一个出口；exec 插件又不允许以 root 运行，而 busybox ping 需要 root。
# 所以由 root 守护进程 lineping 按源地址分别 ping，结果写 /var/run/lineping/，
# 再由 exec 插件（nobody）读出，以 ping 插件的格式上报，LuCI 的 Ping 图直接能画。
cp /root/lineping /usr/sbin/lineping
mkdir -p /usr/libexec/collectd
cp /root/lineping-collectd.sh /usr/libexec/collectd/lineping.sh
chmod +x /usr/sbin/lineping /usr/libexec/collectd/lineping.sh
cat > /etc/init.d/lineping <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
	procd_open_instance
	procd_set_param command /usr/sbin/lineping 223.5.5.5
	procd_set_param respawn
	procd_close_instance
}
EOF
chmod +x /etc/init.d/lineping
/etc/init.d/lineping enable
/etc/init.d/lineping restart

# ── luci-app-statistics ──
S=luci_statistics
uci set $S.collectd_rrdtool.DataDir="$D/rrd"
uci set $S.collectd_rrdtool.RRARows='300'
uci set $S.collectd_interface.enable='1'
uci -q delete $S.collectd_interface.Interfaces || true
for i in wancm1 wancm2 wanct1 wanct2 br-lan br-lanct; do uci add_list $S.collectd_interface.Interfaces=$i; done
uci set $S.collectd_interface.IgnoreSelected='0'
uci set $S.collectd_iwinfo.enable='0'          # J1900 没有无线
uci set $S.collectd_thermal.enable='1'
uci set $S.collectd_conntrack.enable='1'
uci set $S.collectd_ping.enable='0'
uci set $S.collectd_exec.enable='1'
while uci -q delete $S.@collectd_exec_input[0]; do :; done
uci add $S collectd_exec_input >/dev/null
uci set $S.@collectd_exec_input[-1].cmdline='/usr/libexec/collectd/lineping.sh'
uci set $S.@collectd_exec_input[-1].cmduser='nobody'
uci set $S.@collectd_exec_input[-1].cmdgroup='nogroup'
uci commit $S
/etc/init.d/luci_statistics enable
/etc/init.d/collectd enable
/etc/init.d/collectd restart

# ── vnstat2 ──
sed -i "s|^;\?DatabaseDir .*|DatabaseDir \"$D/vnstat\"|" /etc/vnstat.conf
uci -q delete vnstat.@vnstat[0].interface || true
for i in wancm1 wancm2 wanct1 wanct2 br-lan br-lanct; do uci add_list vnstat.@vnstat[0].interface=$i; done
uci commit vnstat
/etc/init.d/vnstat enable
/etc/init.d/vnstat restart

# ── 系统日志写硬盘：文件到 50MB 轮转为 .old（最多约 100MB）；内存缓冲 4MB ──
# cron 例行执行不再记日志（原来占日志的一大半），出错仍会记
logread >> $D/log/messages      # 重启 logd 会清空内存缓冲，先存下来
uci set system.@system[0].log_file="$D/log/messages"
uci set system.@system[0].log_size='51200'
uci set system.@system[0].log_buffer_size='4096'
uci set system.@system[0].cronloglevel='9'
uci commit system
/etc/init.d/log restart
/etc/init.d/cron restart

# ── 升级时保留 ──
for f in /usr/sbin/lineping /usr/libexec/collectd/lineping.sh /etc/init.d/lineping /etc/vnstat.conf; do
	grep -qx "$f" /etc/sysupgrade.conf || echo "$f" >> /etc/sysupgrade.conf
done
echo MONITOR_DONE

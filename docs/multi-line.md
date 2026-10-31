# 多线路部署

郑大校园网允许**同一账号在多个 IP 上同时在线且运营商不同**，所以一根网线就能接出多条线路，再按运营商分组做多路聚合。

完整实例（J1900 软路由做主路由 + Redmi AX5400 纯 AP，联通 ×2 + 电信 ×2）见 [extras/j1900/](../extras/j1900/README.md)：

```
校园网网线 → eth1 ┬ wancm1 / wancm2（macvlan）联通组 → main  表 ← 31 网段
                  └ wanct1 / wanct2（macvlan）电信组 → wanct 表 ← 32 网段（VLAN 32）
```

## 要点

| 项 | 说明 |
|----|------|
| macvlan | 每条线路一个独立 MAC，DHCP 拿到独立的校园网 IP；MAC 固定则续租 IP 不变。SQM 挂在各 macvlan 上才能分线路限速 |
| 每线一张路由表 | netifd `ip4table` 会自动加 `from <线路 IP> lookup <线路表>`，保证路由器自身发出的包源 IP 与出口一致。校园网按 MAC 识别会话，不一致时认证请求会算到另一条线上（看门狗误判、登录串号） |
| 组表 | 只放多路默认路由，由 [`extras/99-multipath`](../extras/99-multipath)（装到 `/etc/hotplug.d/iface/99-multipath`）在线路上下线时重建；nexthop 用 `onlink`。分组写在脚本末尾的 `GROUPS`。插件的故障摘除与组间兜底也通过它生效 |
| 多路哈希 | `fib_multipath_hash_policy=1` 按连接分摊，多线程下载可叠加；同组线路出口 IP 相同，换线不会掉网站登录 |
| 策略路由 | `lookup main suppress_prefixlength 0`（局域网互访先查 main，但不用它的默认路由）；`iif lanct from 192.168.32.0/24 lookup wanct` |
| ARP | 各线路 `arp_ignore=1`、`arp_announce=2`、`rp_filter=2`，防止同网段多出口 ARP 串线（否则认证服务器看到的 MAC 会错） |

插件这边：每条线路在「认证线路」表格里选好出口接口（`iface`）和运营商即可。

netifd 停止时不会删除 macvlan，残留设备会导致同名设备认领失败（`DEVICE_CLAIM_FAILED`）或新设备套不上原 MAC。重启网络时先 `network stop`，删掉各线路设备再 `start`（见 `extras/j1900/j1900-apply.sh`）。

## 关闭 IPv6

郑大校园网的 IPv6 免认证，且统一走中国移动出口（前缀 `2409:87xx`）。实测多连接总速率被限在约 120 Mbps（单连接约 25 Mbps）。不关的话，连“电信” WiFi 的设备也会优先走移动 v6。

```sh
uci set dhcp.lan.ra='disabled'; uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.@dnsmasq[0].filter_aaaa='1'          # 不给客户端返回 AAAA
uci commit dhcp; /etc/init.d/odhcpd stop; /etc/init.d/odhcpd disable; /etc/init.d/dnsmasq reload
uci set network.wan6.disabled='1'; uci -q delete network.lan.ip6assign; uci -q delete network.globals.ula_prefix
uci commit network; /etc/init.d/network reload
```

客户端已有的 v6 地址要重连 WiFi 后才会消失。

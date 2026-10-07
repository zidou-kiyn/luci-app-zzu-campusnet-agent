# 实例：J1900 软路由 + Redmi AX5400 AP

```
校园网 ── J1900 软路由（主路由，4 线认证 + 聚合）── Redmi AX5400（纯 AP）── 终端
```

J1900（ImmortalWrt x86-64，内核 6.18）在一根校园网网线上跑 4 条认证线路（联通 ×2 + 电信 ×2），
按运营商分组聚合；Redmi AX5400（ImmortalWrt，内核 6.12）退为纯 AP，只发 WiFi。
下面是实际在用的配置脚本。账号、密码、MAC、设备名已去除，改用占位符或环境变量。

## 拓扑

```
校园网网线 → J1900 eth1（WAN）
               ├ 联通1 wancm1 ┐ 联通组（main 表）← 31 网段、路由器自身
               ├ 联通2 wancm2 ┘
               ├ 电信1 wanct1 ┐ 电信组（wanct 表）← 32 网段
               └ 电信2 wanct2 ┘
             J1900 eth0（LAN）→ AX5400 WAN 口
               不带 tag  = 31 网段 lan
               VLAN 32   = 32 网段 lanct
Redmi AX5400（纯 AP）
   Lyra-5G、LAN1~3 → 31 网段（联通）
   Lyra-2.4G       → 32 网段（电信）
```

## 地址

| 地址 | 说明 |
|---|---|
| 192.168.31.1 | J1900：网关 / DNS / LuCI（主机名 `Lyra`） |
| 192.168.32.1 | J1900 在 32 网段的地址 |
| 192.168.1.1 | J1900 救援地址（与 31.1 同一网口）。配置出错时电脑手动设 `192.168.1.100/24` 即可登录，**不要删除** |
| 192.168.31.2 | AX5400 管理地址 |
| 192.168.31.1:3000 | AdGuard Home |
| 100.x.x.x | J1900 的 Tailscale 地址（在外面访问路由器） |

## 文件

| 文件 | 运行位置 | 作用 |
|---|---|---|
| `j1900-setup.sh` | J1900 | 写入全部配置（网段、VLAN、4 条 macvlan 线路、策略路由、防火墙、DHCP、sysctl、`99-multipath`、插件配置），不立即生效 |
| `../99-multipath` | J1900 | 组表多路默认路由 hotplug（联通组 → main，电信组 → wanct），由 `j1900-setup.sh` 装到 `/etc/hotplug.d/iface/` |
| `j1900-apply.sh` | J1900 | 后台应用上面的配置，等 4 条线路拿到 IP 后重启防火墙 / DNS / 插件（日志 `/tmp/apply.log`） |
| `j1900-dhcp-on.sh` | J1900 | 切换时延时 20 秒打开 31 网段 DHCP（等 AX5400 先变成 AP） |
| `zzucampusnetagent.example` | J1900 | 插件配置示例（4 线），填好后传到 `/tmp/zzucampusnetagent.cfg` |
| `agh-front.sh` | J1900 | AdGuard Home 直接监听 :53，dnsmasq 让到 :54；加 DNS 劫持规则 |
| `sqm.example` | J1900 | `/etc/config/sqm`：只给电信两线限下载 124M（cake，nat dual-dsthost） |
| `speedtest.sh` | J1900 | 多线路同时测速：`sh speedtest.sh 10 4 wancm1 wancm2` |
| `xiaomi-ap.sh` | AX5400 | 改成纯 AP：停用路由类服务、WAN 口并入网桥、VLAN 32、管理地址 31.2 |
| `data-disk.sh` | J1900 | 系统盘剩余空间分成 ext4 数据分区，挂到 `/mnt/data`（不动现有分区、不重启） |
| `monitor-setup.sh` | J1900 | 装 vnstat2 + luci-app-statistics，配好每条线路延迟曲线；系统日志改写到硬盘 |
| `lineping` / `lineping-collectd.sh` | J1900 | 每 30 秒分别从 4 条线路 ping，结果交给 collectd 画在「统计 → 图表 → Ping」里；由 `monitor-setup.sh` 安装 |
| `tailscale-setup.sh` | J1900 | 装 Tailscale、加防火墙区域，发布两个网段和出口节点 |
| `derper/` | 香港 / 国内服务器 | 自建 Tailscale 中转（Docker Compose，香港用 Let's Encrypt、国内用已有证书），校园网端口限制的绕法见 [derper/README.md](derper/README.md) |
| `irq-pin.sh` | AX5400 | 中断固定：CPU0 = 有线 + 2.4G，CPU1 = 5G。装到 `/usr/sbin/irq-pin.sh`，由 `rc.local` 开机执行 |

## 部署步骤

```sh
# 1. J1900 刷好 ImmortalWrt、装好本插件和 kmod-macvlan（此时旧路由器还是主路由，J1900 用 192.168.1.1）
scp extras/99-multipath extras/j1900/*.sh root@192.168.1.1:/root/
scp zzucampusnetagent.cfg root@192.168.1.1:/tmp/zzucampusnetagent.cfg   # 由 .example 填好
# 可选：沿用旧路由器的 MAC（校园网 IP 不变），以及静态租约 /root/hosts.txt（每行：名称 IP MAC）
ssh root@192.168.1.1 'MAC_WANCT1=.. MAC_WANCT2=.. MAC_WANCM1=.. MAC_WANCM2=.. sh /root/j1900-setup.sh'
ssh root@192.168.1.1 'nohup sh /root/j1900-apply.sh &'

# 2. 切换：J1900 打开 DHCP，AX5400 变 AP，然后改接网线（校园网 → J1900 eth1，J1900 eth0 → AX5400 WAN）
scp extras/j1900/xiaomi-ap.sh extras/j1900/irq-pin.sh root@<AX5400>:/root/
ssh root@192.168.1.1 'nohup sh /root/j1900-dhcp-on.sh &'
ssh root@<AX5400> 'nohup sh /root/xiaomi-ap.sh &'

# 3. J1900 装好 AdGuard Home 后
ssh root@192.168.31.1 sh /root/agh-front.sh
# SQM：装 luci-app-sqm 后按 sqm.example 写 /etc/config/sqm

# 4. 可选：数据分区 + 监控 + 日志写硬盘
scp extras/j1900/{data-disk.sh,monitor-setup.sh,lineping,lineping-collectd.sh} root@192.168.31.1:/root/
ssh root@192.168.31.1 'sh /root/data-disk.sh && sh /root/monitor-setup.sh'

# 5. 可选：Tailscale（会打印登录链接；自建中转见 derper/README.md）
scp extras/j1900/tailscale-setup.sh root@192.168.31.1:/root/
ssh root@192.168.31.1 sh /root/tailscale-setup.sh
```

AX5400 上的校园网插件、AdGuard Home、SQM 等软件包，切换后可以在 LuCI → 系统 → 软件包里卸载。

## J1900 上运行的服务

| 服务 | 说明 |
|---|---|
| 校园网插件 | 4 线认证、5 秒看门狗、外网检测、故障线路摘除；06:00 全部重认证，00:30 联通两线额外重认证；设备监控（lan + lanct，保留 30 天） |
| 多线聚合 | `/etc/hotplug.d/iface/99-multipath`，按连接哈希（`fib_multipath_hash_policy=1`） |
| AdGuard Home | 监听 :53，上游阿里 / 腾讯 DoH + DoT，`.lan` 和反查交给 `127.0.0.1:54`；规则 AdGuard DNS filter + anti-AD |
| dnsmasq | 端口 **54**，只做 DHCP 和 `.lan` 本地解析；**`dns_redirect` 必须为 0**（否则查询被劫持到 54，返回 REFUSED） |
| DNS 劫持 | 防火墙 `Hijack-DNS-lan` / `Hijack-DNS-lanct`：发往其他服务器的明文 53 → AdGuard（DoH / DoT 不受影响） |
| 防火墙 | 软件 + 硬件流量卸载、FullCone NAT |
| SQM | 只给电信两线限下载 124M；联通和上传不限速 |
| irqbalance | 开启 |
| 数据分区 | 系统盘剩余约 28G → `/mnt/data`（ext4），存日志、vnstat、统计数据 |
| 系统日志 | 写 `/mnt/data/log/messages`，50MB 轮转一次；cron 例行执行不记日志 |
| vnstat2 | 4 条线路 + 两个网段，按小时 / 天 / 月统计流量 |
| luci-app-statistics | CPU、负载、内存、温度、连接数、各接口流量；`lineping` 提供每条线路到 223.5.5.5 的延迟 / 丢包 |
| Tailscale | 发布 31 / 32 网段、校园内网 172.16.0.0/16、校内 OJ 10.67.4.89 + 出口节点；不接管 DNS、不接收别人的路由；中转用自建香港 + 国内 DERP（见 derper/） |

AX5400 只运行 WiFi / 网桥 / LuCI / SSH / NTP，DHCP、DNS、防火墙都已停用，irqbalance 由 `irq-pin.sh` 代替。
校园网插件已经卸载，所以它**不能**再直接当路由器用。

## 实测带宽（iperf3，Mbps；对端是上限 500M 的香港节点）

| | 下行 | 上行 |
|---|---|---|
| 联通单线 | 358~416 | 190~220 |
| 联通聚合 | ≥456（受对端限制） | 218 |
| 电信单线 | 126 | 25 |
| 电信聚合 | 252 | 50 |

## 未做

- 跨运营商自动切换（联通整组断时 31 网段临时走电信）
- IPv6

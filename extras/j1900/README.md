# J1900 主路由 + 小米 AX5400 AP 部署实例

一台 J1900 软路由（ImmortalWrt x86-64）做主路由：一根校园网网线上跑 4 条认证线路（联通 ×2 + 电信 ×2）、
按运营商分组多线聚合；小米 AX5400（ImmortalWrt）退为纯 AP。下面是实际在用的配置脚本，可作参考。

> 账号、密码、MAC、设备名等已去除，用占位符或环境变量代替。

## 拓扑

```
校园网网线 → J1900 eth1（WAN）
               ├ 联通1 wancm1 ┐ 联通组（main 表）← 31 网段、路由器自身
               ├ 联通2 wancm2 ┘
               ├ 电信1 wanct1 ┐ 电信组（wanct 表）← 32 网段
               └ 电信2 wanct2 ┘
             J1900 eth0（LAN）→ 小米 WAN 口
               不带 tag  = 31 网段 lan
               VLAN 32   = 32 网段 lanct
小米 AX5400（纯 AP）
   Lyra-5G、LAN1~3 → 31 网段（联通）
   Lyra-2.4G       → 32 网段（电信）
```

## 地址

| 地址 | 说明 |
|---|---|
| 192.168.31.1 | J1900：网关 / DNS / LuCI |
| 192.168.32.1 | J1900 在 32 网段的地址 |
| 192.168.1.1 | J1900 救援地址（与 31.1 同一网口）。配置出错时电脑手动设 `192.168.1.100/24` 即可登录，**不要删除** |
| 192.168.31.2 | 小米 AP 管理地址 |
| :3000 | AdGuard Home |

## 文件

| 文件 | 运行位置 | 作用 |
|---|---|---|
| `j1900-setup.sh` | J1900 | 写入全部配置（网段、VLAN、4 条 macvlan 线路、策略路由、防火墙、DHCP、sysctl、`99-multipath`、插件配置），不立即生效 |
| `j1900-apply.sh` | J1900 | 后台应用上面的配置，等 4 条线路拿到 IP 后重启防火墙/DNS/插件（日志 `/tmp/apply.log`） |
| `j1900-dhcp-on.sh` | J1900 | 切换时延时 20 秒打开 31 网段 DHCP（等小米先变成 AP） |
| `zzucampusnetagent.example` | — | 插件配置示例（4 线），填好后传到 `/tmp/zzucampusnetagent.cfg` |
| `agh-front.sh` | J1900 | AdGuard Home 直接监听 :53，dnsmasq 让到 :54；加 DNS 劫持规则 |
| `sqm.example` | J1900 | `/etc/config/sqm`：仅电信两线下载限速 124M（cake nat dual-dsthost） |
| `nikki-setup.sh` | J1900 | Nikki（mihomo）白名单模式：只代理指定设备，国内直连，DNS 交给 AGH |
| `node-direct.sh` | J1900 | 从订阅提取节点 IP 生成直连规则，防止设备自开代理时被二次代理 |
| `acl-guard.sh` | J1900 | Nikki 访问控制里没填 IP/MAC 的条目会匹配所有设备，自动停用 |
| `speedtest.sh` | J1900 | 多线路同时测速：`sh speedtest.sh 10 4 wancm1 wancm2` |
| `xiaomi-ap.sh` | 小米 | 把小米改成纯 AP（停服务、WAN 口并入网桥、VLAN 32、管理地址 31.2） |
| `xiaomi-irq.sh` | 小米 | IPQ5018 中断固定：CPU0 = 有线 + 2.4G，CPU1 = 5G（放进 `rc.local`） |

## 部署步骤

```sh
# 1. J1900 刷好 ImmortalWrt、装好本插件后（此时小米还是主路由）
scp extras/j1900/*.sh root@192.168.1.1:/root/
scp zzucampusnetagent.cfg root@192.168.1.1:/tmp/zzucampusnetagent.cfg   # 由 .example 填好
# 可选：沿用旧路由器 MAC（校园网 IP 不变），以及静态租约 /root/hosts.txt（每行：名称 IP MAC）
ssh root@192.168.1.1 'MAC_WANCT1=.. MAC_WANCT2=.. MAC_WANCM1=.. MAC_WANCM2=.. sh /root/j1900-setup.sh'
ssh root@192.168.1.1 'nohup sh /root/j1900-apply.sh &'

# 2. 切换：J1900 打开 DHCP，小米变 AP，网线改接（校园网 → J1900 eth1，J1900 eth0 → 小米 WAN）
ssh root@192.168.1.1 'nohup sh /root/j1900-dhcp-on.sh &'
ssh root@<小米> 'nohup sh /root/xiaomi-ap.sh &'

# 3. 装 AdGuard Home 后
ssh root@192.168.31.1 sh /root/agh-front.sh
```

## J1900 上运行的服务

| 服务 | 说明 |
|---|---|
| 校园网插件 | 4 线认证、5 秒看门狗、故障线路摘除；06:00 全部重认证，00:30 联通重认证 |
| 多线聚合 | `/etc/hotplug.d/iface/99-multipath`，按连接哈希（`fib_multipath_hash_policy=1`） |
| AdGuard Home | 监听 :53，上游阿里/腾讯 DoH + DoT（并行），`[/lan/]127.0.0.1:54`，反查也交给 :54；规则 AdGuard DNS filter + anti-AD |
| dnsmasq | 端口 **54**，只做 DHCP 和 `.lan` 本地解析；**`dns_redirect` 必须为 0**（否则查询被劫持到 54 导致 REFUSED） |
| DNS 劫持 | 防火墙 `Hijack-DNS-lan` / `Hijack-DNS-lanct`：发往其他服务器的明文 53 → AdGuard（DoH/DoT 不受影响） |
| SQM | 仅电信两线下载 124M；联通与上传不限速 |
| irqbalance | 开启 |

小米 AP 只运行 WiFi / 网桥 / LuCI / SSH / NTP；DHCP、DNS、防火墙均已停用，校园网插件已卸载（不能再直接当路由器用）。

## 实测带宽（iperf3，对端为 500M 上限的香港节点，Mbps）

| | 下行 | 上行 |
|---|---|---|
| 联通单线 | 358~416 | 190~220 |
| 联通聚合 | ≥456（受对端限制） | 218 |
| 电信单线 | 126 | 25 |
| 电信聚合 | 252 | 50 |

## 未做

- 跨运营商自动切换（联通整组断时 31 网段临时走电信）
- IPv6

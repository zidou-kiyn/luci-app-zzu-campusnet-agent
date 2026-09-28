# luci-app-zzu-campusnet-agent — 郑大校园网状态 / 认证 LuCI 插件

为 **ImmortalWrt（内核 6.12.89）** 编写的极轻量 LuCI 插件，挂在 LuCI **服务** 菜单下：

- 🟢 每 **10 秒** 自动查询并显示在线状态（账号 / 运营商 / 时长 / IP），带 **手动刷新** 按钮
- 🔑 **一键登录 / 注销**（portal 认证）
- ⏰ **每天定时重新授权**：到点若在线则先注销、隔 1 秒再登录，保证授权不掉线（默认凌晨 06:00）
- 🔀 **多线路**：同一账号在不同出口**同时**登录不同运营商（如电信日常 + 移动下载），每条线路独立显示状态、独立登录/注销
- 🩺 **掉线自动重登**：定期检查所有线路，发现离线自动重新认证
- ⚙ **UI 内可改**：服务器地址 baseurl、账号、密码、运营商（移动/联通/电信/校园网/学科专网）、定时开关与时间
- 🎨 Argon Design 配色卡片风，贴近 argon 主题

## 它有多轻量

- **零新增常驻进程**：抓取逻辑只在被调用时跑（LuCI 轮询 / cron 触发），平时不占内存。
- **零额外依赖**：只用系统自带 `uclient-fetch`/`curl`、`jsonfilter`、`jshn`、`awk`、`cron`。
  密码的 base64 与 URL 编码内置纯 `awk` 兜底实现。
- **磁盘占用 < 30 KB**。

## 工作原理

路由器 WAN 已拨入郑大校园网，eportal 按**来源 IP** 识别用户，所以由路由器自身请求即可。
- 查询 `http://<baseurl>:801/eportal/portal/custom`
- 登录 `http://<baseurl>:801/eportal/portal/login?user_account=,0,<账号><运营商后缀>&user_password=<密码base64并URL编码>`
- 注销 `http://<baseurl>:801/eportal/portal/logout`

账号密码只在路由器内部使用，**不经过浏览器**。

多线路时，每条线路绑定一个 netifd 接口，请求用 `curl --interface <该接口IP>` 发出，
认证服务器据此把不同 IP 分别认证为不同运营商。

---

## 双运营商分流（电信日常 + 移动下载）

实测郑大校园网允许**同一账号在两个 IP 上同时在线且运营商不同**。一根网线即可实现：

```
                    ┌─ wan   (原 MAC, 10.172.a.b) ── 电信 ── OpenWrt-2.4G / OpenWrt-5G / 有线 LAN (192.168.31.0/24)
校园网网线 ── wan ──┤
                    └─ wancm (macvlan, 10.172.c.d) ── 移动 ── OpenWrt-CMCC-5G (192.168.32.0/24)
```

一键配置（在路由器上，需已装本插件；依赖 `kmod-macvlan`、`curl`）：

```sh
scp extras/dual-isp-setup.sh root@192.168.31.1:/root/
ssh root@192.168.31.1 sh /root/dual-isp-setup.sh          # 安装
ssh root@192.168.31.1 sh /root/dual-isp-setup.sh remove   # 移除
# 可用环境变量改默认值：SSID / RADIO / SUBNET / ISP / NAME / KEY / ENC / MAC / DOH1_URL / DOH2_URL ...
```

脚本做了这些事：

| 项 | 说明 |
|----|------|
| macvlan `wancm` | 在 `wan` 上建第二个 MAC，DHCP 拿第二个校园网 IP；MAC 固定，续租 IP 不变 |
| 路由表 `cmcc`(100) | `wancm` 的路由只进这张表，主线路默认路由不受影响 |
| 策略路由 | 从移动 WiFi 进来（`iif br-cmcc`）的 `192.168.32.0/24` 查 `cmcc` 表；表空（移动断线）时**直接不可达、不回落电信**。必须限定 iif，否则路由器发给客户端的 DNS 应答也会被送去 WAN |
| `suppress_prefixlength` 规则 | 修正 netifd 自动加的 `to 10.172.0.0/16 lookup cmcc`，防止主线路 DHCP 续租等内网流量错走移动 |
| `arp_ignore=1 / arp_announce=2` | 同网段双出口防 ARP 串线（否则认证服务器看到的 MAC 会错） |
| 防火墙 | 新区域 `cmcc` → `wan`（`wancm` 加入 wan 区域做 NAT），与主 LAN 隔离 |
| DNS | 移动网段用**独立 dnsmasq 实例**（`dhcp.cmcc`），上游为经移动出口的**公共加密 DNS**（阿里 / 腾讯 DoH），CDN 按移动调度。详见下方 |
| DHCP | 由移动 dnsmasq 实例提供，客户端 DNS 即路由器（`192.168.32.1`） |
| WiFi | 5G 射频上新增 `OpenWrt-CMCC-5G`，密码沿用该射频原 WiFi；支持时用 WPA2/WPA3 混合（`ENC` 可覆盖）；网桥使用独立 MAC（不能与 WiFi 接口/BSSID 相同） |
| 插件 | 添加额外线路 `wancm`（@cmcc），开启掉线自动重登 |

> 说明：没有外部服务器时，**单个连接无法叠加两条线路带宽**；这里是按 WiFi 固定分流。

### 两个网段各自的加密 DNS

```
电信局域网 → dnsmasq 主实例 → https-dns-proxy :5053/:5054（用户 nobody）  → 电信出口 → 阿里/腾讯 DoH
移动 WiFi  → dnsmasq cmcc 实例 → https-dns-proxy :5055/:5056（用户 dnscmcc）→ 移动出口 → 阿里/腾讯 DoH
```

- 移动的两个 DoH 进程以专用用户 `dnscmcc`（uid 6053）运行，策略规则 `uidrange 6053 lookup cmcc`
  让它们的流量走移动出口；按用户而非 IP 匹配，`wancm` 换 IP 也无需改配置。移动断线时该用户流量不可达，不会漏到电信
- DoH 服务端看到的是移动出口 IP，因此返回移动的 CDN 节点（实测 `dldir1.qq.com`：电信实例 → `123.54.x`，移动实例 → `111.42.x`）
- https-dns-proxy 默认会把**所有** DoH 进程写进**所有** dnsmasq 实例，脚本将其 `dnsmasq_config_update` 设为 `-`（不自动改写），
  两个实例的上游各自固定
- 两个实例都开启 `all-servers`（并发问两家取最快）与 `use-stale-cache`（缓存过期先返回再后台刷新）
- 未安装 https-dns-proxy 时，移动实例退化为绑定 `wancm` 的明文公共 DNS（`223.5.5.5@wancm`）

可选：给主实例也加上缓存 / 并发优化（日志出现 `Maximum number of concurrent DNS queries reached` 时建议）：

```sh
uci set dhcp.@dnsmasq[0].cachesize='10000'; uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'
uci set dhcp.@dnsmasq[0].extraconftext='all-servers\nuse-stale-cache=3600'
uci commit dhcp; /etc/init.d/dnsmasq restart
```

### 分线路限速（SQM）

macvlan 的流量会先经过父设备 `wan` 的 tc ingress，SQM 挂在 `wan` 或物理口上会把两条线路算在一起。
`extras/dual-isp-sqm.sh` 把主线路也挪到 macvlan `wanct`（沿用原 WAN MAC，物理口换随机 MAC），
然后给 `wanct`、`wancm` 各建一个 cake 队列，并开启全核 RPS（`packet_steering=2`）：

```sh
scp extras/dual-isp-sqm.sh root@192.168.31.1:/root/
ssh root@192.168.31.1 "CT_DOWN=142000 CT_UP=50000 CM_DOWN=285000 CM_UP=50000 sh /root/dual-isp-sqm.sh"
ssh root@192.168.31.1 sh /root/dual-isp-sqm.sh remove    # 还原
```

速率建议取实测的 90%~95%，之后也可直接在 LuCI → 网络 → SQM QoS 里改。
主线路换设备后 DHCP 可能分到新 IP，脚本结尾会调用 `zzucampusnetagent watchdog` 立即补登。

> 性能参考（2 核 A53 @1GHz）：单线路跑满无压力；两条线同时满载时 CPU 基本吃满，
> 路由器本机测速总吞吐约 230M（不开 SQM 约 270M）。CPU 不够时可在 LuCI → 网络 → SQM QoS
> 把两个队列取消启用，或 `uci set sqm.wanct.enabled=0; uci set sqm.wancm.enabled=0; uci commit sqm; /etc/init.d/sqm stop`。

### 关闭 IPv6

郑大校园网的 IPv6 **免认证且统一走中国移动出口**（前缀 `2409:87xx` 属于移动），
实测多连接总速率被限在约 **120 Mbps**（两个不同 CDN 节点叠加仍是 ~123M，单连接约 25M）。
不关的话连"电信" WiFi 的设备也会优先用移动 v6。关闭方法：

```sh
uci set dhcp.lan.ra='disabled'; uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.@dnsmasq[0].filter_aaaa='1'          # 不给客户端返回 AAAA
uci commit dhcp; /etc/init.d/odhcpd stop; /etc/init.d/odhcpd disable; /etc/init.d/dnsmasq reload
uci set network.wan6.disabled='1'; uci -q delete network.lan.ip6assign; uci -q delete network.globals.ula_prefix
uci commit network; /etc/init.d/network reload
```

客户端已有的 v6 地址需重连 WiFi 后消失。

## 组件一览

| 文件 | 作用 |
|------|------|
| `/usr/sbin/zzucampusnetagent` | 核心 CLI：`status/query/login/logout/reauth/watchdog`，编码与解析都在这里 |
| `/usr/libexec/rpcd/luci.zzucampusnetagent` | rpcd 包装层，把上面三个动作暴露给 LuCI（ubus） |
| `/etc/init.d/zzucampusnetagent` | 按配置同步 cron 定时任务（procd reload 触发） |
| `/etc/config/zzucampusnetagent` | UCI 配置：`config` 段为共用账号 + 主线路；`line` 段为额外线路（iface/isp） |
| `extras/dual-isp-setup.sh` | （不随包安装）双运营商分流一键配置脚本 |
| `htdocs/.../view/zzucampusnetagent/status.js` | LuCI 前端：状态卡片 + 操作按钮 + 设置表单 |
| `menu.d` / `acl.d` | 菜单（服务下）与权限 |

---

## 安装方法零：从 Release 下载安装包（推荐）

[Releases](https://github.com/zidou-kiyn/luci-app-zzu-campusnet-agent/releases) 页面提供编译好的安装包。本插件**架构无关**（纯脚本），同一个包适用于所有平台，按系统版本选格式：

| 你的系统 | 包格式 | 安装命令 |
|----------|--------|----------|
| ImmortalWrt 25.12 / snapshot（新版，apk） | `*.apk` | `apk add --allow-untrusted /tmp/luci-app-zzu-campusnet-agent-*.apk` |
| ImmortalWrt 24.10 及更早（opkg） | `*.ipk` | `opkg install /tmp/luci-app-zzu-campusnet-agent_*_all.ipk` |

> 不确定用哪个？SSH 执行 `which apk` 有输出就用 apk，否则用 ipk。
> apk 包为本地编译、无官方签名，所以需要 `--allow-untrusted`。

```sh
# 示例：下载后传到路由器再安装
scp luci-app-zzu-campusnet-agent-*.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
apk add --allow-untrusted /tmp/luci-app-zzu-campusnet-agent-*.apk
```

---

## 安装（一键脚本，无需编译）

1. 把 `install.sh` 传到路由器（任选一种）：
   ```powershell
   # Windows PowerShell；把 192.168.1.1 换成你路由器 LAN 地址
   scp D:\CodePack\luci-app-zzu-campusnet-agent\install.sh root@192.168.1.1:/tmp/
   ```
   > 也可用 WinSCP 拖进 `/tmp/`，或在 LuCI 的 TTYD 终端里 `vi /tmp/install.sh` 粘贴。

2. SSH 登录路由器执行：
   ```sh
   ssh root@192.168.1.1
   sh /tmp/install.sh
   ```

3. 打开 LuCI → **服务 → ZZU CampusNet Agent**。
   首次使用：展开页面下方 **账号与认证设置** 填 **账号 / 密码 / 运营商** →【保存并应用】→ 再点 **🔑 登录**。
   开启 **每天定时重新授权** 并设好时间后，同样点【保存并应用】即生效（自动写入 cron）。

---

## 更新

更新 = **重新跑一遍 install.sh**。脚本会覆盖所有程序文件，但 **保留 `/etc/config/zzucampusnetagent` 里你填的账号、密码、运营商等设置**（升级时只补齐新增的配置项，不会清空旧值）。

```sh
# 1) 把新的 install.sh 传上去（覆盖旧的）
scp D:\CodePack\luci-app-zzu-campusnet-agent\install.sh root@192.168.1.1:/tmp/

# 2) SSH 登录后执行（与安装同一条命令）
ssh root@192.168.1.1
sh /tmp/install.sh
```

脚本结尾会自动：重启 `rpcd`、重新同步 cron、清空 LuCI 缓存。
最后在浏览器按 **Ctrl + F5** 强刷即可看到新版页面。无需重启路由器。

> 如果你是用 **方法二（手动拷贝）** 装的，更新就是把对应文件再覆盖一遍，然后执行：
> ```sh
> chmod +x /usr/sbin/zzucampusnetagent /usr/libexec/rpcd/luci.zzucampusnetagent /etc/init.d/zzucampusnetagent
> /etc/init.d/zzucampusnetagent enable; /etc/init.d/zzucampusnetagent restart
> /etc/init.d/rpcd restart
> rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache
> ```
> 若你是用 **方法三（ipk）** 装的，则 `opkg install --force-reinstall luci-app-zzu-campusnet-agent_*.ipk`。

**卸载：** `sh /tmp/install.sh uninstall`（会一并删除 cron 任务与配置）。

---

## 安装方法二：手动拷贝文件

把本目录文件按相同路径放到路由器，然后执行上面“手动拷贝更新”里的那几条生效命令：

| 本地文件 | 路由器目标路径 |
|----------|----------------|
| `htdocs/luci-static/resources/view/zzucampusnetagent/status.js` | `/www/luci-static/resources/view/zzucampusnetagent/status.js` |
| `root/usr/sbin/zzucampusnetagent` | `/usr/sbin/zzucampusnetagent` |
| `root/usr/libexec/rpcd/luci.zzucampusnetagent` | `/usr/libexec/rpcd/luci.zzucampusnetagent` |
| `root/etc/init.d/zzucampusnetagent` | `/etc/init.d/zzucampusnetagent` |
| `root/usr/share/luci/menu.d/luci-app-zzu-campusnet-agent.json` | `/usr/share/luci/menu.d/luci-app-zzu-campusnet-agent.json` |
| `root/usr/share/rpcd/acl.d/luci-app-zzu-campusnet-agent.json` | `/usr/share/rpcd/acl.d/luci-app-zzu-campusnet-agent.json` |
| `root/etc/config/zzucampusnetagent` | `/etc/config/zzucampusnetagent`（已存在则别覆盖，保留你的设置） |

## 安装方法三：用 SDK 编译成 ipk（可选）

```sh
cp -r luci-app-zzu-campusnet-agent <sdk>/package/
cd <sdk>
./scripts/feeds update -a && ./scripts/feeds install -a   # 首次需要
make package/luci-app-zzu-campusnet-agent/compile V=s
# 产物：bin/packages/<arch>/.../luci-app-zzu-campusnet-agent_1.0.0-1_all.ipk → opkg install
```

---

## 自检 / 排错（在路由器 SSH 里）

```sh
zzucampusnetagent status          # 全部线路状态 JSON
zzucampusnetagent query [线路]    # 单条线路状态（默认 main；额外线路用段名，如 wancm）
zzucampusnetagent login [线路]    # 用已保存配置登录
zzucampusnetagent logout [线路]   # 注销
zzucampusnetagent reauth [线路]   # “注销→隔1s→登录”；不带参数 = 全部线路
zzucampusnetagent watchdog        # 检查全部线路，离线的自动重登
logread | grep zzucampusnetagent    # 看定时重授权日志
crontab -l                  # 确认定时任务已写入（# zzucampusnetagent-reauth / -watchdog）
```

- `query` 能返回 `"status":"online"` 说明后端正常；页面看不到就 Ctrl+F5 强刷。
- 登录返回 `result:0` 且提示账号密码为空 → 先在 UI 填好并【保存并应用】。
- 登录一直失败 → 核对运营商后缀是否选对、密码是否正确、baseurl 是否正确。
- `crontab -l` 没有任务 → 确认已勾选“每天定时重新授权”并点过【保存并应用】。

## 安全说明

密码以明文存于 `/etc/config/zzucampusnetagent`（与多数 LuCI 应用做法一致，仅 root 可读）。
提交认证时按 eportal 要求做 base64 + URL 编码。请勿把含密码的配置文件外传。

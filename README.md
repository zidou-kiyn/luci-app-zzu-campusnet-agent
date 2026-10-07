# luci-app-zzu-campusnet-agent — 郑大校园网状态 / 认证 LuCI 插件

为 **ImmortalWrt** 编写（实测 x86-64 内核 6.18、IPQ5018 内核 6.12）的极轻量 LuCI 插件，挂在 LuCI **服务** 菜单下：

- 🟢 每 **10 秒** 自动查询并显示在线状态（账号 / 运营商 / 时长 / IP），带 **手动刷新** 按钮
- 🔑 **一键登录 / 注销**（portal 认证）
- ⏰ **每天定时重新授权**：到点若在线则先注销、隔 1 秒再登录，保证授权不掉线（默认凌晨 06:00）
- 🔀 **多线路**：同一账号在不同出口**同时**登录不同运营商（如电信1 + 移动1），每条线路独立显示状态、独立登录/注销
- 🩺 **掉线自动重登**：定期检查所有线路，发现离线自动重新认证；间隔可设为秒级（如 `5s`，常驻进程快速探测外网）
- ⏰ **单线路额外重认证**：每条线路可另设每天的重认证时间（如联通线路 00:30），与全局定时互不影响
- 🌐 **外网连通检测**（默认开启）：认证服务器只记录登录状态，运营商侧会话失效后仍显示“在线”。插件对在线线路再以该线路 IP 访问 `generate_204` 检测地址，不通则显示 **外网不通**（可一键「重新认证」）；看门狗隔 3 秒复测仍不通则自动“注销→登录”
- 🔀 **故障线路自动摘除**（默认开启，配合多线聚合）：重新认证后仍不通的线路暂时移出聚合路由，新连接不再分到坏线上；连续 2 次检测正常后自动加回；同组全部故障时保留全部
- 📊 **设备监控**（默认关闭，「设备监控」页开启）：各设备实时速率与每日上传 / 下载流量、访问过的域名；开启流量卸载也准确，几乎不占内存，历史按天压缩存闪存（默认 30 天）
- ⚙ **UI 内可改**：服务器地址 baseurl、定时开关与时间；「认证线路」表格里每行一条线路（名称、账号、密码、出口接口、运营商 移动/联通/电信/校园网/学科专网）
- 🎨 Argon Design 配色卡片风，贴近 argon 主题

## 它有多轻量

- **默认零新增常驻进程**：抓取逻辑只在被调用时跑（LuCI 轮询 / cron 触发），平时不占内存；仅当掉线检测间隔设为秒级（如 `5s`）时才由 procd 托管一个 shell 循环。
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

## 多线路部署（一根网线 4 条线、按运营商聚合）

实测郑大校园网允许**同一账号在多个 IP 上同时在线且运营商不同**，一根网线即可拨多条线路。
完整实例（J1900 软路由做主路由 + Redmi AX5400 纯 AP，联通 ×2 + 电信 ×2）见 [extras/j1900/](extras/j1900/README.md)：

```
校园网网线 → eth1 ┬ wancm1 / wancm2（macvlan）联通组 → main  表 ← 31 网段
                  └ wanct1 / wanct2（macvlan）电信组 → wanct 表 ← 32 网段（VLAN 32）
```

要点：

| 项 | 说明 |
|----|------|
| macvlan | 每条线路一个独立 MAC → DHCP 拿独立校园网 IP；MAC 固定则续租 IP 不变。SQM 挂在各 macvlan 上才能分线路限速 |
| 每线一张路由表 | netifd `ip4table`，自动加 `from <线路IP> lookup <线路表>`，保证路由器自身发出的包源 IP 与出口一致。校园网按 MAC 识别会话，不一致时认证请求会算到另一条线上（看门狗误判、登录串号） |
| 组表 | 只放多路默认路由，由 `/etc/hotplug.d/iface/99-multipath`（即 `extras/99-multipath`）在线路上下线时重建；nexthop 用 `onlink`；插件的「故障线路自动摘除」也通过它生效 |
| 多路哈希 | `fib_multipath_hash_policy=1` 按连接分摊，单任务多线程下载可叠加；同组线路出口 IP 相同，换线不掉网站登录 |
| 策略路由 | `lookup main suppress_prefixlength 0`（局域网互访先查 main 但不用其默认路由）；`iif lanct from 192.168.32.0/24 lookup wanct` |
| ARP | 各线路 `arp_ignore=1 / arp_announce=2 / rp_filter=2`，同网段多出口防 ARP 串线（否则认证服务器看到的 MAC 会错） |

> 注意：netifd 停止时不会删除 macvlan，残留设备会导致同名设备认领失败（`DEVICE_CLAIM_FAILED`）或新设备套不上原 MAC。
> 重启网络时先 `network stop`、删掉各线路设备再 `start`（见 `extras/j1900/j1900-apply.sh`）。

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
| `/etc/config/zzucampusnetagent` | UCI 配置：`config` 段为全局设置（服务器、定时任务）；每个 `line` 段是一条认证线路（name/account/password/iface/isp）。旧版把主线路和共用账号密码存在 `config` 段，升级后自动迁移：主线路 → `line` 段 `main`，共用账号密码 → 填进没有自己账号密码的线路 |
| `extras/99-multipath` | （不随包安装）组表多路默认路由 hotplug，配合故障线路摘除 |
| `extras/j1900/` | （不随包安装）实例：J1900 软路由做主路由 + Redmi AX5400 纯 AP 的全套配置脚本，见 [extras/j1900/README.md](extras/j1900/README.md) |
| `htdocs/.../view/zzucampusnetagent/status.js` | LuCI 前端：状态卡片 + 操作按钮 + 设置表单 |
| `/usr/sbin/zzunetmon` | 设备监控 CLI：nft 计数钩子、DNS 日志汇总、按天存储与 JSON 输出 |
| `/etc/init.d/zzunetmon` / `hotplug.d/iface/90-zzunetmon` | 按 `netmon` 配置段启停；LAN 网桥重建后重新挂钩子 |
| `htdocs/.../view/zzucampusnetagent/netmon.js` | LuCI 前端：设备流量表、访问记录弹窗、设置 |
| `menu.d` / `acl.d` | 菜单（服务下）与权限 |

## 设备监控

LuCI → 服务 → ZZU CampusNet Agent → **设备监控**，勾选「启用」、选择要监控的局域网（可多选）后保存。

| 项目 | 做法 |
|------|------|
| 流量 | 在 LAN 网桥的 netdev ingress / egress 钩子（优先级早于 flowtable）上用 nft 动态集合按 IP 计数。nlbwmon 依赖 conntrack 计数，开启流量卸载后几乎统计不到；这里在网桥上计数，卸载的连接同样计入，实测无可见 CPU 开销 |
| 访问记录 | 打开 dnsmasq `log-queries`，日志写在 `/tmp/zzunetmon-dns.*.log`，每 5 分钟汇总为「设备 × 域名 × 查询次数」后清空。只能看到域名（HTTPS 看不到具体网址）；设备自行使用加密 DNS（浏览器「安全 DNS」、iCloud 专用代理等）时缺失 |
| 设备识别 | 按 MAC 区分（IP→MAC 取自 DHCP 租约与邻居表），名称：页面里设置的别名 > DHCP 静态分配 > DHCP 主机名 |
| 存储 | 当天与前一天在 `/tmp/zzunetmon`；每小时压缩同步到 `/etc/zzunetmon`（每天几 KB～几百 KB），超过保留天数自动删除；重启最多丢 1 小时数据 |

```sh
zzunetmon devices [YYYYMMDD]         # 设备流量 JSON
zzunetmon domains <MAC> [YYYYMMDD]   # 某设备访问过的域名 JSON
zzunetmon save                       # 立即汇总并写闪存
logread -e zzunetmon                 # 计数钩子挂载日志
```

> 监控他人设备前请告知使用者。

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
   首次使用：展开页面下方 **账号与认证设置** 在 **认证线路** 表格里填好 **账号 / 密码 / 运营商** →【保存并应用】→ 再点 **登录**。
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
| `root/etc/config/zzucampusnetagent` | `/etc/config/zzucampusnetagent`（已存在则别覆盖，保留你的设置；旧版配置会在首次调用时自动迁移） |

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
zzucampusnetagent query [线路]    # 单条线路状态（线路用 UCI 段名，如 main / wancm1；省略 = 第一条）
zzucampusnetagent login [线路]    # 用已保存配置登录
zzucampusnetagent logout [线路]   # 注销
zzucampusnetagent reauth [线路]   # “注销→隔1s→登录”；不带参数 = 全部线路
zzucampusnetagent relogin [线路]  # 同上（单条），输出登录结果 JSON（页面「重新认证」按钮调用）
zzucampusnetagent watchdog [线路...]  # 检查线路（默认全部）：离线的自动登录；认证在线但外网不通的注销后重登
zzucampusnetagent watchdog-loop 5 # 常驻快速检测（检查间隔设为 5s 时由 procd 自动启动，无需手动运行）
zzucampusnetagent migrate         # 手动触发旧版配置迁移（平时每次调用都会自动检查）
logread | grep zzucampusnetagent    # 看定时重授权日志
crontab -l                  # 确认定时任务已写入（# zzucampusnetagent-reauth / -reauth-line / -watchdog）
ubus call service list '{"name":"zzucampusnetagent"}'  # 秒级检测时确认 watchdog-loop 进程在运行
```

- `query` 能返回 `"status":"online"` 说明后端正常；页面看不到就 Ctrl+F5 强刷。
- `"status":"nonet"`（`"net":"down"`）= 认证服务器显示在线但该线路外网不通，常见于同一账号同一运营商在多个出口反复注销/登录后运营商侧会话失效；`reauth` 该线路即可恢复。检测地址可用 `uci add_list zzucampusnetagent.config.probe_url=...` 自定义（须返回 HTTP 204），`uci set zzucampusnetagent.config.probe=0` 关闭检测。
- 线路被摘除时状态 JSON 带 `"removed": true`，日志有 `failover: [线路] <设备> removed from multipath`；标记文件在 `/var/run/zzucampusnetagent/down/`（按设备名，重启即清空），由 `extras/99-multipath` 读取。未安装该脚本时只记标记、不影响路由。
- 登录返回 `result:0` 且提示账号密码为空 → 先在 UI 填好并【保存并应用】。
- 登录一直失败 → 核对运营商后缀是否选对、密码是否正确、baseurl 是否正确。
- `crontab -l` 没有任务 → 确认已勾选“每天定时重新授权”并点过【保存并应用】。

## 安全说明

密码以明文存于 `/etc/config/zzucampusnetagent`（与多数 LuCI 应用做法一致，仅 root 可读）。
提交认证时按 eportal 要求做 base64 + URL 编码。请勿把含密码的配置文件外传。

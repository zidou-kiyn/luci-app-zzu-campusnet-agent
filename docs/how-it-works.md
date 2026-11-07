# 工作原理

## 认证

路由器 WAN 接入郑大校园网后，eportal 按**来源 IP** 识别用户，由路由器自身发请求即可完成认证：

| 动作 | 请求 |
|------|------|
| 查询 | `https://<baseurl>:802/eportal/portal/custom` |
| 登录 | `https://<baseurl>:802/eportal/portal/login?user_account=,0,<账号><运营商后缀>&user_password=<base64 后再 URL 编码的密码>` |
| 注销 | `https://<baseurl>:802/eportal/portal/logout` |

认证服务器按校区区分：荷园、柳园为 `portal1.zzu.edu.cn`，松园为 `portal2.zzu.edu.cn`。这些域名只有校园网 DNS 能解析，而路由器常改用公共 DNS，所以插件先向各接口 DHCP 下发（含因 `peerdns=0` 未启用）的 DNS 查询，再退回系统 DNS，结果缓存 10 分钟，请求时用 `curl --resolve` 直连。不校验证书：开机时钟未同步时校验会失败，导致无法认证。

运营商后缀：移动 `@cmcc`、联通 `@unicom`、电信 `@telecom`、学科专网 `@zzuplan`，校园网不加后缀。

多线路时每条线路绑定一个 netifd 接口，请求用 `curl --interface <该接口 IP>` 发出，认证服务器据此把不同 IP 分别认证为不同运营商。线路未绑定接口时走系统默认路由。

## 外网检测

认证服务器只记录“登录过”，运营商侧会话失效后仍返回在线。因此对在线的线路再以该线路 IP 请求 `generate_204` 检测地址：

- 只认 HTTP 204。未认证时 HTTP 会被劫持到认证页（200/302），不算通
- 检测地址的 IP 解析一次后缓存 10 分钟，探测时用 `curl --resolve` 直连。路由器自身的 DNS 只走一组线路，不缓存的话那组线路一抖动，所有线路都会因解析超时被误判
- 默认检测 `connect.rom.miui.com` 与 `connectivitycheck.platform.hicloud.com`，任一返回 204 即为通

结果显示为状态 `online` / `nonet`（认证在线但外网不通）/ `offline` / `error`。

## 掉线检测

`watchdog` 逐条检查线路：离线的直接登录；`nonet` 的注销后重新登录。

检测间隔：

- 纯数字（分钟）：由 cron 定时运行 `watchdog`
- 带 `s` 后缀（如 `5s`）：由 procd 托管常驻的 `watchdog-loop`。它每轮对各线路并行请求第一个检测地址；不通的线路再隔 1 秒用全部地址复测 2 轮，都不通才确认并重新认证。处理过的线路 30 秒内不再快速探测，另外每 60 秒跑一次完整 `watchdog`

## 故障摘除与组间兜底

配合多线聚合脚本 [`extras/99-multipath`](../extras/99-multipath) 使用（不随包安装，见 [multi-line.md](multi-line.md)）。

- 重新认证后外网仍不通的线路写入标记 `/var/run/zzucampusnetagent/down/<设备名>`，多路脚本重建组路由时跳过它；之后连续 2 次检测正常再加回
- 已禁用线路的接口同样摘除
- 某组线路全部不可用时，借用其它组的可用线路（如联通全挂时 31 网段临时走电信），本组任一线路恢复后切回；所有组都不可用时保留本组全部

## 组件

| 路由器上的文件 | 作用 |
|----------------|------|
| `/usr/sbin/zzucampusnetagent` | 核心 CLI：查询、登录、注销、重认证、看门狗、外网检测、故障摘除 |
| `/usr/libexec/rpcd/luci.zzucampusnetagent` | rpcd 包装层，把 CLI 暴露给 LuCI（ubus） |
| `/etc/init.d/zzucampusnetagent` | 按配置写入 cron 任务、托管 `watchdog-loop` |
| `/etc/config/zzucampusnetagent` | UCI 配置，见下 |
| `/usr/sbin/zzunetmon`、`/etc/init.d/zzunetmon`、`/etc/hotplug.d/iface/90-zzunetmon` | 设备监控，见 [netmon.md](netmon.md) |
| `/www/luci-static/resources/view/zzucampusnetagent/` | LuCI 页面：`status.js`（状态与设置）、`netmon.js`（设备监控） |
| `menu.d` / `acl.d` 下的 JSON | 菜单与权限 |

## 配置

`/etc/config/zzucampusnetagent`，一般在页面里改即可。

`config` 段（全局）：

| 选项 | 说明 |
|------|------|
| `baseurl` | 认证服务器域名或 IP，默认 `portal1.zzu.edu.cn`；可带端口（默认 802），带 `https://` 与路径也行，只取主机部分 |
| `auto_relogin` / `relogin_time` | 每天定时重新授权的开关与时间（`HH:MM`，默认 `06:00`） |
| `watchdog` / `watchdog_interval` | 掉线检测开关与间隔（分钟数，或 `5s` 这样的秒数） |
| `probe` / `probe_url` | 外网检测开关（默认开）与自定义检测地址（list，须返回 HTTP 204） |
| `failover` | 故障摘除开关（默认开，需开启外网检测） |

`line` 段（每段一条线路，段名即线路 id）：`enabled`、`name`、`account`、`password`、`iface`（出口接口，留空走默认路由）、`isp`（`cmcc` / `unicom` / `telecom` / `campus` / `zzuplan`）、`reauth_time`（该线路额外的每日重认证时间，`HH:MM`）。

`netmon` 段见 [netmon.md](netmon.md)。

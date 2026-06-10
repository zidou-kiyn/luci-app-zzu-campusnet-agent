# luci-app-zzu-campusnet-agent — 郑大校园网状态 / 认证 LuCI 插件

为 **ImmortalWrt（内核 6.12.89）** 编写的极轻量 LuCI 插件，挂在 LuCI **服务** 菜单下：

- 🟢 每 **10 秒** 自动查询并显示在线状态（账号 / 运营商 / 时长 / IP），带 **手动刷新** 按钮
- 🔑 **一键登录 / 注销**（portal 认证）
- ⏰ **每天定时重新授权**：到点若在线则先注销、隔 1 秒再登录，保证授权不掉线（默认凌晨 06:00）
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

## 组件一览

| 文件 | 作用 |
|------|------|
| `/usr/sbin/zzucampusnetagent` | 核心 CLI：`query/login/logout/reauth`，编码与解析都在这里 |
| `/usr/libexec/rpcd/luci.zzucampusnetagent` | rpcd 包装层，把上面三个动作暴露给 LuCI（ubus） |
| `/etc/init.d/zzucampusnetagent` | 按配置同步 cron 定时任务（procd reload 触发） |
| `/etc/config/zzucampusnetagent` | UCI 配置：baseurl/account/password/isp/auto_relogin/relogin_time |
| `htdocs/.../view/zzucampusnetagent/status.js` | LuCI 前端：状态卡片 + 操作按钮 + 设置表单 |
| `menu.d` / `acl.d` | 菜单（服务下）与权限 |

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
zzucampusnetagent query     # 看状态 JSON
zzucampusnetagent login     # 用已保存配置登录
zzucampusnetagent logout    # 注销
zzucampusnetagent reauth    # 手动跑一次“注销→隔1s→登录”重授权流程
logread | grep zzucampusnetagent    # 看定时重授权日志
crontab -l                  # 确认定时任务已写入（含 # zzucampusnetagent-reauth）
```

- `query` 能返回 `"status":"online"` 说明后端正常；页面看不到就 Ctrl+F5 强刷。
- 登录返回 `result:0` 且提示账号密码为空 → 先在 UI 填好并【保存并应用】。
- 登录一直失败 → 核对运营商后缀是否选对、密码是否正确、baseurl 是否正确。
- `crontab -l` 没有任务 → 确认已勾选“每天定时重新授权”并点过【保存并应用】。

## 安全说明

密码以明文存于 `/etc/config/zzucampusnetagent`（与多数 LuCI 应用做法一致，仅 root 可读）。
提交认证时按 eportal 要求做 base64 + URL 编码。请勿把含密码的配置文件外传。

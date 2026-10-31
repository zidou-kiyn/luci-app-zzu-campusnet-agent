# 安装、更新与卸载

以下 `192.168.1.1` 换成你路由器的 LAN 地址。

## 方式一：安装包（推荐）

[Releases](https://github.com/zidou-kiyn/luci-app-zzu-campusnet-agent/releases) 提供编译好的安装包。插件是纯脚本，同一个包适用于所有架构，按系统版本选格式：

| 系统 | 格式 | 安装命令 |
|------|------|----------|
| ImmortalWrt 25.12 / snapshot（apk） | `*.apk` | `apk add --allow-untrusted /tmp/luci-app-zzu-campusnet-agent-*.apk` |
| ImmortalWrt 24.10 及更早（opkg） | `*.ipk` | `opkg install /tmp/luci-app-zzu-campusnet-agent_*_all.ipk` |

不确定用哪个：`which apk` 有输出就用 apk。apk 包为本地编译、无官方签名，所以需要 `--allow-untrusted`。

```sh
scp luci-app-zzu-campusnet-agent-*.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'apk add --allow-untrusted /tmp/luci-app-zzu-campusnet-agent-*.apk'
```

## 方式二：一键脚本（无需编译）

```sh
scp install.sh root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sh /tmp/install.sh'
```

没有 scp 时可用 WinSCP 拖进 `/tmp/`，或在 LuCI 的 TTYD 终端里 `vi /tmp/install.sh` 粘贴。

脚本结束时会重启 `rpcd`、同步 cron、清空 LuCI 缓存；浏览器按 Ctrl+F5 强刷即可，无需重启路由器。

## 方式三：手动拷贝文件

把仓库文件按相同路径放到路由器：

| 本地文件 | 路由器路径 |
|----------|------------|
| `htdocs/luci-static/resources/view/zzucampusnetagent/*.js` | `/www/luci-static/resources/view/zzucampusnetagent/` |
| `root/usr/sbin/zzucampusnetagent`、`root/usr/sbin/zzunetmon` | `/usr/sbin/` |
| `root/usr/libexec/rpcd/luci.zzucampusnetagent` | `/usr/libexec/rpcd/` |
| `root/etc/init.d/zzucampusnetagent`、`root/etc/init.d/zzunetmon` | `/etc/init.d/` |
| `root/etc/hotplug.d/iface/90-zzunetmon` | `/etc/hotplug.d/iface/` |
| `root/usr/share/luci/menu.d/luci-app-zzu-campusnet-agent.json` | `/usr/share/luci/menu.d/` |
| `root/usr/share/rpcd/acl.d/luci-app-zzu-campusnet-agent.json` | `/usr/share/rpcd/acl.d/` |
| `root/etc/config/zzucampusnetagent` | `/etc/config/`（已存在则不要覆盖） |

然后让它生效：

```sh
chmod +x /usr/sbin/zzucampusnetagent /usr/sbin/zzunetmon /usr/libexec/rpcd/luci.zzucampusnetagent \
         /etc/init.d/zzucampusnetagent /etc/init.d/zzunetmon
/etc/init.d/zzucampusnetagent enable; /etc/init.d/zzucampusnetagent restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache
```

## 方式四：用 SDK 编译

```sh
cp -r luci-app-zzu-campusnet-agent <sdk>/package/
cd <sdk>
./scripts/feeds update -a && ./scripts/feeds install -a   # 首次需要
make package/luci-app-zzu-campusnet-agent/compile V=s
# 产物在 bin/packages/<arch>/ 下
```

## 更新

按原来的安装方式再装一遍即可，`/etc/config/zzucampusnetagent` 里的账号、密码等设置都会保留（只补齐新增配置项）：

- 安装包：`apk add --allow-untrusted <新包>`，或 `opkg install --force-reinstall <新包>`
- 一键脚本：传上新的 `install.sh` 后再执行 `sh /tmp/install.sh`
- 手动拷贝：覆盖文件后执行上面“让它生效”的命令

旧版配置（主线路与共用账号存在 `config` 段）会在首次调用时自动迁移为 `line` 段。

## 卸载

```sh
sh /tmp/install.sh uninstall   # 同时删除 cron 任务与配置
```

用安装包安装的也可以 `apk del` / `opkg remove luci-app-zzu-campusnet-agent`。

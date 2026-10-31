# luci-app-zzu-campusnet-agent

郑州大学校园网（eportal）认证 LuCI 插件，适用于 ImmortalWrt（实测 x86-64 内核 6.18、IPQ5018 内核 6.12），入口在 LuCI **服务 → ZZU CampusNet Agent**。

## 功能

- **状态与登录**：每 10 秒刷新在线状态（账号 / 运营商 / 时长 / IP），一键登录、注销、重新认证
- **多线路**：同一账号在不同出口同时以不同运营商认证（如联通 ×2 + 电信 ×2），每条线路独立管理
- **定时重认证**：每天定时“注销 → 登录”（默认 06:00），每条线路可另设时间
- **掉线检测**：离线自动重登；以各线路 IP 探测外网（`generate_204`），认证显示在线但外网不通时自动重新认证；检测间隔可设为秒级
- **故障摘除**（配合多线聚合）：重认证后仍不通或已禁用的线路暂时移出聚合路由，恢复后自动加回；一组线路全部不可用时借用其它组
- **设备监控**（默认关闭）：各设备实时速率、每日流量与访问域名，开启流量卸载也能准确计数
- **轻量**：纯 shell + LuCI JS，只用系统自带工具（`curl`/`uclient-fetch`、`jsonfilter`、`jshn`、`awk`、`cron`），架构无关，占用 < 30 KB

## 安装

从 [Releases](https://github.com/zidou-kiyn/luci-app-zzu-campusnet-agent/releases) 下载安装包，传到路由器 `/tmp/` 后安装：

```sh
apk add --allow-untrusted /tmp/luci-app-zzu-campusnet-agent-*.apk   # ImmortalWrt 25.12 / snapshot
opkg install /tmp/luci-app-zzu-campusnet-agent_*_all.ipk            # ImmortalWrt 24.10 及更早
```

也可以不装包，直接运行一键脚本 `sh /tmp/install.sh`（重复运行即更新，保留已有设置）。手动拷贝、SDK 编译、更新与卸载见 [docs/install.md](docs/install.md)。

## 使用

1. 打开 LuCI → 服务 → ZZU CampusNet Agent，展开 **账号与认证设置**
2. 在 **认证线路** 表格中填写账号、密码、运营商（多线路时再选出口接口），【保存并应用】
3. 点 **登录**；按需开启每天定时重新授权与掉线检测，同样【保存并应用】

## 文档

| 文档 | 内容 |
|------|------|
| [docs/install.md](docs/install.md) | 各种安装方式、更新、卸载 |
| [docs/how-it-works.md](docs/how-it-works.md) | 认证原理、外网检测与故障摘除、组件与配置 |
| [docs/multi-line.md](docs/multi-line.md) | 一根网线多条线路、按运营商聚合，关闭 IPv6 |
| [docs/netmon.md](docs/netmon.md) | 设备监控 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 命令行自检与常见问题 |
| [extras/j1900/](extras/j1900/README.md) | 完整部署实例：J1900 软路由 + Redmi AX5400 AP，4 线聚合 |

## 安全

密码以明文存于 `/etc/config/zzucampusnetagent`（与多数 LuCI 应用一致，仅 root 可读），只在路由器内部使用，不经过浏览器。请勿外传该配置文件。

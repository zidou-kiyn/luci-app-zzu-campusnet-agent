# 设备监控

LuCI → 服务 → ZZU CampusNet Agent → **设备监控**：勾选「启用」，选择要监控的局域网（可多选），保存。默认关闭。

页面显示各设备的实时速率、每日上传 / 下载流量，点开可看访问过的域名。

## 实现

| 项目 | 做法 |
|------|------|
| 流量 | 在 LAN 网桥的 netdev ingress / egress 钩子（早于 flowtable）上用 nft 动态集合按 IP 计数。nlbwmon 依赖 conntrack 计数，开启流量卸载后几乎统计不到；这里在网桥上计数，被卸载的连接同样计入，实测无可见 CPU 开销 |
| 访问记录 | 打开 dnsmasq `log-queries`，日志写到 `/tmp/zzunetmon-dns.*.log`，每 5 分钟汇总为「设备 × 域名 × 次数」后清空。只能看到域名（HTTPS 看不到具体网址）；设备自己使用加密 DNS（浏览器安全 DNS、iCloud 专用代理等）时记录会缺失 |
| 设备识别 | 按 MAC 区分（IP→MAC 取自 DHCP 租约与邻居表）。名称优先级：页面里设置的别名 > DHCP 静态分配 > DHCP 主机名 |
| 存储 | 当天与前一天在 `/tmp/zzunetmon`；每小时压缩同步到 `/etc/zzunetmon`（每天几 KB～几百 KB），超过保留天数（默认 30）自动删除；重启最多丢 1 小时数据 |

## 配置

`/etc/config/zzucampusnetagent` 的 `netmon` 段：`enabled`、`dns`（是否记录访问域名）、`retention`（保留天数）、`iface`（监控的局域网接口，list）。

## 命令

```sh
zzunetmon devices [YYYYMMDD]         # 设备流量 JSON
zzunetmon domains <MAC> [YYYYMMDD]   # 某设备访问过的域名 JSON
zzunetmon save                       # 立即汇总并写入闪存
logread -e zzunetmon                 # 计数钩子挂载日志
```

监控他人设备前请告知使用者。

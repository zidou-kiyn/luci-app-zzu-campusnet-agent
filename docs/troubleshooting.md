# 自检与排错

以下命令在路由器 SSH 里执行。线路参数用 UCI 段名（如 `wancm1`），省略时默认第一条线路。

```sh
zzucampusnetagent status              # 全部线路状态 JSON
zzucampusnetagent query [线路]        # 单条线路状态
zzucampusnetagent login [线路]        # 用已保存的配置登录
zzucampusnetagent logout [线路]       # 注销
zzucampusnetagent reauth [线路]       # 注销 → 隔 1 秒 → 登录；不带参数 = 全部线路
zzucampusnetagent watchdog [线路...]  # 手动跑一次掉线检测（默认全部线路）
logread -e zzucampusnetagent          # 认证、看门狗、故障摘除日志
logread -e multipath                  # 多路聚合重建日志
crontab -l                            # 定时任务（# zzucampusnetagent-reauth / -reauth-line / -watchdog）
ubus call service list '{"name":"zzucampusnetagent"}'   # 秒级检测时确认 watchdog-loop 在运行
```

## 常见问题

**页面看不到状态。** 先确认 `zzucampusnetagent query` 能返回 `"status": "online"`；后端正常的话，浏览器按 Ctrl+F5 强刷。

**状态是 `nonet`（外网不通）。** 认证服务器显示在线但该线路外网不通，常见于运营商侧会话失效；`reauth` 该线路即可，开了掉线检测时会自动处理。若是学校出口本身故障，重认证也无效，等出口恢复即可。
检测地址可自定义（须返回 HTTP 204）：`uci add_list zzucampusnetagent.config.probe_url=<地址>`；关闭检测：`uci set zzucampusnetagent.config.probe=0`，改完 `uci commit`。

**线路被摘除了。** 状态 JSON 带 `"removed": true`，日志有 `failover: [线路] <设备> removed from multipath`。标记文件在 `/var/run/zzucampusnetagent/down/`（重启清空），由 `99-multipath` 读取；没装该脚本时只记标记，不影响路由。组间兜底时日志有 `multipath: main: N path(s) (own lines all down, borrowing: ...)`。

**登录返回 `result: 0`，提示账号密码为空。** 先在页面填好并【保存并应用】。

**登录一直失败。** 核对运营商是否选对、密码是否正确、`baseurl` 是否正确。

**`crontab -l` 没有任务。** 确认已勾选每天定时重新授权（或掉线检测），并点过【保存并应用】。

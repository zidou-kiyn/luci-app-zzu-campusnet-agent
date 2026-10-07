# 自建 Tailscale 中转（DERP）

校园网和手机网络都是对称 NAT（`tailscale netcheck` 显示 `MappingVariesByDestIP: true`），
两边通常打不通直连，只能走中转。官方中转最近的也在 150ms 以上，所以在香港服务器上自建一个。

## 校园网的坑

从校园网到这台香港服务器，**TCP 22 / 80 / 443 和 UDP 3478 都不通**，其它不常用端口正常；
手机流量访问 443 正常，服务器防火墙 / 安全组也没拦，所以是校园网拦的。因此：

- 中转用 **TCP 33445**、STUN 用 **UDP 33478**（换别的不常用端口也行，先从校园网测通）
- derper 用 letsencrypt 证书时**只在 443 上启用 TLS**，监听其它端口会变成明文 HTTP，
  客户端报 `first record does not look like a TLS handshake`。所以容器里固定监听 443，对外端口用 Docker 映射
- 80 端口留给 Let's Encrypt 续期（证书机构从国外访问，不受校园网影响）

## 部署

1. 域名 A 记录指向服务器；安全组放行 TCP 80、443、33445，UDP 33478
2. 生成 auth key：Tailscale 后台 → Settings → Keys。**Reusable、Ephemeral 都不勾**；有效期 1 天即可
3. 服务器上：
   ```sh
   cp .env.example .env    # 填域名和 auth key
   docker compose up -d --build
   docker compose logs --tail 20 derper    # 应看到 serving on :443 with TLS
   ```
4. Tailscale 后台 → Machines → `hk-derp` → **Disable key expiry**（过期后 `-verify-clients` 会拒绝所有设备）；
   之后可把 `.env` 里的 `TS_AUTHKEY` 删掉
5. Tailscale 后台 → Access controls → JSON editor，把 `derpmap.jsonc` 的内容贴到最外层，Save

## 验证（在路由器上）

```sh
tailscale debug derp 900     # 应有 Successfully established a DERP connection
tailscale netcheck           # Nearest DERP 应为 Hong Kong (self)
```

`debug derp` 里「captive portal check … port 80 blocked」和 IPv6 的报错可以忽略（校园网拦了 80、域名没有 IPv6）。

## 手机

安卓同时只能开一个 VPN，Tailscale 和 FlClash 之类的代理 App 不能同时开；
Tailscale 登录要访问国外服务器，可以先开代理登录，或在登录页菜单里用 auth key 登录。

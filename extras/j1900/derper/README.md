# 自建 Tailscale 中转（DERP）

校园网和手机网络都是对称 NAT（`tailscale netcheck` 显示 `MappingVariesByDestIP: true`），
两边通常打不通直连，只能走中转。官方中转最近的也在 150ms 以上，所以自建了两个：

| 区域 | 位置 | 证书 | 文件 | 校园网 → 中转 |
|---|---|---|---|---|
| 900 `hk-self` | 香港 | derper 自己申请 Let's Encrypt | `docker-compose.yml` | 约 36ms |
| 901 `cn-self` | 国内（已备案） | 反向代理已有的通配符证书 | `docker-compose.manual-cert.yml` | 约 21ms |

每台设备自动选延迟最低的作为自己的中转，另一个作备用。两个都写在 `derpmap.jsonc` 里。

## 校园网的坑

从校园网到香港服务器，**TCP 22 / 80 / 443 和 UDP 3478 都不通**，其它不常用端口正常；
手机流量访问 443 正常，服务器防火墙 / 安全组也没拦，所以是校园网拦的。因此两个中转都用：

- 中转 **TCP 33445**、STUN **UDP 33478**（换别的不常用端口也行，先从校园网测通）
- 80 端口只给 Let's Encrypt 续期用（证书机构从国外访问，不受校园网影响）

## derper 的坑：TLS 只在 443 或 manual 模式下开启

`-certmode=letsencrypt` 时 derper **只在 443 上启用 TLS**，监听其它端口会变成明文 HTTP，
客户端报 `first record does not look like a TLS handshake`。所以：

- letsencrypt 模式（香港）：容器里固定监听 443，对外 33445 用 Docker 端口映射
- manual 模式（国内）：可以直接监听 33445

manual 模式**只在启动时读证书**，反向代理续期后 derper 仍用内存里的旧证书，所以要定期重启（见下）。

## 部署：香港（`docker-compose.yml`）

1. 域名 A 记录指向服务器；安全组放行 TCP 80、443、33445，UDP 33478
2. 生成 auth key：Tailscale 后台 → Settings → Keys。**Reusable、Ephemeral 都不勾**；有效期 1 天即可
3. 服务器上：
   ```sh
   cp .env.example .env    # 填域名和 auth key
   docker compose up -d --build
   docker compose logs --tail 20 derper    # 应看到 serving on :443 with TLS
   ```

## 部署：国内（`docker-compose.manual-cert.yml`）

适用于已备案、80/443 被 Nginx Proxy Manager 之类占用的服务器。

1. **镜像**：国内拉不动 Docker Hub 和 Go 依赖，在香港服务器上导出后传过来：
   ```sh
   # 香港
   docker pull tailscale/tailscale:stable
   docker save derper-derper tailscale/tailscale:stable | gzip > derp-images.tar.gz
   # 用 sftp / scp 传到国内服务器后
   gunzip -c derp-images.tar.gz | docker load
   ```
2. **证书**：用反向代理里已有的证书（`*.example.com` 通配符可以覆盖 `derp-cn.example.com`）。
   找到 NPM 的 letsencrypt 目录（`docker inspect <npm 容器>` 看 `/etc/letsencrypt` 挂在哪），再找对应证书：
   ```sh
   for d in /path/to/npm/letsencrypt/live/npm-*; do
     echo "$d: $(openssl x509 -noout -ext subjectAltName -in $d/cert.pem | tail -1)"; done
   mkdir -p certs
   ln -sf /path/to/npm/letsencrypt/live/npm-N/fullchain.pem certs/derp-cn.example.com.crt
   ln -sf /path/to/npm/letsencrypt/live/npm-N/privkey.pem   certs/derp-cn.example.com.key
   openssl x509 -noout -subject -enddate -in certs/derp-cn.example.com.crt   # 验证链接
   ```
   文件名必须是 `<derper 的域名>.crt/.key`；要挂整个 letsencrypt 目录（`live/` 里的文件本身是指向 `archive/` 的软链接）。
   compose 里把 `/path/to/npm/letsencrypt` 换成实际路径，容器内外保持一致
3. 域名 A 记录指向服务器；安全组放行 TCP 33445、UDP 33478；`.env` 填 `DERP_DOMAIN` 和新的 auth key
4. 启动，并每周重启一次读新证书（断开几秒，客户端自动重连）：
   ```sh
   docker compose -f docker-compose.manual-cert.yml up -d
   docker compose -f docker-compose.manual-cert.yml logs --tail 20 derper   # serving on :33445 with TLS
   ( crontab -l 2>/dev/null; echo '0 5 * * 1 docker restart derper >/dev/null 2>&1' ) | crontab -
   ```

## 部署后（两个都要做）

1. Tailscale 后台 → Machines → `hk-derp` / `cn-derp` → **Disable key expiry**
   （过期后 `-verify-clients` 会拒绝所有设备）；之后可把 `.env` 里的 `TS_AUTHKEY` 删掉
2. Tailscale 后台 → Access controls → JSON editor，把 `derpmap.jsonc` 的内容贴到最外层，Save

## 验证（在路由器上）

```sh
tailscale debug derp 900     # 应有 Successfully established a DERP connection
tailscale debug derp 901
tailscale netcheck           # 列出各区域延迟，Nearest DERP 应为其中最低的
tailscale status --json | grep -m1 '"Relay"'   # 本机当前用的中转
```

`debug derp` 里「captive portal check … port 80 blocked」和 IPv6 的报错可以忽略（校园网拦了 80、域名没有 IPv6）。

加了新区域后，已经在线的设备不一定马上换过去（Tailscale 换中转比较保守），重启一次 Tailscale 即可。

## 不能按设备指定中转

Tailscale 没有「这台设备固定用某个中转」的设置，每台设备按延迟自己选。
只能在 `derpmap.jsonc` 里给某个区域加 `"Avoid": true`，让**所有设备**都不选它（仍可作备用）。

## 手机

安卓同时只能开一个 VPN，Tailscale 和 FlClash 之类的代理 App 不能同时开；
Tailscale 登录要访问国外服务器，可以先开代理登录，或在登录页菜单里用 auth key 登录。

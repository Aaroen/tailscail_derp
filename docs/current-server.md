# 当前服务器（示例）运行方式梳理

说明：本文件仅记录“实际观测到的配置与行为”，不包含任何敏感内容（例如 `/etc/derp/tskey.txt` 的内容）。
为避免泄露隐私，本仓库不会记录真实公网 IP/域名；下文使用占位符 `<DERP_PUBLIC_HOST>` 表示实际对外地址（IP 或域名）。

## 核心组件

### 1) DERP/STUN 服务：`derp.service`

- unit：`/etc/systemd/system/derp.service`
- 进程：`/root/go/bin/derper`
- 启动参数（观测值）：
  - `-hostname <DERP_PUBLIC_HOST>`
  - `-a :443`
  - `-stun-port 3478`
  - `-certmode manual`
  - `-certdir /etc/derp`

端口监听（观测值）：

- `tcp/443`：DERP over TLS
- `udp/3478`：STUN
- `tcp/80`：`derper` 默认的 HTTP 端口（用于主页/重定向/ACME 等；是否需要取决于证书模式与部署策略）

证书目录（观测值）：

- `/etc/derp/<DERP_PUBLIC_HOST>.crt` / `/etc/derp/<DERP_PUBLIC_HOST>.key`：当前对外呈现的自签名证书（有效期约 1 年；若为 IP 模式需包含 IP SAN）
- `/etc/derp/derp.crt` / `/etc/derp/derp.key`：存在但不一定被当前 `derper` 使用（需以实际对外呈现证书为准）

### 2) 自动更新：`derp-ip-updater.service`

- unit：`/etc/systemd/system/derp-ip-updater.service`
- 执行脚本：`/usr/local/bin/update_derp_ip_full_auto.sh`
- 触发方式：oneshot + enabled（通常开机后执行一次）
- 主要逻辑（概括）：
  1. `sleep 15` 等网络
  2. 通过 `ifconfig.me`/`ip.sb` 获取公网 IP
  3. 与 `/etc/derp/last_ip.txt` 比较，若变化：
     - `systemctl stop derp`
     - 生成自签名证书（写入 `/etc/derp/derp.{crt,key}`）
     - 用 `sed -i` 修改 `/etc/systemd/system/derp.service` 内的 `-hostname` 参数
     - `daemon-reload` + `start derp`
     - 读取 `/etc/derp/tskey.txt` 中的 Tailscale API Key，POST ACL（包含 `derpMap`）到：
       - `https://api.tailscale.com/api/v2/tailnet/<TAILNET_NAME>/acl`
     - 更新 `/etc/derp/last_ip.txt`

## 关键风险点（与“项目优化”直接相关）

1) **证书生成与 `derper` 实际加载的证书命名可能不一致**
- 当前对外呈现的是 `<DERP_PUBLIC_HOST>.crt`（IP 模式下应带 IP SAN）
  - 但更新脚本生成的是 `derp.crt`
  - 若未来 IP 变化，脚本可能导致 `derper` 找不到匹配证书或继续使用旧证书（需要在优化版脚本中明确并统一）

2) **证书有效期**
   - 当前对外呈现的自签名证书为 1 年有效期；需要续期机制，否则到期后客户端会失败/报警（尤其是未设置 `InsecureForTests` 的场景）

3) **脚本会覆盖 tailnet 的 ACL**
   - 当前脚本是“生成一份 ACL JSON 并整体 POST”，这会覆盖现有策略文件
   - 对“多团队/多用途 tailnet”风险较高，建议改造为“只更新 derpMap（或显式 --force）”

4) **以 root 运行**
   - `derp.service` 以 `root` 运行并绑定 80/443；建议改为专用用户 + `CAP_NET_BIND_SERVICE` 并增加 systemd hardening

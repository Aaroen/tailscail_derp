# 项目整合与优化建议（面向可复用部署）

目标：在不改变“核心用途”（提供 DERP+STUN、中转能力，必要时自动更新 tailnet 的 derpMap）前提下，提高安全性、可维护性和可一键部署性。

## 1) 首选架构：域名 + Let's Encrypt（推荐）

问题根源：使用“IP + 自签名证书”会迫使客户端使用 `InsecureForTests`（降低服务端身份校验），并带来证书续期和命名一致性问题。

推荐改造：

- 给 DERP 节点绑定域名（例如 `derp-hz.example.com`）
- `derper` 使用 `-certmode letsencrypt` 自动签发/续期
- Tailscale `derpMap` 的 `HostName` 填域名
- 这样即使公网 IP 改变，也只需要更新 DNS（可用 DDNS），无需改 unit 参数、无需生成自签名证书、可移除 `InsecureForTests`

## 2) 如果必须用 IP：自签名证书要“可续期且命名一致”

建议点：

- 证书生成必须包含 `subjectAltName=IP:<ip>`（仅 CN 在很多客户端/库里已不被信任）
- 明确 `derper` 在 `manual` 模式下实际读取的证书文件命名（你当前观测到对外呈现的是 `<hostname>.crt`），并让更新脚本生成同名文件
- 不要 `rm` 删除旧证书；建议：
  - 新证书生成到临时文件
  - 原证书备份为带时间戳的文件名（便于回滚）
  - 原子替换（`mv`）

## 3) systemd 层优化（更安全、更可控）

- `User=` 改为专用用户（例如 `derp`），避免 root 常驻
- 使用 `AmbientCapabilities=CAP_NET_BIND_SERVICE` 以允许绑定 80/443
- 建议开启 hardening（示例）：
  - `NoNewPrivileges=true`
  - `PrivateTmp=true`
  - `ProtectSystem=strict`
  - `ProtectHome=true`
  - `ReadWritePaths=/etc/derp /var/log`（按实际需要）
- 避免更新脚本 `sed -i` 直接改 unit 文件：改为读取 `EnvironmentFile`（例如 `/etc/derp/derp.env`）

## 4) Tailscale ACL / derpMap 更新策略

当前脚本策略是“生成完整 ACL 并 POST”。建议两种模式：

1) **完全托管 ACL（简单，但有覆盖风险）**
   - 仓库提供 `acl.template.json` 或脚本内模板
   - 用户明确接受由本项目“全量管理” ACL
   - 适合你自己的 tailnet 或单用途 tailnet

2) **只更新 derpMap（更安全，建议作为默认）**
   - 先 GET 当前 ACL
   - 解析/清洗（ACL 可能包含注释、尾逗号等）
   - 仅修改 `derpMap` 字段
   - 再 POST 回去

## 5) 观测与运维

- 给 updater 日志加 logrotate（避免 `/var/log/derp_updater.log` 无上限增长）
- 建议加入健康检查：
  - `curl -fsS https://<host>/derp`（或检查 443/3478 监听）
- 端口层面建议：
  - 若不需要 80：`-http-port -1`（降低扫描噪音）
  - 若需要 ACME：保留 80 并确保安全组放行

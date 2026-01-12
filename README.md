## 项目介绍

这是一个用于部署自建 Tailscale DERP（`derper`）中转站的仓库，目标是让新服务器做到：

- 开机自启 DERP（`tcp/443`）+ STUN（`udp/3478`）
- 自动探测服务器公网 IP
- 使用 Tailscale API access token 自动把最新节点信息写入 tailnet 的 ACL（**仅更新 `derpMap`，不覆盖其它 ACL 字段**）

本仓库不包含任何密钥/证书私钥；敏感信息仅放在服务器本地（例如 `/etc/derp/derp.env`）。

## 适用方案

当前默认按 A 方案运行：**公网 IP + 自签名证书**。

- 优点：不需要域名，部署简单，立刻可用
- 注意：自签名模式通常需要在 `derpMap` 里设置 `InsecureForTests: true`；并且要确保云安全组/防火墙放通端口，否则 `tailscale netcheck` 会看不到该 DERP 的延迟

更详细的文件路径与启动链路见：
- `docs/current-server.md`

## 一键部署（推荐流程）

### 0) 开通端口（必须）

请在云厂商安全组/防火墙放行入站：

- `TCP 443`（DERP over TLS，必须）
- `UDP 3478`（STUN，必须）
- `TCP 80`（可选，仅用于 `http://<ip>/` 跳转/展示；不影响 DERP 核心功能）

如果 80/443 未放行，你会看到：浏览器访问超时、`tailscale netcheck` 里该区域延迟为空白。

### 1) 准备 `derper` 二进制

目标机需要 `/usr/local/bin/derper`（可执行）。

现阶段可选方式：

- 从你已有的 DERP 机器拷贝：`scp root@<已有DERP服务器>:/root/go/bin/derper /usr/local/bin/derper && chmod +x /usr/local/bin/derper`
- 或目标机自行 `go install tailscale.com/cmd/derper@<version>` 后放到 `/usr/local/bin/derper`

### 2) 拉取仓库并安装 systemd

在目标机执行：

```bash
git clone https://github.com/Aaroen/Tailscale-DERP.git
cd Tailscale-DERP
./scripts/install_systemd.sh
```

### 3) 配置 `/etc/derp/derp.env`（填 token 与 tailnet）

编辑 `/etc/derp/derp.env`，至少设置：

- `TAILSCALE_TAILNET=<你的 tailnet 标识>`
- `TAILSCALE_API_KEY=<Tailscale API access token，需有 ACL 读写权限>`

说明：

- 这是 **API access token**（用于调用 API 更新 ACL/derpMap），不是 auth key
- `DERP_HOSTNAME` 会在服务启动/定时任务运行时自动探测公网 IP 并写回

### 4) 启用开机自启 + 定时更新

```bash
systemctl enable --now derp.service
systemctl enable --now derp-ip-updater.timer
```

## 工作原理（简述）

- `derp.service` 通过 `scripts/start_derper.sh` 启动 `derper`：
  - 自动获取公网 IP
  - 在 `/etc/derp` 生成/复用 `IP.crt`/`IP.key`（自签名，含 IP SAN）
  - 启动 `derper`（443/3478，80 默认开启）
- `derp-ip-updater.timer` 定时触发 `scripts/update_derp_ip.sh`：
  - 公网 IP 变化时：更新 `/etc/derp/derp.env`、生成新证书、重启 `derp.service`
  - 通过 Tailscale API 获取当前 ACL 并 **仅更新 `derpMap`**（添加/更新你指定的 Region/Node）

## 验证方式

在目标机：

```bash
systemctl --no-pager status derp.service
ss -lntup | grep -E ':(443|80)\\b|:3478\\b' || true
journalctl -u derp-ip-updater.service --no-pager -n 200
```

在任意外部机器：

- `curl -k https://<公网IP>/` 应显示 “This is a Tailscale DERP server”
- `tailscale netcheck` 应能看到 `my-xx: <latency> (My <name> DERP)`（前提：80/443/3478 已放通，且 derpMap 已更新）

## 目录结构

- `systemd/`：systemd unit（`derp.service`、`derp-ip-updater.*`）
- `scripts/`：启动/更新脚本（参数化、无密钥）
- `docs/`：盘点报告、优化建议、部署与上传文档

## 进一步优化（可选）

强烈建议优先改为“域名 + Let's Encrypt”（避免自签名与 `InsecureForTests`），以及把“更新 hostname/证书/ACL”的逻辑拆成可复用且可审计的脚本（不直接 `sed -i` 改 unit 文件、不 `rm` 删除关键文件，改为生成新文件+备份旧文件）。

详见：
- `docs/optimization.md`

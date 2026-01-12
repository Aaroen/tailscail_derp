# 服务器部署步骤（A：IP + 自签名）

本步骤用于在一台新服务器上部署 `derper`（DERP+STUN）并实现：

- 开机自启 DERP 服务
- 自动获取公网 IP
- 使用 Tailscale API token 仅更新 tailnet ACL 中的 `derpMap`

## 0) 前置条件

- 放行端口：`TCP 443`、`UDP 3478`（可选 `TCP 80`）
- 系统：Ubuntu/Debian（其它发行版类同）
- 你已准备好：
  - `TAILSCALE_TAILNET`
  - `TAILSCALE_API_KEY`（API access token）

## 1) 安装依赖

```bash
apt-get update
apt-get install -y curl openssl python3 ca-certificates
```

## 2) 获取本仓库

```bash
git clone https://github.com/Aaroen/Tailscale-DERP.git
cd Tailscale-DERP
```

## 3) 安装 `derper` 二进制

要求：`/usr/local/bin/derper` 可执行。

（临时方案）如果你已经有一台现网 DERP 机器可取二进制，可用 `scp` 拷贝到目标机：

```bash
scp root@<已有DERP服务器>:/root/go/bin/derper /usr/local/bin/derper
chmod +x /usr/local/bin/derper
```

后续建议把 `derper` 通过 GitHub Release/Actions 构建成可下载 artifact，再由安装脚本自动下载。

## 4) 安装 systemd unit + 脚本

```bash
./scripts/install_systemd.sh
```

## 5) 配置 `/etc/derp/derp.env`

编辑 `/etc/derp/derp.env`，至少填：

- `TAILSCALE_TAILNET=...`
- `TAILSCALE_API_KEY=...`

成都节点建议：

- `DERP_REGION_ID=903`
- `DERP_REGION_CODE=my-cd`
- `DERP_REGION_NAME="My Chengdu DERP"`
- `DERP_NODE_NAME=derp-cd-1`

说明：`DERP_HOSTNAME` 会在服务启动时自动探测公网 IP 并写回。

## 6) 启用开机自启

```bash
systemctl enable --now derp.service
systemctl enable --now derp-ip-updater.timer
```

## 7) 验证

```bash
systemctl status derp.service --no-pager
ss -lntup | grep -E ':(443|80)\\b|:3478\\b' || true
journalctl -u derp-ip-updater.service --no-pager -n 200
```

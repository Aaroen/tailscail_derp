#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  sudo ./scripts/install_systemd.sh [--force]

说明：
  - 默认不覆盖已有的 /etc/systemd/system/derp*.service（避免误改现网）。
  - 你需要自行准备 /usr/local/bin/derper（或后续为本仓库补齐 release 二进制下载逻辑）。
  - 该脚本不会删除任何文件；若 --force 覆盖，会对旧文件做时间戳备份。
EOF
}

force=0
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--force" ]]; then
  force=1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

backup_if_exists() {
  local target="$1"
  if [[ -e "$target" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    cp -a "$target" "${target}.bak.${ts}"
  fi
}

install_file() {
  local src="$1"
  local dst="$2"
  if [[ -e "$dst" && "$force" -ne 1 ]]; then
    echo "已存在，跳过（使用 --force 覆盖）：$dst"
    return 0
  fi
  backup_if_exists "$dst"
  install -m 0644 "$src" "$dst"
  echo "已安装：$dst"
}

main() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "需要 root 权限运行（sudo）"
    exit 1
  fi

  if ! id -u derp >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin derp
  fi

  mkdir -p /usr/local/lib/derp-relay /etc/derp
  chmod 700 /etc/derp || true
  mkdir -p /var/lib/derper

  # 脚本
  install -m 0755 "$repo_root/scripts/start_derper.sh" /usr/local/lib/derp-relay/start_derper.sh
  install -m 0755 "$repo_root/scripts/update_derp_ip.sh" /usr/local/lib/derp-relay/update_derp_ip.sh
  install -m 0755 "$repo_root/scripts/render_acl_with_derpmap.sh" /usr/local/lib/derp-relay/render_acl_with_derpmap.sh
  install -m 0755 "$repo_root/scripts/post_acl.sh" /usr/local/lib/derp-relay/post_acl.sh

  # systemd units
  install_file "$repo_root/systemd/derp.service" /etc/systemd/system/derp.service
  install_file "$repo_root/systemd/derp-ip-updater.service" /etc/systemd/system/derp-ip-updater.service
  install_file "$repo_root/systemd/derp-ip-updater.timer" /etc/systemd/system/derp-ip-updater.timer

  systemctl daemon-reload

  if [[ ! -f /etc/derp/derp.env ]]; then
    cat >/etc/derp/derp.env <<'EOF'
# DERP 服务配置
DERP_HOSTNAME=
DERP_ADDR=:443
DERP_STUN_PORT=3478
DERP_CERTMODE=manual
DERP_CERTDIR=/etc/derp
DERP_HTTP_PORT=80
DERP_EXTRA_ARGS=""

# 自动更新配置
DERP_ENV_FILE=/etc/derp/derp.env
DERP_LAST_IP_FILE=/etc/derp/last_ip.txt
DERP_SERVICE_NAME=derp.service
DERP_UPDATER_LOG=/var/log/derp_updater.log

# Tailscale ACL/derpMap 更新（默认开启，但你必须在服务器上填好 token 与 tailnet）
TAILSCALE_UPDATE_ACL=1
TAILSCALE_TAILNET=
TAILSCALE_API_KEY=

# 成都节点默认值（可按需调整）
DERP_REGION_ID=903
DERP_REGION_CODE=my-cd
DERP_REGION_NAME="My Chengdu DERP"
DERP_NODE_NAME=derp-cd-1
DERP_PORT=443
STUN_PORT=3478
DERP_INSECURE_FOR_TESTS=true
EOF
    chmod 600 /etc/derp/derp.env
    echo "已生成模板：/etc/derp/derp.env（请填入 DERP_HOSTNAME / TAILSCALE_TAILNET / TAILSCALE_API_KEY）"
  else
    echo "已存在：/etc/derp/derp.env（未覆盖）"
  fi

  echo "启用服务：systemctl enable --now derp.service"
  echo "启用定时器：systemctl enable --now derp-ip-updater.timer"
}

main "$@"

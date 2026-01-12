#!/usr/bin/env bash
set -euo pipefail

umask 077

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${DERP_UPDATER_LOG:-/var/log/derp_updater.log}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "缺少依赖命令：$1"; exit 1; }
}

get_public_ip() {
  if [[ -n "${PUBLIC_IP:-}" ]]; then
    echo "${PUBLIC_IP}"
    return 0
  fi
  curl -fsS --max-time 10 ifconfig.me 2>/dev/null || curl -fsS --max-time 10 ip.sb 2>/dev/null
}

set_kv_in_env_file() {
  local env_file="$1"
  local key="$2"
  local value="$3"

  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"

  if grep -qE "^${key}=" "$env_file"; then
    # 仅替换整行 KEY=...
    sed -i -E "s#^${key}=.*#${key}=${value}#g" "$env_file"
  else
    echo "${key}=${value}" >>"$env_file"
  fi
}

generate_self_signed_ip_cert() {
  local cert_dir="$1"
  local ip="$2"

  mkdir -p "$cert_dir"
  chmod 700 "$cert_dir" || true

  local crt="${cert_dir}/${ip}.crt"
  local key="${cert_dir}/${ip}.key"

  if [[ -f "$crt" && -f "$key" ]]; then
    log "证书已存在：$crt"
    return 0
  fi

  local tmp_crt="${crt}.new.$(date +%s)"
  local tmp_key="${key}.new.$(date +%s)"

  log "生成自签名 IP 证书：CN=$ip, SAN=IP:$ip"
  openssl req -x509 -newkey rsa:4096 -sha256 -days "${DERP_CERT_DAYS:-365}" -nodes \
    -keyout "$tmp_key" -out "$tmp_crt" \
    -subj "/CN=$ip" \
    -addext "subjectAltName=IP:$ip"

  chmod 600 "$tmp_key"
  chmod 644 "$tmp_crt"

  # 不删除旧文件：若目标文件已存在则保留；否则原子落盘
  [[ -e "$key" ]] || mv "$tmp_key" "$key"
  [[ -e "$crt" ]] || mv "$tmp_crt" "$crt"

  # 若目标已存在，保留 new 文件以便排查（不做 rm）
}

main() {
  require_cmd curl
  require_cmd openssl

  local env_file="${DERP_ENV_FILE:-/etc/derp/derp.env}"
  local cert_dir="${DERP_CERTDIR:-/etc/derp}"
  local last_ip_file="${DERP_LAST_IP_FILE:-${cert_dir}/last_ip.txt}"
  local last_acl_ts_file="${DERP_LAST_ACL_TS_FILE:-${cert_dir}/last_acl_update_epoch.txt}"
  local acl_update_max_age_sec="${DERP_ACL_UPDATE_MAX_AGE_SEC:-86400}"
  local service_name="${DERP_SERVICE_NAME:-derp.service}"

  log "开始检查公网 IP..."
  local current_ip
  current_ip="$(get_public_ip || true)"
  if [[ -z "${current_ip}" ]]; then
    log "错误：无法获取公网 IP"
    exit 1
  fi

  local last_ip=""
  if [[ -f "$last_ip_file" ]]; then
    last_ip="$(cat "$last_ip_file" || true)"
  fi

  local ip_changed=0
  if [[ "$current_ip" != "$last_ip" || -z "$last_ip" ]]; then
    ip_changed=1
    log "检测到 IP 变化：'${last_ip}' -> '${current_ip}'"
    export DERP_HOSTNAME="$current_ip"
    set_kv_in_env_file "$env_file" "DERP_HOSTNAME" "$current_ip"
    set_kv_in_env_file "$env_file" "DERP_CERTMODE" "${DERP_CERTMODE:-manual}"
    set_kv_in_env_file "$env_file" "DERP_CERTDIR" "$cert_dir"

    if [[ "${DERP_CERTMODE:-manual}" == "manual" ]]; then
      generate_self_signed_ip_cert "$cert_dir" "$current_ip"
    fi

    echo "$current_ip" >"$last_ip_file"
  else
    log "IP 未变化：$current_ip"
  fi

  # Tailscale derpMap 更新策略：
  # - IP 变化时必更新
  # - IP 未变化时：首次（无时间戳）或超过一定周期也会更新一次，确保“开机首次部署”也能写入 derpMap
  if [[ "${TAILSCALE_UPDATE_ACL:-0}" == "1" ]]; then
    if [[ -z "${TAILSCALE_API_KEY:-}" || -z "${TAILSCALE_TAILNET:-}" ]]; then
      log "TAILSCALE_UPDATE_ACL=1 但未提供 TAILSCALE_API_KEY/TAILSCALE_TAILNET，跳过 ACL 更新"
    else
      local now_epoch
      now_epoch="$(date +%s)"
      local last_epoch="0"
      if [[ -f "$last_acl_ts_file" ]]; then
        last_epoch="$(cat "$last_acl_ts_file" 2>/dev/null || echo 0)"
      fi

      local need_acl_update=0
      if [[ "$ip_changed" == "1" ]]; then
        need_acl_update=1
      elif [[ "$last_epoch" == "0" ]]; then
        need_acl_update=1
      elif [[ $((now_epoch - last_epoch)) -ge "$acl_update_max_age_sec" ]]; then
        need_acl_update=1
      fi

      if [[ "$need_acl_update" == "1" ]]; then
        export DERP_HOSTNAME="$current_ip"
        /usr/local/lib/derp-relay/post_acl.sh
        echo "$now_epoch" >"$last_acl_ts_file"
      else
        log "ACL/derpMap 更新未到周期（上次 epoch=$last_epoch），跳过"
      fi
    fi
  fi

  # 尽量温和：仅 try-restart，不强行 stop/start
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl try-restart "$service_name" || true
  fi

  log "完成"
}

main "$@"

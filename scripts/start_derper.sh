#!/usr/bin/env bash
set -euo pipefail

umask 077

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${DERP_UPDATER_LOG:-/var/log/derp_updater.log}"
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

  [[ -e "$key" ]] || mv "$tmp_key" "$key"
  [[ -e "$crt" ]] || mv "$tmp_crt" "$crt"
}

main() {
  local env_file="${DERP_ENV_FILE:-/etc/derp/derp.env}"
  # 注意：该脚本通常由 systemd 运行，unit 已通过 EnvironmentFile 注入变量。
  # 因此这里不再 source env_file（避免因未加引号的空格导致语法错误）。

  : "${DERP_ADDR:=:443}"
  : "${DERP_STUN_PORT:=3478}"
  : "${DERP_CERTMODE:=manual}"
  : "${DERP_CERTDIR:=/etc/derp}"
  : "${DERP_HTTP_PORT:=80}"
  : "${DERP_EXTRA_ARGS:=}"

  local ip
  ip="$(get_public_ip)"
  if [[ -z "$ip" ]]; then
    log "错误：无法获取公网 IP，退出"
    exit 1
  fi

  set_kv_in_env_file "$env_file" "DERP_HOSTNAME" "$ip"
  set_kv_in_env_file "$env_file" "DERP_CERTMODE" "$DERP_CERTMODE"
  set_kv_in_env_file "$env_file" "DERP_CERTDIR" "$DERP_CERTDIR"

  if [[ "$DERP_CERTMODE" == "manual" ]]; then
    generate_self_signed_ip_cert "$DERP_CERTDIR" "$ip"
  fi

  exec /usr/local/bin/derper \
    -hostname "$ip" \
    -a "$DERP_ADDR" \
    -stun-port "$DERP_STUN_PORT" \
    -certmode "$DERP_CERTMODE" \
    -certdir "$DERP_CERTDIR" \
    -http-port "$DERP_HTTP_PORT" \
    $DERP_EXTRA_ARGS
}

main "$@"

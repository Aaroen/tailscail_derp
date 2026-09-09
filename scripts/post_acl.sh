#!/usr/bin/env bash
set -euo pipefail

umask 077

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${DERP_UPDATER_LOG:-/var/log/derp_updater.log}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "缺少依赖命令：$1"; exit 1; }
}

main() {
  require_cmd curl
  require_cmd python3

  : "${TAILSCALE_API_KEY:?需要设置 TAILSCALE_API_KEY（不要提交到 GitHub）}"
  : "${TAILSCALE_TAILNET:?需要设置 TAILSCALE_TAILNET}"

  : "${DERP_REGION_ID:?需要设置 DERP_REGION_ID（例如 903）}"
  : "${DERP_REGION_CODE:=my-derp}"
  : "${DERP_REGION_NAME:=My DERP}"
  : "${DERP_NODE_NAME:=derp-1}"
  : "${DERP_HOSTNAME:?需要设置 DERP_HOSTNAME（IP 或域名）}"
  : "${DERP_PORT:=443}"
  : "${STUN_PORT:=3478}"
  : "${DERP_INSECURE_FOR_TESTS:=true}"

  local url="https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}/acl"
  local tmp_in="/tmp/tailscale_acl_current.json"
  local tmp_out="/tmp/tailscale_acl_updated.json"

  log "获取当前 ACL..."
  # 必须请求 application/json:Tailscale ACL API 默认返回 HuJSON(带注释/尾逗号),
  # 下方 python json 模块无法解析,会 404/解析失败。加此 header 让其返回纯 JSON。
  curl -fsS --header "Authorization: Bearer ${TAILSCALE_API_KEY}" --header "Accept: application/json" "$url" >"$tmp_in"

  log "仅更新 derpMap（不覆盖其它 ACL 字段）..."
  python3 - "$tmp_in" "$tmp_out" <<'PY'
import json
import os
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
with open(src_path, "r", encoding="utf-8") as f:
  data = json.load(f)

derp_map = data.get("derpMap")
if not isinstance(derp_map, dict):
  derp_map = {}
data["derpMap"] = derp_map

regions = derp_map.get("Regions")
if not isinstance(regions, dict):
  regions = {}
derp_map["Regions"] = regions

region_id = str(os.environ["DERP_REGION_ID"])
region_id_int = int(os.environ["DERP_REGION_ID"])

node = {
  "Name": os.environ.get("DERP_NODE_NAME", "derp-1"),
  "RegionID": region_id_int,
  "HostName": os.environ["DERP_HOSTNAME"],
  "DERPPort": int(os.environ.get("DERP_PORT", "443")),
  "STUNPort": int(os.environ.get("STUN_PORT", "3478")),
  "InsecureForTests": os.environ.get("DERP_INSECURE_FOR_TESTS", "true").lower() == "true",
}

regions[region_id] = {
  "RegionID": region_id_int,
  "RegionCode": os.environ.get("DERP_REGION_CODE", "my-derp"),
  "RegionName": os.environ.get("DERP_REGION_NAME", "My DERP"),
  "Nodes": [node],
}

with open(dst_path, "w", encoding="utf-8") as f:
  json.dump(data, f, ensure_ascii=False, indent=2)
  f.write("\n")
PY

  local status
  status="$(curl -s -o /dev/null -w "%{http_code}" -X POST --data-binary "@${tmp_out}" --header "Authorization: Bearer ${TAILSCALE_API_KEY}" "$url")"

  if [[ "$status" != "200" ]]; then
    log "错误：ACL 更新失败，HTTP $status"
    exit 1
  fi

  log "ACL 更新成功（derpMap 已更新）"
}

main "$@"

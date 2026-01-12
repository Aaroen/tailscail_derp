#!/usr/bin/env bash
set -euo pipefail

umask 077

out="${1:-/tmp/acl_to_post.json}"

: "${TAILSCALE_TAILNET:?需要设置 TAILSCALE_TAILNET（例如 example.com 或 email）}"
: "${DERP_REGION_ID:?需要设置 DERP_REGION_ID（例如 902）}"
: "${DERP_REGION_CODE:=my-derp}"
: "${DERP_REGION_NAME:=My DERP}"
: "${DERP_NODE_NAME:=derp-1}"
: "${DERP_HOSTNAME:?需要设置 DERP_HOSTNAME（IP 或域名）}"
: "${DERP_PORT:=443}"
: "${STUN_PORT:=3478}"

cat >"$out" <<EOF
{
  "tagOwners": {
    "tag:linux-server": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["*:*"]
    }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot", "root"]
    }
  ],
  "derpMap": {
    "OmitDefaultRegions": false,
    "Regions": {
      "${DERP_REGION_ID}": {
        "RegionID": ${DERP_REGION_ID},
        "RegionCode": "${DERP_REGION_CODE}",
        "RegionName": "${DERP_REGION_NAME}",
        "Nodes": [
          {
            "Name": "${DERP_NODE_NAME}",
            "RegionID": ${DERP_REGION_ID},
            "HostName": "${DERP_HOSTNAME}",
            "DERPPort": ${DERP_PORT},
            "STUNPort": ${STUN_PORT},
            "InsecureForTests": true
          }
        ]
      }
    }
  }
}
EOF

echo "$out"

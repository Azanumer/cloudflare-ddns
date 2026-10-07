#!/usr/bin/env bash
# update-dns.sh — Cloudflare Dynamic DNS updater (IPv4 and/or IPv6).
#
# Usage: update-dns.sh [--config /etc/cfddns.conf]
#
# Config file format (key=value, one per line):
#   CF_API_TOKEN=your_cloudflare_api_token   # needs Zone:DNS:Edit on the zone
#   ZONE=example.com
#   HOSTS="home router"                      # hostnames inside ZONE, "@" = apex
#   V4=yes                                   # update A records (default yes)
#   V6=no                                    # update AAAA records (default no)
#
# Skips the API call when the public IP hasn't changed (state in /var/lib/cfddns).
set -euo pipefail

CONFIG="${1:-/etc/cfddns.conf}"
if [[ "${1:-}" == --config ]]; then CONFIG="${2:-/etc/cfddns.conf}"; fi
[[ -r "$CONFIG" ]] || { echo "Config not readable: $CONFIG" >&2; exit 1; }

# shellcheck disable=SC1090
source "$CONFIG"

: "${CF_API_TOKEN:?CF_API_TOKEN missing in $CONFIG}"
: "${ZONE:?ZONE missing in $CONFIG}"
HOSTS="${HOSTS:-@}"
V4="${V4:-yes}"
V6="${V6:-no}"
STATE_DIR="${STATE_DIR:-/var/lib/cfddns}"
mkdir -p "$STATE_DIR"

API=https://api.cloudflare.com/client/v4

cf() { # cf METHOD PATH [DATA]
    curl -sfS -X "$1" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        ${3:+--data "$3"} \
        "$API$2"
}

public_ip() {
    case "$1" in
        A)    curl -sfS --max-time 15 https://api.ipify.org ;;
        AAAA) curl -sfS --max-time 15 https://api64.ipify.org ;;
    esac
}

zone_id() {
    cf GET "/zones?name=$ZONE" | grep -o '"id":"[a-f0-9]\{32\}"' | head -1 | cut -d'"' -f4
}

update_one() { # HOSTNAME TYPE IP
    local name="$1" type="$2" ip="$3"
    local fqdn="$name"
    [[ "$name" == "@" ]] && fqdn="$ZONE" || fqdn="$name.$ZONE"
    local state="$STATE_DIR/$fqdn-$type"

    if [[ -f "$state" && "$(cat "$state")" == "$ip" ]]; then
        echo "SKIP $fqdn ($type) — IP unchanged ($ip)"
        return 0
    fi

    local zid
    zid=$(zone_id) || { echo "FAIL $fqdn — cannot resolve zone id" >&2; return 1; }
    [[ -n "$zid" ]] || { echo "FAIL $fqdn — zone $ZONE not found" >&2; return 1; }

    local rec
    rec=$(cf GET "/zones/$zid/dns_records?type=$type&name=$fqdn" \
        | grep -o '"id":"[a-f0-9]\{32\}"' | head -1 | cut -d'"' -f4)

    local payload
    payload=$(printf '{"type":"%s","name":"%s","content":"%s","ttl":300,"proxied":false}' \
        "$type" "$fqdn" "$ip")

    if [[ -n "$rec" ]]; then
        cf PUT "/zones/$zid/dns_records/$rec" "$payload" >/dev/null \
            && echo "OK   $fqdn ($type) -> $ip (updated)"
    else
        cf POST "/zones/$zid/dns_records" "$payload" >/dev/null \
            && echo "OK   $fqdn ($type) -> $ip (created)"
    fi

    echo "$ip" > "$state"
}

failed=0
for fam in A AAAA; do
    want=yes
    [[ "$fam" == A ]] && want="$V4"
    [[ "$fam" == AAAA ]] && want="$V6"
    [[ "$want" == yes ]] || continue

    ip=$(public_ip "$fam") || { echo "FAIL — cannot detect public $fam address" >&2; failed=1; continue; }
    for host in $HOSTS; do
        update_one "$host" "$fam" "$ip" || failed=1
    done
done

exit "$failed"

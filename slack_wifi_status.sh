#!/bin/bash
# =============================================================
# slack_wifi_status.sh — Update Slack status based on WiFi
# Triggered automatically by LaunchAgent on network changes.
#
# Edit the NETWORK → STATUS MAPPINGS section below,
# then run: ./install_slack_wifi_status.sh
# =============================================================

# ---- NETWORK → STATUS MAPPINGS ------------------------------
# Returns "status text|:emoji:" for a given SSID.
# Patterns are matched top-to-bottom; use * for wildcards.
get_status() {
    local ssid="$1"
    case "$ssid" in
        "Bespin")
            echo "Working from home|:house_with_garden:"
            ;;
        "Gangverk")
            echo "At the Gangverk office|:office:"
            ;;
        "Origo-Gestir" | H158*)
            echo "At Helix offices|:office:"
            ;;
        "iLuks")
            # Mobile hotspot / 5G
            echo "On the move|:iphone:"
            ;;
        "")
            # No wifi
            echo "On the move|:iphone:"
            ;;
        *)
            # Unknown network
            echo "On the move|:iphone:"
            ;;
    esac
}
# ---- END CONFIG ---------------------------------------------

LOG="$HOME/.slack_wifi_status.log"
TOKEN_FILE="$HOME/.config/slack-wifi-status/token"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Read token
if [[ ! -f "$TOKEN_FILE" ]]; then
    log "ERROR: Token file not found at $TOKEN_FILE — run install_slack_wifi_status.sh"
    exit 1
fi
SLACK_TOKEN=$(cat "$TOKEN_FILE")

# Get current WiFi SSID
WIFI_IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
RAW=$(networksetup -getairportnetwork "$WIFI_IF" 2>/dev/null)

if [[ "$RAW" == *"not associated"* ]] || [[ -z "$RAW" ]]; then
    SSID=""
else
    SSID="${RAW#Current Wi-Fi Network: }"
fi

log "WiFi: '${SSID:-<none>}'"

# Resolve status
MAPPING=$(get_status "$SSID")
STATUS_TEXT="${MAPPING%%|*}"
STATUS_EMOJI="${MAPPING##*|}"

log "Setting: $STATUS_TEXT $STATUS_EMOJI"

# Build JSON safely with python3
PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({'profile': {
    'status_text':       sys.argv[1],
    'status_emoji':      sys.argv[2],
    'status_expiration': 0,
}}))
" "$STATUS_TEXT" "$STATUS_EMOJI")

# Post to Slack
RESPONSE=$(curl -s -X POST "https://slack.com/api/users.profile.set" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$PAYLOAD")

if echo "$RESPONSE" | grep -q '"ok":true'; then
    log "OK"
else
    log "ERROR: $RESPONSE"
fi

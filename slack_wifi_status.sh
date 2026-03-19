#!/bin/bash
# slack_wifi_status.sh — Update Slack status based on WiFi
# Triggered automatically by LaunchAgent on network changes.
# Configure via: ~/.config/slack-wifi-status/networks.conf

CONFIG_DIR="$HOME/.config/slack-wifi-status"
TOKEN_FILE="$CONFIG_DIR/token"
NETWORKS_FILE="$CONFIG_DIR/networks.conf"
LOG="$HOME/.slack_wifi_status.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Read token
if [[ ! -f "$TOKEN_FILE" ]]; then
    log "ERROR: Token file not found — run install.sh"
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

# Look up SSID in networks.conf (supports glob patterns)
# Format: PATTERN|status text|:emoji:
STATUS_TEXT=""
STATUS_EMOJI=""

if [[ -f "$NETWORKS_FILE" ]]; then
    while IFS='|' read -r pattern text emoji; do
        # Skip comments and blank lines
        [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${pattern// }" ]] && continue
        # Trim whitespace
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        # Glob match (unquoted $pattern is intentional)
        # shellcheck disable=SC2053
        if [[ "$SSID" == $pattern ]]; then
            STATUS_TEXT="${text#"${text%%[![:space:]]*}"}"
            STATUS_TEXT="${STATUS_TEXT%"${STATUS_TEXT##*[![:space:]]}"}"
            STATUS_EMOJI="${emoji#"${emoji%%[![:space:]]*}"}"
            STATUS_EMOJI="${STATUS_EMOJI%"${STATUS_EMOJI##*[![:space:]]}"}"
            break
        fi
    done < "$NETWORKS_FILE"
fi

# Fall back to defaults if no match (unknown network or no wifi)
if [[ -z "$STATUS_TEXT" ]]; then
    STATUS_TEXT="On the move"
    STATUS_EMOJI=":iphone:"
fi

log "Setting: $STATUS_TEXT $STATUS_EMOJI"

# Build JSON safely and post to Slack
PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({'profile': {
    'status_text':       sys.argv[1],
    'status_emoji':      sys.argv[2],
    'status_expiration': 0,
}}))
" "$STATUS_TEXT" "$STATUS_EMOJI")

RESPONSE=$(curl -s -X POST "https://slack.com/api/users.profile.set" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$PAYLOAD")

if echo "$RESPONSE" | grep -q '"ok":true'; then
    log "OK"
else
    log "ERROR: $RESPONSE"
fi

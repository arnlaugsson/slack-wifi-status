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

# Use default gateway IP as network fingerprint — works without location services
GATEWAY=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')

log "Gateway: '${GATEWAY:-<none>}'"

# Look up gateway in networks.conf (supports glob patterns)
# Format: GATEWAY_PATTERN | status text | :emoji:
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
        if [[ "$GATEWAY" == $pattern ]]; then
            STATUS_TEXT="${text#"${text%%[![:space:]]*}"}"
            STATUS_TEXT="${STATUS_TEXT%"${STATUS_TEXT##*[![:space:]]}"}"
            STATUS_EMOJI="${emoji#"${emoji%%[![:space:]]*}"}"
            STATUS_EMOJI="${STATUS_EMOJI%"${STATUS_EMOJI##*[![:space:]]}"}"
            break
        fi
    done < "$NETWORKS_FILE"
fi

# Fall back to "On the move" for unknown/no network
if [[ -z "$STATUS_TEXT" ]]; then
    STATUS_TEXT="On the move"
    STATUS_EMOJI=":iphone:"
fi

log "Setting: $STATUS_TEXT $STATUS_EMOJI"

# Build JSON safely and post to Slack
# Statuses expire at 18:00 today; "On the move" never expires (0)
PAYLOAD=$(python3 -c "
import json, sys, time, datetime
text, emoji = sys.argv[1], sys.argv[2]
if text == 'On the move':
    expiry = 0
else:
    now = datetime.datetime.now()
    eod = now.replace(hour=18, minute=0, second=0, microsecond=0)
    # If already past 18:00, don't set an expiry in the past
    expiry = int(eod.timestamp()) if eod > now else 0
print(json.dumps({'profile': {
    'status_text':       text,
    'status_emoji':      emoji,
    'status_expiration': expiry,
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

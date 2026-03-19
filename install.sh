#!/bin/bash
# =============================================================
# slack-wifi-status installer
# Usage (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/arnlaugsson/slack-wifi-status/main/install.sh)
# Or locally:
#   ./install.sh
# =============================================================

set -e

INSTALL_DIR="$HOME/.slack-wifi-status"
CONFIG_DIR="$HOME/.config/slack-wifi-status"
TOKEN_FILE="$CONFIG_DIR/token"
NETWORKS_FILE="$CONFIG_DIR/networks.conf"
PLIST_LABEL="com.local.slack-wifi-status"
PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
WORKER="$INSTALL_DIR/slack_wifi_status.sh"

# ---------- helpers ------------------------------------------
bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }

ask() {
    # ask PROMPT DEFAULT
    local prompt="$1" default="$2"
    [[ -n "$default" ]] && prompt="$prompt [$(dim "$default")]"
    printf '%s: ' "$prompt"
    read -r reply
    echo "${reply:-$default}"
}

ask_secret() {
    printf '%s: ' "$1"
    read -rs reply
    echo
    echo "$reply"
}

# ---------- install / update repo ----------------------------
echo
echo "$(bold 'slack-wifi-status')"
echo "─────────────────────────────────────────"

# Detect if running from within the cloned repo already
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
if [[ -f "$SCRIPT_PATH/slack_wifi_status.sh" ]] && [[ "$SCRIPT_PATH" != "$INSTALL_DIR" ]]; then
    # Running locally from repo (dev / first-time from hacks)
    echo "Installing from local repo → $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_PATH/slack_wifi_status.sh" "$INSTALL_DIR/"
    chmod +x "$WORKER"
elif [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Updating existing installation..."
    git -C "$INSTALL_DIR" pull --quiet
else
    REPO_URL="https://github.com/arnlaugsson/slack-wifi-status.git"
    echo "Cloning to $INSTALL_DIR..."
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
    chmod +x "$WORKER"
fi

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# ---------- Slack token --------------------------------------
echo
if [[ -f "$TOKEN_FILE" ]]; then
    echo "Slack token already saved. $(dim 'Delete ~/.config/slack-wifi-status/token to replace.')"
else
    echo "$(bold 'Slack token')"
    echo "Create one at: https://api.slack.com/apps"
    echo "  → OAuth & Permissions → add 'users.profile:write' scope → install app → copy User OAuth Token"
    echo
    TOKEN=$(ask_secret "Token (xoxp-...)")
    if [[ -z "$TOKEN" ]]; then
        echo "ERROR: No token provided." >&2; exit 1
    fi
    # Verify token
    printf 'Verifying token... '
    RESULT=$(curl -s -X POST "https://slack.com/api/auth.test" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json")
    if echo "$RESULT" | grep -q '"ok":true'; then
        USER_NAME=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('user',''))" 2>/dev/null || echo "unknown")
        echo "$(green "✓") ($USER_NAME)"
        echo "$TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
    else
        echo "failed."
        echo "ERROR: Token verification failed. Check the token and try again." >&2
        exit 1
    fi
fi

# ---------- Network mappings ---------------------------------
echo
echo "$(bold 'Network → Status mappings')"

if [[ -f "$NETWORKS_FILE" ]]; then
    echo "Current mappings:"
    grep -v '^#' "$NETWORKS_FILE" | grep -v '^[[:space:]]*$' | while IFS='|' read -r ssid text emoji; do
        printf '  %-30s %s %s\n' "$ssid" "$emoji" "$text"
    done
    echo
    RECONFIGURE=$(ask "Reconfigure mappings? (y/N)" "n")
    [[ "$RECONFIGURE" != "y" && "$RECONFIGURE" != "Y" ]] && SKIP_NETWORKS=true
fi

if [[ -z "$SKIP_NETWORKS" ]]; then
    echo
    echo "Enter the default gateway IP for each network."
    echo "Find it on any network with: route -n get default | awk '/gateway/{print \$2}'"
    echo "Press Enter to skip. Glob patterns supported (e.g. 10.10.*)."
    echo

    CONF_LINES=()
    CONF_LINES+=("# slack-wifi-status network mappings")
    CONF_LINES+=("# Format: GATEWAY_IP (glob ok) | status text | :emoji:")
    CONF_LINES+=("# Find your gateway: route -n get default | awk '/gateway/{print \$2}'")
    CONF_LINES+=("")

    # Prompt for common scenarios
    for LABEL in "Home" "Office 1" "Office 2" "Mobile hotspot"; do
        case "$LABEL" in
            "Home")           DEFAULT_TEXT="Working from home"; DEFAULT_EMOJI=":house_with_garden:" ;;
            "Mobile hotspot") DEFAULT_TEXT="On the move";       DEFAULT_EMOJI=":iphone:"            ;;
            *)                DEFAULT_TEXT="At the office";     DEFAULT_EMOJI=":office:"            ;;
        esac

        echo "$(bold "$LABEL")"
        GATEWAY=$(ask "  Gateway IP" "")
        [[ -z "$GATEWAY" ]] && echo && continue
        TEXT=$(ask "  Status text" "$DEFAULT_TEXT")
        EMOJI=$(ask "  Emoji" "$DEFAULT_EMOJI")
        CONF_LINES+=("$GATEWAY | $TEXT | $EMOJI")
        echo
    done

    # Write config
    printf '%s\n' "${CONF_LINES[@]}" > "$NETWORKS_FILE"
    echo "Mappings saved to $NETWORKS_FILE"
fi

# ---------- LaunchAgent --------------------------------------
echo
echo "$(bold 'Installing LaunchAgent...')"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$WORKER</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/etc/resolv.conf</string>
        <string>/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist</string>
        <string>/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.slack_wifi_status.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.slack_wifi_status.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo
echo "$(green '✓') Done! Status will update automatically on every network change."
echo
echo "$(dim 'Commands:')"
echo "  $(dim 'bash ~/.slack-wifi-status/slack_wifi_status.sh   # trigger now')"
echo "  $(dim 'tail -f ~/.slack_wifi_status.log                  # watch log')"
echo "  $(dim "launchctl unload $PLIST   # disable")"

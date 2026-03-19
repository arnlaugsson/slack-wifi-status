#!/bin/bash
# =============================================================
# install_slack_wifi_status.sh — One-time setup
# Saves your Slack token and installs the LaunchAgent so
# slack_wifi_status.sh runs automatically on network changes.
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER="$SCRIPT_DIR/slack_wifi_status.sh"
PLIST_LABEL="com.local.slack-wifi-status"
PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
TOKEN_DIR="$HOME/.config/slack-wifi-status"
TOKEN_FILE="$TOKEN_DIR/token"

# Ensure worker is executable
chmod +x "$WORKER"

# Save Slack token
mkdir -p "$TOKEN_DIR"
chmod 700 "$TOKEN_DIR"

if [[ -f "$TOKEN_FILE" ]]; then
    echo "Token already saved. To replace it, delete $TOKEN_FILE and re-run."
else
    echo -n "Slack user token (xoxp-...): "
    read -rs SLACK_TOKEN
    echo
    if [[ -z "$SLACK_TOKEN" ]]; then
        echo "ERROR: No token entered." >&2
        exit 1
    fi
    echo "$SLACK_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "Token saved to $TOKEN_FILE"
fi

# Write LaunchAgent plist
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

    <!-- Trigger on any network change -->
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

# Load (or reload) the agent
launchctl unload "$PLIST" 2>/dev/null
launchctl load -w "$PLIST"

echo ""
echo "LaunchAgent installed and running."
echo "Status will update automatically on every network change."
echo ""
echo "Useful commands:"
echo "  tail -f ~/.slack_wifi_status.log   # watch live"
echo "  bash $WORKER                       # trigger manually"
echo "  launchctl unload $PLIST            # disable"

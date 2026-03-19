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

# ---------- Slack app credentials ----------------------------
# One app shared by all users — maintainer fills these in once.
# Requires: OAuth redirect URI http://localhost:9876/callback
#           User scope: users.profile:write
#           Manage Distribution → public distribution enabled
SLACK_CLIENT_ID="REPLACE_WITH_CLIENT_ID"
SLACK_CLIENT_SECRET="REPLACE_WITH_CLIENT_SECRET"
OAUTH_PORT=9876
# -------------------------------------------------------------

# ---------- helpers ------------------------------------------
bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }

ask() {
    local prompt="$1" default="$2"
    [[ -n "$default" ]] && prompt="$prompt [$(dim "$default")]"
    printf '%s: ' "$prompt"
    read -r reply
    echo "${reply:-$default}"
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

# ---------- Slack authorisation ------------------------------
echo
if [[ -f "$TOKEN_FILE" ]]; then
    echo "Slack already authorised. $(dim 'Delete ~/.config/slack-wifi-status/token to re-authorise.')"
else
    echo "$(bold 'Authorising with Slack...')"
    echo "A browser window will open — click Allow to continue."
    echo

    OAUTH_CODE_FILE=$(mktemp)
    OAUTH_ERROR_FILE=$(mktemp)

    # Start a local HTTP server to catch the OAuth callback
    python3 - "$OAUTH_PORT" "$OAUTH_CODE_FILE" "$OAUTH_ERROR_FILE" << 'PYEOF' &
import http.server, urllib.parse, sys, threading, os

port       = int(sys.argv[1])
code_file  = sys.argv[2]
error_file = sys.argv[3]

HTML_OK  = b"<html><body style='font-family:sans-serif;padding:2em'><h2>&#x2705; Authorised!</h2><p>You can close this tab and return to the terminal.</p></body></html>"
HTML_ERR = b"<html><body style='font-family:sans-serif;padding:2em'><h2>&#x274C; Authorisation failed</h2><p>Check the terminal for details.</p></body></html>"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if 'code' in params:
            open(code_file, 'w').write(params['code'][0])
            self.send_response(200); self.send_header('Content-type','text/html'); self.end_headers()
            self.wfile.write(HTML_OK)
        else:
            err = params.get('error', ['unknown'])[0]
            open(error_file, 'w').write(err)
            self.send_response(400); self.send_header('Content-type','text/html'); self.end_headers()
            self.wfile.write(HTML_ERR)
        threading.Thread(target=self.server.shutdown, daemon=True).start()
    def log_message(self, *a): pass

http.server.HTTPServer(('localhost', port), Handler).serve_forever()
PYEOF

    OAUTH_SERVER_PID=$!

    # Open browser to Slack OAuth
    REDIRECT_URI="http://localhost:${OAUTH_PORT}/callback"
    OAUTH_URL="https://slack.com/oauth/v2/authorize?client_id=${SLACK_CLIENT_ID}&user_scope=users.profile:write&redirect_uri=${REDIRECT_URI}"
    open "$OAUTH_URL"

    # Wait up to 120s for the callback
    for i in $(seq 1 120); do
        if [[ -s "$OAUTH_CODE_FILE" ]]; then break; fi
        if [[ -s "$OAUTH_ERROR_FILE" ]]; then
            echo "ERROR: Slack returned: $(cat "$OAUTH_ERROR_FILE")" >&2
            kill "$OAUTH_SERVER_PID" 2>/dev/null; rm -f "$OAUTH_CODE_FILE" "$OAUTH_ERROR_FILE"; exit 1
        fi
        sleep 1
    done

    kill "$OAUTH_SERVER_PID" 2>/dev/null

    CODE=$(cat "$OAUTH_CODE_FILE" 2>/dev/null)
    rm -f "$OAUTH_CODE_FILE" "$OAUTH_ERROR_FILE"

    if [[ -z "$CODE" ]]; then
        echo "ERROR: Timed out waiting for authorisation." >&2; exit 1
    fi

    # Exchange code for token
    printf 'Exchanging code for token... '
    RESULT=$(curl -s -X POST "https://slack.com/api/oauth.v2.access" \
        --data-urlencode "client_id=${SLACK_CLIENT_ID}" \
        --data-urlencode "client_secret=${SLACK_CLIENT_SECRET}" \
        --data-urlencode "code=${CODE}" \
        --data-urlencode "redirect_uri=${REDIRECT_URI}")

    TOKEN=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('authed_user',{}).get('access_token',''))" <<< "$RESULT")
    USER_NAME=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('authed_user',{}).get('id',''))" <<< "$RESULT")

    if [[ -z "$TOKEN" ]]; then
        echo "failed."
        echo "ERROR: $(python3 -c "import json,sys; print(json.load(sys.stdin).get('error','unknown'))" <<< "$RESULT")" >&2
        exit 1
    fi

    echo "$(green "✓") ($USER_NAME)"
    echo "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
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

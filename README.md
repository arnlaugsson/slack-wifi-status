# slack-wifi-status

Automatically updates your Slack status based on which Wi-Fi network you're connected to. Runs as a macOS LaunchAgent, triggering on every network change.

- **Home network** → Working from home
- **Office network(s)** → At the office
- **Mobile hotspot / unknown** → On the move

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/arnlaugsson/slack-wifi-status/main/install.sh)
```

The installer will ask for your Slack token, then walk you through mapping networks to statuses.

## Requirements

- macOS
- A Slack account in the workspace you want to update (no admin rights needed)

## How it works

macOS restricts SSID access to apps with Location Services permission, which terminal apps typically don't have. This script identifies your network by its **default gateway IP** instead — no permissions needed.

## Configuration

Networks are stored in `~/.config/slack-wifi-status/networks.conf`:

```
# Format: GATEWAY_IP (glob patterns ok) | status text | :emoji:
#
# Find your gateway on any network:
#   route -n get default | awk '/gateway/{print $2}'

192.168.1.1  | Working from home       | :house_with_garden:
10.42.108.1  | At the office           | :office:
10.10.*      | At the other office     | :office:
```

Edit this file any time — no reinstall needed. Unknown networks and no-wifi fall back to "On the move".

## Usage

```bash
# Trigger manually
bash ~/.slack-wifi-status/slack_wifi_status.sh

# Watch the log
tail -f ~/.slack_wifi_status.log

# Disable
launchctl unload ~/Library/LaunchAgents/com.local.slack-wifi-status.plist

# Re-enable
launchctl load -w ~/Library/LaunchAgents/com.local.slack-wifi-status.plist
```

## For maintainers — one-time Slack app setup

Users don't need to create anything. You set up one shared Slack app:

1. [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → From scratch
2. **OAuth & Permissions** → User Token Scopes → add `users.profile:write`
3. **OAuth & Permissions** → Redirect URLs → add `http://localhost:9876/callback`
4. **Manage Distribution** → enable **Remove Hard Coded Information** + **Activate Public Distribution**
5. Copy **Client ID** and **Client Secret** from Basic Information into `install.sh`

# slack-wifi-status

Automatically updates your Slack status based on which Wi-Fi network you're connected to. Runs as a macOS LaunchAgent, triggering on every network change.

- **Home network** → Working from home
- **Office network(s)** → At the office
- **Mobile hotspot / unknown** → On the move

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/arnlaugsson/slack-wifi-status/main/install.sh)
```

The installer will ask for your Slack token, then walk you through mapping SSIDs to statuses. No config file editing required.

## Requirements

- macOS
- A Slack user token (`xoxp-...`) with `users.profile:write` scope → [how to get one](#getting-a-slack-token)

## Configuration

Networks are stored in `~/.config/slack-wifi-status/networks.conf`:

```
# Format: SSID (glob patterns ok) | status text | :emoji:
Bespin       | Working from home    | :house_with_garden:
MyOffice     | At the office        | :office:
Office-5G*   | At the office        | :office:
MyHotspot    | On the move          | :iphone:
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

## Getting a Slack token

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → From scratch
2. **OAuth & Permissions** → User Token Scopes → add `users.profile:write`
3. **Install to Workspace** → copy the **User OAuth Token** (`xoxp-...`)

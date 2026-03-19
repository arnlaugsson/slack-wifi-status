# slack-wifi-status

Automatically updates your Slack status based on which Wi-Fi network you're connected to. Runs as a macOS LaunchAgent, triggering on every network change.

## How it works

- **Known office network** → sets office status
- **Home network** → sets working from home
- **Mobile hotspot** → sets on the move
- **Unknown / no Wi-Fi** → sets on the move

## Requirements

- macOS
- A Slack [user token](https://api.slack.com/authentication/token-types#user) (`xoxp-...`) with `users.profile:write` scope

## Setup

**1. Edit your network mappings** in `slack_wifi_status.sh`:

```bash
"YourHomeSSID")
    echo "Working from home|:house_with_garden:"
    ;;
"YourOfficeSSID")
    echo "At the office|:office:"
    ;;
```

**2. Run the installer:**

```bash
./install_slack_wifi_status.sh
```

It will prompt for your Slack token (stored in `~/.config/slack-wifi-status/token`, `chmod 600`), write the LaunchAgent plist, and load it.

## Usage

```bash
# Trigger manually
bash slack_wifi_status.sh

# Watch the log
tail -f ~/.slack_wifi_status.log

# Disable
launchctl unload ~/Library/LaunchAgents/com.local.slack-wifi-status.plist

# Re-enable
launchctl load -w ~/Library/LaunchAgents/com.local.slack-wifi-status.plist
```

## Getting a Slack token

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create an app
2. Under **OAuth & Permissions**, add the `users.profile:write` scope
3. Install the app to your workspace and copy the **User OAuth Token** (`xoxp-...`)

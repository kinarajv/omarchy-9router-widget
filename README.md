# Omarchy 9Router AI Monitor Widget

An ultra-lightweight Quickshell top-bar widget and interactive dashboard flyout for Omarchy Linux that tracks 9Router AI Gateway infrastructure, provider connection health, and live token usage quotas.

---

## Overview

When orchestrating multi-model AI coding agents (such as Hermes, Codex, Claude Code, and OpenCode) routed through a unified 9Router gateway, monitoring token burn rates and detecting rate-limit lockouts (`429`) in real time is essential.

**Omarchy 9Router Monitor** brings live gateway intelligence directly to the desktop status bar:
- **Clean Bar Presence**: Displays the router icon alongside formatted aggregate daily tokens (e.g. `󰒋 391.3M`).
- **Zero Idle Footprint**: The background data poller is compiled in native Zig (`ReleaseSmall`), executing in under 35ms with negligible memory overhead (~5 MB peak RSS during refresh).
- **Comprehensive Flyout Panel**: Left-click the status bar item to inspect requests, token volumes, estimated spend, and per-account connection statuses.
- **Quota Lock Alerts**: Color-coded status dots surface quota limits, model locks, and authentication drops instantly.
- **One-Click Actions**: Open the full web dashboard or trigger an on-demand data refresh directly from the panel.

---

## Visual Behavior & UX

### Top Bar Item
- **Left-click**: Toggles the interactive 9Router dashboard flyout panel.
- **Right-click**: Opens the 9Router Web Dashboard in your default browser.
- **Tooltip**: Displays an immediate summary of online connectivity, today's request count, total tokens, and enabled provider breakdowns.

### Flyout Panel Components

| UI Element | Function | UX Details |
| :--- | :--- | :--- |
| **Header** | Gateway title, online status badge, and date | Green indicator confirms active connectivity. |
| **Metric Cards** | Requests, Tokens, and Active Accounts | High-contrast KPI cards showing daily volume and estimated cost. |
| **Account List** | Individual provider cards (Claude, OpenAI, Gemini) | Displays display name/email, provider badge, priority rank, requests, and token volume. |
| **Status Indicators** | Green (`active`), Orange (`locked`), Red (`quota 429` / `unavailable`) | Pinpoints which provider credentials have exhausted quota. |
| **Footer Actions** | "Open Web Dashboard" and "Refresh Data" | Fast access to gateway management and manual polling trigger. |

---

## Prerequisites

- **Desktop**: Omarchy Linux with `omarchy-shell` / `quickshell`.
- **Compiler (Optional for build)**: `zig` 0.13+ or 0.16+ (a precompiled executable and Python fallback are included).
- **Network**: SSH access or local access to the host running the 9Router SQLite database.

---

## Configuration Guide

The widget supports flexible configuration via a local JSON file, a global user config, or shell environment variables.

### Configuration File Locations

The fetcher checks configuration in the following order of priority:
1. Environment variables (highest priority)
2. Plugin-local config: `~/.config/omarchy/plugins/kinara.9router/config.json`
3. Global user config: `~/.config/omarchy/9router.json`

To set up your configuration, copy `config.example.json`:

```bash
cp config.example.json config.json
```

### Configuration Options Reference

| Key | Environment Variable | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `mode` | `ROUTER_MODE` | `"ssh"` | Polling mode: `"ssh"` for remote hosts, `"local"` for local SQLite DB |
| `sshTarget` | `ROUTER_SSH_TARGET` | `"user@router-host"` | SSH destination (`user@host` or SSH alias) |
| `lxcId` | `ROUTER_LXC_ID` | `"109"` | Proxmox LXC container identifier running 9Router |
| `dbPath` | `ROUTER_DB_PATH` | `/var/lib/docker/volumes/9router-data/_data/db/data.sqlite` | Absolute path to the 9Router SQLite database file |
| `dashboardUrl` | `ROUTER_DASHBOARD_URL` | `http://router-host:20128/dashboard` | Web dashboard URL opened on click |
| `gatewayHost` | `ROUTER_GATEWAY_HOST` | `"router-host:20128"` | Subtitle display label shown in the panel header |
| `fetchCmd` | `ROUTER_FETCH_CMD` | `""` | Optional raw command override that outputs JSON to stdout |

---

### Configuration Examples

#### Example A: Remote Proxmox LXC Container (Default)
When 9Router is deployed inside a Proxmox LXC container accessible via SSH:

```json
{
  "mode": "ssh",
  "sshTarget": "root@192.168.0.2",
  "lxcId": "109",
  "dbPath": "/var/lib/docker/volumes/9router-data/_data/db/data.sqlite",
  "dashboardUrl": "http://192.168.0.44:20128/dashboard",
  "gatewayHost": "192.168.0.44:20128"
}
```

#### Example B: Local Docker / Native Service
When 9Router runs on the same machine as your desktop:

```json
{
  "mode": "local",
  "dbPath": "/var/lib/docker/volumes/9router-data/_data/db/data.sqlite",
  "dashboardUrl": "http://localhost:20128/dashboard",
  "gatewayHost": "localhost:20128"
}
```

#### Example C: Environment Variables in `~/.config/environment.d/9router.conf`
For systemd user sessions without creating a JSON file:

```ini
ROUTER_SSH_TARGET="root@192.168.0.2"
ROUTER_LXC_ID="109"
ROUTER_DASHBOARD_URL="http://192.168.0.44:20128/dashboard"
ROUTER_GATEWAY_HOST="192.168.0.44:20128"
```

---

## Installation & Setup

### 1. Clone into Omarchy Plugin Directory
Clone this repository into your user plugin folder:

```bash
git clone https://github.com/kinarajv/omarchy-9router-widget.git ~/.config/omarchy/plugins/kinara.9router
cd ~/.config/omarchy/plugins/kinara.9router
```

### 2. Configure Settings
Copy and edit your configuration:

```bash
cp config.example.json config.json
nano config.json
```

### 3. Build the Fetch Runner
Compile the native Zig poller:

```bash
./build.sh
```

If Zig is not installed on your system, `build.sh` automatically falls back to the Python runner (`fetch.py`).

### 4. Add to Omarchy Top Bar
Open `~/.config/omarchy/shell.json` and insert `kinara.9router` into your bar configuration:

```json
{
  "plugins": {
    "bar": [
      "omarchy.workspace-switcher",
      "kinara.9router",
      "omarchy.media-player",
      "omarchy.clock"
    ]
  }
}
```

### 5. Reload the Shell
Trigger Quickshell to load the new widget:

```bash
quickshell ipc -p /usr/share/omarchy/shell call kinara.9router open 2>/dev/null || systemctl --user restart quickshell
```

---

## Verification & Health Check

### Test Polling Execution
Run the fetch executable directly from your terminal:

```bash
~/.config/omarchy/plugins/kinara.9router/fetch
```

Expected output:
```json
{"status":"ok","barText":"401.2M","accounts":9}
```

Check the generated state cache:
```bash
cat ~/.local/state/omarchy/9router/usage.json | head -n 30
```

---

## Troubleshooting

### Widget shows "󰒋" without numbers
- Cause: The state file `~/.local/state/omarchy/9router/usage.json` has not been generated yet or connection timed out.
- Recovery: Run `./fetch` manually in terminal to observe the exact error.

### Permission Denied on SSH
- Cause: SSH public key authentication is not configured for the target host.
- Recovery: Authorize your SSH key on the router host:
  ```bash
  ssh-copy-id <user>@<router-host>
  ```

---

## Uninstallation

1. Remove `kinara.9router` from `~/.config/omarchy/shell.json`.
2. Delete the plugin directory:
   ```bash
   rm -rf ~/.config/omarchy/plugins/kinara.9router
   ```
3. Restart Quickshell:
   ```bash
   systemctl --user restart quickshell
   ```

---

## License

MIT License.

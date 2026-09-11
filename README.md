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
- **Right-click**: Opens the full 9Router Web Dashboard in your default browser.
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

## Installation & Setup

### 1. Clone into Omarchy Plugin Directory
Clone this repository into your user plugin folder:

```bash
git clone https://github.com/<your-username>/omarchy-9router-widget.git ~/.config/omarchy/plugins/kinara.9router
cd ~/.config/omarchy/plugins/kinara.9router
```

### 2. Build the Fetch Runner
Build the standalone Zig binary:

```bash
./build.sh
```

If Zig is not installed on your system, `build.sh` automatically falls back to the Python runner (`fetch.py`).

### 3. Configure Connection Environment (Optional)
By default, the script polls the gateway database over SSH. You can customize connection parameters by setting environment variables in `~/.config/environment.d/9router.conf` or your shell profile:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `ROUTER_FETCH_CMD` | Custom shell command that outputs the JSON payload | SSH Proxmox/Docker command |
| `ROUTER_SSH_TARGET` | SSH connection string for the container host | `root@192.168.0.2` |
| `ROUTER_LXC_ID` | Proxmox LXC container identifier | `109` |
| `ROUTER_DASHBOARD_URL` | Destination URL opened on click | `http://192.168.0.44:20128/dashboard` |

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

### Test Background Polling
Run the fetch binary directly in your terminal:

```bash
~/.config/omarchy/plugins/kinara.9router/fetch
```

Expected JSON output:
```json
{"status":"ok","barText":"391.3M","accounts":9}
```

Check the generated state cache file:
```bash
cat ~/.local/state/omarchy/9router/usage.json | head -n 30
```

---

## Troubleshooting

### Widget shows "󰒋" without numbers
- Cause: The state file `~/.local/state/omarchy/9router/usage.json` has not been generated yet or SSH timed out.
- Recovery: Run `./fetch` manually in terminal and check the output or error messages.

### Permission Denied on SSH
- Cause: SSH public key is not trusted on the Proxmox/router host.
- Recovery: Add your public key to the target host using `ssh-copy-id root@<host>`.

---

## Uninstallation

1. Remove `kinara.9router` from `~/.config/omarchy/shell.json`.
2. Delete the plugin folder:
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

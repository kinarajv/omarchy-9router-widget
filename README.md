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
- **Compiler (Optional for build)**: `zig` 0.13+ or 0.14+ (a precompiled executable is included).
- **Network**: HTTP access to the 9Router API endpoint.

---

## Configuration Guide

The widget reads usage through the 9Router HTTP API. It supports configuration via a local JSON file, a global user config, or shell environment variables.

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
| `target` | `ROUTER_TARGET` | `http://127.0.0.1:20128` | 9Router gateway host or base URL |
| `password` | `ROUTER_PASSWORD` | `""` | Dashboard login password used to auto-renew session token |

---

### Configuration Example

```json
{
  "target": "http://127.0.0.1:20128",
  "password": "your-9router-password"
}
```

#### Environment Variables in `~/.config/environment.d/9router.conf`

```ini
ROUTER_TARGET="http://127.0.0.1:20128"
ROUTER_PASSWORD="your-9router-password"
```

---

## Installation & Setup
 
### Method 1: Using the Omarchy Plugin Manager (Recommended)
Install directly from GitHub using the Omarchy CLI:

```bash
omarchy plugin add https://github.com/kinarajv/omarchy-9router-widget.git --enable
```

Then configure your endpoint:
```bash
cd ~/.config/omarchy/plugins/kinarajv.9router
cp config.example.json config.json
nano config.json
```

### Method 2: Manual Installation
Clone this repository into your user plugin folder:

```bash
git clone https://github.com/kinarajv/omarchy-9router-widget.git ~/.config/omarchy/plugins/kinarajv.9router
cd ~/.config/omarchy/plugins/kinarajv.9router
```

Configure Settings:
```bash
cp config.example.json config.json
nano config.json
```

Build or verify the fetch executable:
```bash
./build.sh
```

Enable the plugin:
```bash
omarchy plugin enable kinarajv.9router
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

### API returns `401 Unauthorized`
- Cause: 9Router authentication is enabled.
- Recovery: configure `ROUTER_API_TOKEN`, `ROUTER_API_KEY`, or `ROUTER_API_COOKIE`, then run the fetcher again.

---

## Uninstallation
 
### Using the Plugin Manager:
```bash
omarchy plugin disable kinarajv.9router
omarchy plugin remove kinarajv.9router --yes
```

### Manual Removal:
1. Remove `kinarajv.9router` from `~/.config/omarchy/shell.json`.
2. Delete the plugin directory:
   ```bash
   rm -rf ~/.config/omarchy/plugins/kinarajv.9router
   ```
3. Restart Quickshell:
   ```bash
   systemctl --user restart quickshell
   ```

---

## License

MIT License.

#!/usr/bin/env python3
import datetime
import json
import os
import subprocess
from pathlib import Path

CACHE_DIR = Path.home() / ".local" / "state" / "omarchy" / "9router"
CACHE_FILE = CACHE_DIR / "usage.json"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def format_tokens(num):
    if num >= 1_000_000_000:
        return f"{num / 1_000_000_000:.1f}B"
    if num >= 1_000_000:
        return f"{num / 1_000_000:.1f}M"
    if num >= 1_000:
        return f"{num / 1_000:.1f}k"
    return str(num)

def fetch():
    cmd = [
        "ssh", "-o", "ConnectTimeout=3", "-o", "BatchMode=yes", os.getenv("ROUTER_SSH_TARGET", "root@192.168.0.2"),
        f"pct exec {os.getenv('ROUTER_LXC_ID', '109')} -- python3 - <<'PY'\n"
        "import sqlite3, json, datetime\n"
        "db = '/var/lib/docker/volumes/9router-data/_data/db/data.sqlite'\n"
        "conn = sqlite3.connect(db)\n"
        "today = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')\n"
        "row = conn.execute('SELECT data FROM usageDaily WHERE dateKey=?', (today,)).fetchone()\n"
        "daily = json.loads(row[0]) if row else {}\n"
        "conns = conn.execute('SELECT id, provider, name, email, priority, isActive, data FROM providerConnections').fetchall()\n"
        "out = {'today': today, 'daily': daily, 'connections': []}\n"
        "for c in conns:\n"
        "    d = json.loads(c[6]) if c[6] else {}\n"
        "    out['connections'].append({\n"
        "        'id': c[0], 'provider': c[1], 'name': c[2], 'email': c[3],\n"
        "        'priority': c[4], 'isActive': bool(c[5]),\n"
        "        'testStatus': d.get('testStatus'), 'errorCode': d.get('errorCode'),\n"
        "        'lastError': d.get('lastError'), 'lastErrorAt': d.get('lastErrorAt'),\n"
        "        'locks': {k: v for k, v in d.items() if k.startswith('modelLock_') and v is not None}\n"
        "    })\n"
        "print(json.dumps(out))\n"
        "PY"
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
        if proc.returncode != 0:
            return {"error": proc.stderr.strip() or "SSH/exec failed", "online": False}
        raw = json.loads(proc.stdout)
    except Exception as exc:
        return {"error": str(exc), "online": False}

    daily = raw.get("daily") or {}
    connections = raw.get("connections") or []
    by_account = daily.get("byAccount") or {}

    total_requests = daily.get("requests") or 0
    prompt_tokens = daily.get("promptTokens") or 0
    comp_tokens = daily.get("completionTokens") or 0
    cached_tokens = daily.get("cachedTokens") or 0
    total_tokens = prompt_tokens + comp_tokens
    cost = daily.get("cost") or 0.0

    active_accounts = 0
    quota_limited = 0
    parsed_accounts = []
    providers_summary = {}

    for c in connections:
        cid = c["id"]
        p_type = c["provider"]
        email = c.get("email") or c.get("name") or cid[:8]
        is_active = c["isActive"]
        if not is_active:
            continue

        active_accounts += 1

        locks = c.get("locks") or {}
        has_lock = len(locks) > 0
        error_code = str(c.get("errorCode") or "")
        is_429 = error_code == "429" or "quota" in str(c.get("lastError") or "").lower()

        if is_429 or has_lock:
            quota_limited += 1

        acc_usage = by_account.get(cid) or {}
        reqs = acc_usage.get("requests") or 0
        p_tok = acc_usage.get("promptTokens") or 0
        c_tok = acc_usage.get("completionTokens") or 0
        a_cost = acc_usage.get("cost") or 0.0

        group = providers_summary.setdefault(p_type, {
            "total": 0, "active": 0, "quotaLimited": 0, "requests": 0, "tokens": 0, "cost": 0.0
        })
        group["total"] += 1
        group["active"] += 1
        if is_429 or has_lock:
            group["quotaLimited"] += 1
        group["requests"] += reqs
        group["tokens"] += (p_tok + c_tok)
        group["cost"] += a_cost

        status_label = "active"
        if is_429:
            status_label = "quota 429"
        elif has_lock:
            status_label = "locked"
        elif c.get("testStatus") == "unavailable":
            status_label = "unavailable"

        parsed_accounts.append({
            "id": cid,
            "provider": p_type,
            "name": c.get("name") or "",
            "email": email,
            "priority": c.get("priority") or 99,
            "isActive": True,
            "status": status_label,
            "isQuotaLimited": is_429 or has_lock,
            "requests": reqs,
            "tokens": p_tok + c_tok,
            "tokensFormatted": format_tokens(p_tok + c_tok),
            "cost": a_cost,
            "locks": locks
        })

    parsed_accounts.sort(key=lambda a: (a["requests"], a["tokens"]), reverse=True)

    bar_text = f"{format_tokens(total_tokens)}"
    dash_url = os.getenv("ROUTER_DASHBOARD_URL", "http://192.168.0.44:20128/dashboard")

    tooltip_lines = [
        f"9Router Status: Online ({dash_url})",
        f"Today: {total_requests} requests · {format_tokens(total_tokens)} tokens · ${cost:.2f}",
        f"Accounts: {active_accounts} enabled ({quota_limited} quota-limited)",
        "",
        "Enabled Providers:"
    ]
    for p_name, g in sorted(providers_summary.items(), key=lambda x: x[1]["requests"], reverse=True):
        if g["active"] > 0:
            tooltip_lines.append(f"• {p_name}: {g['active']} enabled, {g['requests']} reqs, {format_tokens(g['tokens'])}")

    result = {
        "online": True,
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "today": raw.get("today"),
        "barText": bar_text,
        "dashboardUrl": dash_url,
        "tooltip": "\n".join(tooltip_lines),
        "totals": {
            "requests": total_requests,
            "promptTokens": prompt_tokens,
            "completionTokens": comp_tokens,
            "cachedTokens": cached_tokens,
            "totalTokens": total_tokens,
            "totalTokensFormatted": format_tokens(total_tokens),
            "cost": cost,
            "totalAccounts": len(connections),
            "activeAccounts": active_accounts,
            "quotaLimitedAccounts": quota_limited
        },
        "providers": providers_summary,
        "accounts": parsed_accounts
    }
    return result

def main():
    data = fetch()
    tmp_file = CACHE_FILE.with_suffix(".tmp")
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    tmp_file.replace(CACHE_FILE)
    print(json.dumps({"status": "ok", "barText": data.get("barText"), "accounts": len(data.get("accounts", []))}))

if __name__ == "__main__":
    main()

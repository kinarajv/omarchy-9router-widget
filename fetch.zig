const std = @import("std");

extern "c" fn popen(command: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern "c" fn pclose(stream: *anyopaque) c_int;
extern "c" fn fread(ptr: *anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fwrite(ptr: *const anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;

const Account = struct {
    id: []const u8,
    provider: []const u8,
    name: []const u8,
    email: []const u8,
    priority: i64,
    status: []const u8,
    isQuotaLimited: bool,
    requests: i64,
    tokens: i64,
    cost: f64,
};

fn formatTokens(allocator: std.mem.Allocator, num: i64) ![]const u8 {
    const f = @as(f64, @floatFromInt(num));
    if (num >= 1_000_000_000) {
        return std.fmt.allocPrint(allocator, "{d:.1}B", .{f / 1_000_000_000.0});
    } else if (num >= 1_000_000) {
        return std.fmt.allocPrint(allocator, "{d:.1}M", .{f / 1_000_000.0});
    } else if (num >= 1_000) {
        return std.fmt.allocPrint(allocator, "{d:.1}k", .{f / 1_000.0});
    } else {
        return std.fmt.allocPrint(allocator, "{d}", .{num});
    }
}

fn accountLessThan(_: void, a: Account, b: Account) bool {
    if (a.requests != b.requests) {
        return a.requests > b.requests;
    }
    return a.tokens > b.tokens;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const default_cmd =
        \\ssh -o ConnectTimeout=3 -o BatchMode=yes root@192.168.0.2 "pct exec 109 -- python3 - <<'PY'
        \\import sqlite3, json, datetime
        \\db = '/var/lib/docker/volumes/9router-data/_data/db/data.sqlite'
        \\conn = sqlite3.connect(db)
        \\today = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
        \\row = conn.execute('SELECT data FROM usageDaily WHERE dateKey=?', (today,)).fetchone()
        \\daily = json.loads(row[0]) if row else {}
        \\conns = conn.execute('SELECT id, provider, name, email, priority, isActive, data FROM providerConnections').fetchall()
        \\out = {'today': today, 'daily': daily, 'connections': []}
        \\for c in conns:
        \\    d = json.loads(c[6]) if c[6] else {}
        \\    out['connections'].append({
        \\        'id': c[0], 'provider': c[1], 'name': c[2], 'email': c[3],
        \\        'priority': c[4], 'isActive': bool(c[5]),
        \\        'testStatus': d.get('testStatus'), 'errorCode': d.get('errorCode'),
        \\        'lastError': d.get('lastError'), 'lastErrorAt': d.get('lastErrorAt'),
        \\        'locks': {k: v for k, v in d.items() if k.startswith('modelLock_') and v is not None}
        \\    })
        \\print(json.dumps(out))
        \\PY"
    ;

    const custom_cmd = getenv("ROUTER_FETCH_CMD");
    const cmd_to_run = if (custom_cmd) |c| std.mem.span(c) else default_cmd;
    const cmd_z = try allocator.dupeZ(u8, cmd_to_run);

    const stream = popen(cmd_z.ptr, "r") orelse {
        std.debug.print("Failed to spawn command\n", .{});
        return error.PopenFailed;
    };
    defer _ = pclose(stream);

    var raw_buf: std.ArrayList(u8) = .empty;
    defer raw_buf.deinit(allocator);

    var chunk: [8192]u8 = undefined;
    while (true) {
        const bytes_read = fread(&chunk, 1, chunk.len, stream);
        if (bytes_read == 0) break;
        try raw_buf.appendSlice(allocator, chunk[0..bytes_read]);
    }

    if (raw_buf.items.len == 0) {
        std.debug.print("Empty response from command\n", .{});
        return error.EmptyResponse;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_buf.items, .{});
    defer parsed.deinit();

    const root_obj = parsed.value.object;
    const today_str = if (root_obj.get("today")) |t| (if (t == .string) t.string else "today") else "today";

    var total_requests: i64 = 0;
    var prompt_tokens: i64 = 0;
    var comp_tokens: i64 = 0;
    var cached_tokens: i64 = 0;
    var total_cost: f64 = 0.0;

    var by_account_map: ?std.json.ObjectMap = null;

    if (root_obj.get("daily")) |d_val| {
        if (d_val == .object) {
            const d = d_val.object;
            if (d.get("requests")) |v| {
                if (v == .integer) total_requests = v.integer;
            }
            if (d.get("promptTokens")) |v| {
                if (v == .integer) prompt_tokens = v.integer;
            }
            if (d.get("completionTokens")) |v| {
                if (v == .integer) comp_tokens = v.integer;
            }
            if (d.get("cachedTokens")) |v| {
                if (v == .integer) cached_tokens = v.integer;
            }
            if (d.get("cost")) |v| {
                if (v == .float) total_cost = v.float else if (v == .integer) total_cost = @floatFromInt(v.integer);
            }
            if (d.get("byAccount")) |v| {
                if (v == .object) by_account_map = v.object;
            }
        }
    }

    const total_tokens = prompt_tokens + comp_tokens;
    const total_tokens_fmt = try formatTokens(allocator, total_tokens);

    var accounts: std.ArrayList(Account) = .empty;
    defer accounts.deinit(allocator);

    var quota_limited_count: i64 = 0;

    if (root_obj.get("connections")) |conns_val| {
        if (conns_val == .array) {
            for (conns_val.array.items) |c_val| {
                if (c_val != .object) continue;
                const c = c_val.object;

                var is_active = false;
                if (c.get("isActive")) |ia| {
                    if (ia == .bool) is_active = ia.bool;
                }
                if (!is_active) continue;

                const cid = if (c.get("id")) |v| (if (v == .string) v.string else "") else "";
                const provider = if (c.get("provider")) |v| (if (v == .string) v.string else "") else "";
                const name = if (c.get("name")) |v| (if (v == .string) v.string else "") else "";
                const email = if (c.get("email")) |v| (if (v == .string) v.string else name) else name;
                var priority: i64 = 99;
                if (c.get("priority")) |v| {
                    if (v == .integer) priority = v.integer;
                }

                var has_lock = false;
                if (c.get("locks")) |v| {
                    if (v == .object and v.object.count() > 0) has_lock = true;
                }

                var is_429 = false;
                if (c.get("errorCode")) |v| {
                    if (v == .integer and v.integer == 429) is_429 = true;
                    if (v == .string and std.mem.eql(u8, v.string, "429")) is_429 = true;
                }
                if (c.get("lastError")) |v| {
                    if (v == .string and std.mem.indexOf(u8, v.string, "quota") != null) is_429 = true;
                }

                if (is_429 or has_lock) quota_limited_count += 1;

                var acc_reqs: i64 = 0;
                var acc_tokens: i64 = 0;
                var acc_cost: f64 = 0.0;

                if (by_account_map) |bam| {
                    if (bam.get(cid)) |acc_u| {
                        if (acc_u == .object) {
                            const au = acc_u.object;
                            if (au.get("requests")) |v| {
                                if (v == .integer) acc_reqs = v.integer;
                            }
                            var p_tok: i64 = 0;
                            var c_tok: i64 = 0;
                            if (au.get("promptTokens")) |v| {
                                if (v == .integer) p_tok = v.integer;
                            }
                            if (au.get("completionTokens")) |v| {
                                if (v == .integer) c_tok = v.integer;
                            }
                            acc_tokens = p_tok + c_tok;
                            if (au.get("cost")) |v| {
                                if (v == .float) acc_cost = v.float else if (v == .integer) acc_cost = @floatFromInt(v.integer);
                            }
                        }
                    }
                }

                var status_label: []const u8 = "active";
                if (is_429) {
                    status_label = "quota 429";
                } else if (has_lock) {
                    status_label = "locked";
                }

                try accounts.append(allocator, .{
                    .id = cid,
                    .provider = provider,
                    .name = name,
                    .email = email,
                    .priority = priority,
                    .status = status_label,
                    .isQuotaLimited = is_429 or has_lock,
                    .requests = acc_reqs,
                    .tokens = acc_tokens,
                    .cost = acc_cost,
                });
            }
        }
    }

    std.mem.sort(Account, accounts.items, {}, accountLessThan);

    const bar_text = try std.fmt.allocPrint(allocator, "{s}", .{total_tokens_fmt});

    const dash_env = getenv("ROUTER_DASHBOARD_URL");
    const dash_url = if (dash_env) |u| std.mem.span(u) else "http://192.168.0.44:20128/dashboard";

    var out_buf: std.ArrayList(u8) = .empty;
    defer out_buf.deinit(allocator);

    const header = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "online": true,
        \\  "today": "{s}",
        \\  "barText": "{s}",
        \\  "dashboardUrl": "{s}",
        \\  "totals": {{
        \\    "requests": {d},
        \\    "promptTokens": {d},
        \\    "completionTokens": {d},
        \\    "cachedTokens": {d},
        \\    "totalTokens": {d},
        \\    "totalTokensFormatted": "{s}",
        \\    "cost": {d:.4},
        \\    "activeAccounts": {d},
        \\    "quotaLimitedAccounts": {d}
        \\  }},
        \\  "accounts": [
    , .{
        today_str,
        bar_text,
        dash_url,
        total_requests,
        prompt_tokens,
        comp_tokens,
        cached_tokens,
        total_tokens,
        total_tokens_fmt,
        total_cost,
        accounts.items.len,
        quota_limited_count,
    });
    try out_buf.appendSlice(allocator, header);

    for (accounts.items, 0..) |acc, i| {
        const tok_fmt = try formatTokens(allocator, acc.tokens);
        if (i > 0) try out_buf.appendSlice(allocator, ",");
        const row = try std.fmt.allocPrint(allocator,
            \\
            \\    {{
            \\      "id": "{s}",
            \\      "provider": "{s}",
            \\      "name": "{s}",
            \\      "email": "{s}",
            \\      "priority": {d},
            \\      "isActive": true,
            \\      "status": "{s}",
            \\      "isQuotaLimited": {},
            \\      "requests": {d},
            \\      "tokens": {d},
            \\      "tokensFormatted": "{s}",
            \\      "cost": {d:.4}
            \\    }}
        , .{
            acc.id,
            acc.provider,
            acc.name,
            acc.email,
            acc.priority,
            acc.status,
            acc.isQuotaLimited,
            acc.requests,
            acc.tokens,
            tok_fmt,
            acc.cost,
        });
        try out_buf.appendSlice(allocator, row);
    }

    try out_buf.appendSlice(allocator,
        \\
        \\  ]
        \\}
    );

    const home = getenv("HOME") orelse ".";
    const dir_path = try std.fmt.allocPrint(allocator, "{s}/.local/state/omarchy/9router", .{home});
    const target_path = try std.fmt.allocPrint(allocator, "{s}/usage.json", .{dir_path});
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}/usage.json.tmp", .{dir_path});

    const target_path_z = try allocator.dupeZ(u8, target_path);
    const tmp_path_z = try allocator.dupeZ(u8, tmp_path);
    const dir_path_z = try allocator.dupeZ(u8, dir_path);

    _ = mkdir(dir_path_z.ptr, 0o755);

    const f = fopen(tmp_path_z.ptr, "wb") orelse {
        std.debug.print("Failed to open tmp file for write\n", .{});
        return error.FileOpenFailed;
    };
    _ = fwrite(out_buf.items.ptr, 1, out_buf.items.len, f);
    _ = fclose(f);
    _ = rename(tmp_path_z.ptr, target_path_z.ptr);

    std.debug.print("{{\"status\":\"ok\",\"barText\":\"{s}\",\"accounts\":{d}}}\n", .{ bar_text, accounts.items.len });
}

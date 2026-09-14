const std = @import("std");

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

fn accountLessThan(_: void, a: Account, b: Account) bool {
    if (a.requests != b.requests) return a.requests > b.requests;
    return a.tokens > b.tokens;
}

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

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();
    return file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return null;
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

fn writePrivateSessionFile(dir_path: []const u8, filename: []const u8, data: []const u8) !void {
    const tmp_name = "session.json.tmp";

    var dir = try std.fs.cwd().openDir(dir_path, .{ .no_follow = true });
    defer dir.close();

    const dir_stat = try dir.stat();
    if (dir_stat.kind != .directory) return error.NotADirectory;

    const flags: std.posix.O = .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
        .NOFOLLOW = true,
    };
    const fd = try std.posix.openat(dir.fd, tmp_name, flags, 0o600);
    defer std.posix.close(fd);

    var written: usize = 0;
    while (written < data.len) {
        const n = try std.posix.write(fd, data[written..]);
        if (n == 0) break;
        written += n;
    }

    try std.posix.fsync(fd);
    try std.posix.renameat(dir.fd, tmp_name, dir.fd, filename);
}

fn readPrivateSessionCookie(allocator: std.mem.Allocator, dir_path: []const u8, filename: []const u8) ?[]const u8 {
    var dir = std.fs.cwd().openDir(dir_path, .{ .no_follow = true }) catch return null;
    defer dir.close();

    const fd = std.posix.openat(dir.fd, filename, .{ .ACCMODE = .RDONLY, .NOFOLLOW = true }, 0) catch return null;
    const file = std.fs.File{ .handle = fd };
    defer file.close();

    const stat = file.stat() catch return null;
    if (stat.kind != .file) return null;

    const raw = file.readToEndAlloc(allocator, 64 * 1024) catch return null;
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value == .object) {
        if (parsed.value.object.get("cookie")) |c| {
            if (c == .string and c.string.len > 0) {
                return allocator.dupe(u8, c.string) catch null;
            }
        }
    }
    return null;
}

fn jsonEscapeString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    for (input) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => {
                if (c < 0x20) {
                    try out.appendSlice(try std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{c}));
                } else {
                    try out.append(c);
                }
            },
        }
    }
    return try allocator.dupe(u8, out.items);
}

const Config = struct {
    target: []const u8,
    password: []const u8,
    allow_insecure_http: bool = false,
};

fn loadConfig(allocator: std.mem.Allocator, home: []const u8, exe_dir: ?[]const u8) !Config {
    var target: []const u8 = "";
    var password: []const u8 = "";
    var allow_insecure_http: bool = false;

    var paths = std.ArrayList([]const u8).init(allocator);
    defer paths.deinit();

    try paths.append(try std.fmt.allocPrint(allocator, "{s}/.config/omarchy/9router.json", .{home}));
    if (exe_dir) |ed| {
        try paths.append(try std.fmt.allocPrint(allocator, "{s}/config.json", .{ed}));
    }
    try paths.append("config.json");

    for (paths.items) |p| {
        if (p.len == 0) continue;
        if (readFileAlloc(allocator, p)) |raw| {
            var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value == .object) {
                const obj = parsed.value.object;
                if (obj.get("target")) |v| {
                    if (v == .string and v.string.len > 0) {
                        target = try allocator.dupe(u8, v.string);
                    }
                }
                if (obj.get("password")) |v| {
                    if (v == .string) {
                        password = try allocator.dupe(u8, v.string);
                    }
                }
                if (obj.get("allowInsecureHttp")) |v| {
                    if (v == .bool) {
                        allow_insecure_http = v.bool;
                    }
                }
            }
        }
    }

    if (std.posix.getenv("ROUTER_TARGET")) |v| target = try allocator.dupe(u8, v);
    if (std.posix.getenv("ROUTER_PASSWORD")) |v| password = try allocator.dupe(u8, v);
    if (std.posix.getenv("ROUTER_ALLOW_INSECURE_HTTP")) |v| {
        allow_insecure_http = std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "true");
    }

    return .{ .target = target, .password = password, .allow_insecure_http = allow_insecure_http };
}

fn isLoopbackHost(host: []const u8) bool {
    if (std.mem.eql(u8, host, "127.0.0.1")) return true;
    if (std.mem.eql(u8, host, "localhost")) return true;
    if (std.mem.eql(u8, host, "::1")) return true;
    if (std.mem.eql(u8, host, "[::1]")) return true;
    return false;
}

fn normalizeBaseUrl(allocator: std.mem.Allocator, target: []const u8) ![]const u8 {
    const has_http = std.mem.startsWith(u8, target, "http://");
    const has_https = std.mem.startsWith(u8, target, "https://");

    var clean: []const u8 = undefined;

    if (has_http or has_https) {
        clean = try allocator.dupe(u8, target);
    } else {
        const host_part = if (std.mem.indexOfScalar(u8, target, '/')) |idx|
            target[0..idx]
        else
            target;
        const host_only = if (std.mem.indexOfScalar(u8, host_part, ':')) |idx|
            host_part[0..idx]
        else
            host_part;

        const default_scheme = if (isLoopbackHost(host_only)) "http://" else "https://";
        clean = try std.fmt.allocPrint(allocator, "{s}{s}", .{ default_scheme, target });
    }

    if (std.mem.endsWith(u8, clean, "/")) {
        clean = clean[0 .. clean.len - 1];
    }

    const after_scheme = if (std.mem.startsWith(u8, clean, "https://"))
        clean[8..]
    else if (std.mem.startsWith(u8, clean, "http://"))
        clean[7..]
    else
        clean;

    const host_part = if (std.mem.indexOfScalar(u8, after_scheme, '/')) |idx|
        after_scheme[0..idx]
    else
        after_scheme;

    if (std.mem.indexOfScalar(u8, host_part, ':') == null) {
        return try std.fmt.allocPrint(allocator, "{s}:20128", .{clean});
    }
    return clean;
}

fn extractHost(target: []const u8) []const u8 {
    var host = target;
    if (std.mem.startsWith(u8, host, "http://")) {
        host = host[7..];
    } else if (std.mem.startsWith(u8, host, "https://")) {
        host = host[8..];
    }
    if (std.mem.indexOfScalar(u8, host, '/')) |idx| {
        host = host[0..idx];
    }
    return host;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const home = std.posix.getenv("HOME") orelse ".";
    const exe_dir = std.fs.selfExeDirPathAlloc(allocator) catch null;
    defer if (exe_dir) |ed| allocator.free(ed);

    const cfg = try loadConfig(allocator, home, exe_dir);

    const dir_path = try std.fmt.allocPrint(allocator, "{s}/.local/state/omarchy/9router", .{home});
    std.fs.cwd().makePath(dir_path) catch {};

    const usage_path = try std.fmt.allocPrint(allocator, "{s}/usage.json", .{dir_path});
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}/usage.json.tmp", .{dir_path});

    if (cfg.target.len == 0) {
        const err_json =
            \\{
            \\  "online": false,
            \\  "source": "api-zig",
            \\  "error": "Missing target in config.json",
            \\  "dashboardUrl": "",
            \\  "gatewayHost": ""
            \\}
        ;
        try writeFile(usage_path, err_json);
        std.debug.print("{{\"status\":\"error\",\"barText\":\"\",\"accounts\":0,\"error\":\"Missing target in config.json\"}}\n", .{});
        return;
    }

    const base_url = try normalizeBaseUrl(allocator, cfg.target);
    const gateway_host = extractHost(base_url);

    var saved_cookie = readPrivateSessionCookie(allocator, dir_path, "session.json") orelse "";

    if (cfg.password.len > 0 or saved_cookie.len > 0) {
        if (std.mem.startsWith(u8, base_url, "http://")) {
            const host_only = if (std.mem.indexOfScalar(u8, gateway_host, ':')) |idx|
                gateway_host[0..idx]
            else
                gateway_host;

            const allow_insecure = cfg.allow_insecure_http or (if (std.posix.getenv("ROUTER_ALLOW_INSECURE_HTTP")) |v|
                std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "true")
            else
                false);

            if (!isLoopbackHost(host_only) and !allow_insecure) {
                const err_json = try std.fmt.allocPrint(allocator,
                    \\{{
                    \\  "online": false,
                    \\  "source": "api-zig",
                    \\  "error": "Insecure transport: credentials require HTTPS for non-loopback target",
                    \\  "dashboardUrl": "{s}/dashboard",
                    \\  "gatewayHost": "{s}"
                    \\}}
                , .{ base_url, gateway_host });
                try writeFile(usage_path, err_json);
                std.debug.print("{{\"status\":\"error\",\"barText\":\"\",\"accounts\":0,\"error\":\"Insecure transport: credentials require HTTPS for non-loopback target\"}}\n", .{});
                return;
            }
        }
    }

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    if (saved_cookie.len == 0 and cfg.password.len > 0) {
        const login_url = try std.fmt.allocPrint(allocator, "{s}/api/auth/login", .{base_url});
        const escaped_pw = try jsonEscapeString(allocator, cfg.password);
        const login_body = try std.fmt.allocPrint(allocator, "{{\"password\":\"{s}\"}}", .{escaped_pw});
        var resp_buf = std.ArrayList(u8).init(allocator);
        defer resp_buf.deinit();

        var header_buf: [4096]u8 = undefined;
        const login_res = client.fetch(.{
            .location = .{ .url = login_url },
            .method = .POST,
            .payload = login_body,
            .response_storage = .{ .dynamic = &resp_buf },
            .server_header_buffer = &header_buf,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "application/json" },
            },
        }) catch null;

        if (login_res != null) {
            const headers_str: []const u8 = &header_buf;
            if (std.mem.indexOf(u8, headers_str, "auth_token=")) |idx| {
                const cookie_part = headers_str[idx..];
                const end_idx = std.mem.indexOfAny(u8, cookie_part, ";\r\n") orelse cookie_part.len;
                saved_cookie = try allocator.dupe(u8, cookie_part[0..end_idx]);
                const escaped_cookie = try jsonEscapeString(allocator, saved_cookie);
                const save_payload = try std.fmt.allocPrint(allocator, "{{\"cookie\":\"{s}\"}}", .{escaped_cookie});
                writePrivateSessionFile(dir_path, "session.json", save_payload) catch {};
            }
        }
    }

    const api_url = try std.fmt.allocPrint(allocator, "{s}/api/usage/stats?period=today", .{base_url});
    var body_buf = std.ArrayList(u8).init(allocator);
    defer body_buf.deinit();

    var extra_hdrs = std.ArrayList(std.http.Header).init(allocator);
    defer extra_hdrs.deinit();
    try extra_hdrs.append(.{ .name = "Accept", .value = "application/json" });
    try extra_hdrs.append(.{ .name = "User-Agent", .value = "kinara.9router/1.0" });

    if (saved_cookie.len > 0) {
        try extra_hdrs.append(.{ .name = "Cookie", .value = saved_cookie });
    }

    var header_buf: [4096]u8 = undefined;
    const res = client.fetch(.{
        .location = .{ .url = api_url },
        .method = .GET,
        .response_storage = .{ .dynamic = &body_buf },
        .server_header_buffer = &header_buf,
        .extra_headers = extra_hdrs.items,
    }) catch |err| {
        const err_json = try std.fmt.allocPrint(allocator,
            \\{{
            \\  "online": false,
            \\  "source": "api-zig",
            \\  "error": "Connection error: {s}",
            \\  "dashboardUrl": "{s}/dashboard",
            \\  "gatewayHost": "{s}"
            \\}}
        , .{ @errorName(err), base_url, gateway_host });
        try writeFile(usage_path, err_json);
        std.debug.print("{{\"status\":\"error\",\"barText\":\"\",\"accounts\":0,\"error\":\"{s}\"}}\n", .{@errorName(err)});
        return;
    };

    if (res.status != .ok) {
        const err_json = try std.fmt.allocPrint(allocator,
            \\{{
            \\  "online": false,
            \\  "source": "api-zig",
            \\  "error": "HTTP {d}",
            \\  "dashboardUrl": "{s}/dashboard",
            \\  "gatewayHost": "{s}"
            \\}}
        , .{ @intFromEnum(res.status), base_url, gateway_host });
        try writeFile(usage_path, err_json);
        std.debug.print("{{\"status\":\"error\",\"barText\":\"\",\"accounts\":0,\"error\":\"HTTP {d}\"}}\n", .{@intFromEnum(res.status)});
        return;
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body_buf.items, .{}) catch {
        std.debug.print("{{\"status\":\"error\",\"barText\":\"\",\"accounts\":0,\"error\":\"Bad JSON\"}}\n", .{});
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        std.debug.print("{{\"status\":\"error\",\"barText\":\"\",\"accounts\":0,\"error\":\"Non-object JSON\"}}\n", .{});
        return;
    }

    const root = parsed.value.object;
    var total_requests: i64 = 0;
    var prompt_tokens: i64 = 0;
    var comp_tokens: i64 = 0;
    var cached_tokens: i64 = 0;
    var total_cost: f64 = 0.0;

    if (root.get("totalRequests")) |v| {
        if (v == .integer) total_requests = v.integer;
    }
    if (root.get("totalPromptTokens")) |v| {
        if (v == .integer) prompt_tokens = v.integer;
    }
    if (root.get("totalCompletionTokens")) |v| {
        if (v == .integer) comp_tokens = v.integer;
    }
    if (root.get("totalCachedTokens")) |v| {
        if (v == .integer) cached_tokens = v.integer;
    }
    if (root.get("totalCost")) |v| {
        if (v == .float) total_cost = v.float else if (v == .integer) total_cost = @floatFromInt(v.integer);
    }

    const total_tokens = prompt_tokens + comp_tokens;
    const bar_text = try formatTokens(allocator, total_tokens);

    var accounts = std.ArrayList(Account).init(allocator);
    defer accounts.deinit();

    if (root.get("byAccount")) |ba| {
        if (ba == .object) {
            var it = ba.object.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* != .object) continue;
                const a = entry.value_ptr.object;

                const raw_id = if (a.get("connectionId")) |v| (if (v == .string) v.string else entry.key_ptr.*) else entry.key_ptr.*;
                const id = try allocator.dupe(u8, raw_id);
                const raw_provider = if (a.get("provider")) |v| (if (v == .string) v.string else "unknown") else "unknown";
                const provider = try allocator.dupe(u8, raw_provider);
                const raw_name = if (a.get("accountName")) |v| (if (v == .string) v.string else "") else "";
                const name = try allocator.dupe(u8, raw_name);
                const email = if (name.len > 0) name else id;

                var reqs: i64 = 0;
                var p_tok: i64 = 0;
                var c_tok: i64 = 0;
                var cost: f64 = 0.0;

                if (a.get("requests")) |v| {
                    if (v == .integer) reqs = v.integer;
                }
                if (a.get("promptTokens")) |v| {
                    if (v == .integer) p_tok = v.integer;
                }
                if (a.get("completionTokens")) |v| {
                    if (v == .integer) c_tok = v.integer;
                }
                if (a.get("cost")) |v| {
                    if (v == .float) cost = v.float else if (v == .integer) cost = @floatFromInt(v.integer);
                }

                var found = false;
                for (accounts.items) |*existing| {
                    if (std.mem.eql(u8, existing.email, email)) {
                        existing.requests += reqs;
                        existing.tokens += (p_tok + c_tok);
                        existing.cost += cost;
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    try accounts.append(.{
                        .id = id,
                        .provider = provider,
                        .name = name,
                        .email = email,
                        .priority = 99,
                        .status = "active",
                        .isQuotaLimited = false,
                        .requests = reqs,
                        .tokens = p_tok + c_tok,
                        .cost = cost,
                    });
                }
            }
        }
    }

    std.mem.sort(Account, accounts.items, {}, accountLessThan);

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    try out.appendSlice(try std.fmt.allocPrint(allocator,
        \\{{
        \\  "online": true,
        \\  "source": "api-zig",
        \\  "today": "today",
        \\  "barText": "{s}",
        \\  "dashboardUrl": "{s}/dashboard",
        \\  "gatewayHost": "{s}",
        \\  "totals": {{
        \\    "requests": {d},
        \\    "promptTokens": {d},
        \\    "completionTokens": {d},
        \\    "cachedTokens": {d},
        \\    "totalTokens": {d},
        \\    "totalTokensFormatted": "{s}",
        \\    "cost": {d:.4},
        \\    "activeAccounts": {d},
        \\    "quotaLimitedAccounts": 0
        \\  }},
        \\  "accounts": [
    , .{
        bar_text,
        base_url,
        gateway_host,
        total_requests,
        prompt_tokens,
        comp_tokens,
        cached_tokens,
        total_tokens,
        bar_text,
        total_cost,
        accounts.items.len,
    }));

    for (accounts.items, 0..) |acc, i| {
        const tok_fmt = try formatTokens(allocator, acc.tokens);
        if (i > 0) try out.appendSlice(",");
        try out.appendSlice(try std.fmt.allocPrint(allocator,
            \\
            \\    {{
            \\      "id": "{s}",
            \\      "provider": "{s}",
            \\      "name": "{s}",
            \\      "email": "{s}",
            \\      "priority": {d},
            \\      "isActive": true,
            \\      "status": "{s}",
            \\      "isQuotaLimited": false,
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
            acc.requests,
            acc.tokens,
            tok_fmt,
            acc.cost,
        }));
    }

    try out.appendSlice("\n  ]\n}");

    try writeFile(tmp_path, out.items);
    std.fs.cwd().rename(tmp_path, usage_path) catch {
        try writeFile(usage_path, out.items);
    };

    std.debug.print("{{\"status\":\"ok\",\"barText\":\"{s}\",\"accounts\":{d}}}\n", .{ bar_text, accounts.items.len });
}

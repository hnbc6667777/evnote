const std = @import("std");
const Io = std.Io;
const net = Io.net;
const router = @import("router.zig");
const Context = @import("../effect/context.zig").Context;

pub const Server = struct {
    router: router.Router,
    ctx: *const Context,
    allocator: std.mem.Allocator,
    io: Io,

    pub fn init(allocator: std.mem.Allocator, ctx: *const Context, io: Io, rtr: router.Router) Server {
        return .{ .allocator = allocator, .ctx = ctx, .router = rtr, .io = io };
    }

    pub fn listen(self: *Server, port: u16) !void {
        const addr = net.IpAddress{ .ip4 = .{ .bytes = .{ 0, 0, 0, 0 }, .port = port } };
        var tcp_server = try addr.listen(self.io, .{ .reuse_address = true });
        defer tcp_server.deinit(self.io);

        self.ctx.log.info("server listening");

        while (true) {
            const conn = try tcp_server.accept(self.io);
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, conn });
            thread.detach();
        }
    }
};

fn handleConnection(server: *Server, conn: net.Stream) void {
    defer conn.close(server.io);
    const allocator = server.allocator;

    var buf: [8192]u8 = std.mem.zeroes([8192]u8);
    var data_slices: [1][]u8 = .{buf[0..]};
    const n = conn.read(server.io, data_slices[0..]) catch {
        server.ctx.log.err("read error");
        return;
    };
    if (n == 0) return;

    const data = buf[0..n];
    var req = parseRequest(allocator, data) catch {
        var resp = router.Response.text(allocator, 400, "Bad Request") catch return;
        defer resp.deinit(allocator);
        writeResponse(server.io, conn, &resp) catch {};
        return;
    };
    defer {
        allocator.free(req.path);
        req.params.deinit(allocator);
        req.headers.deinit(allocator);
    }

    var resp = server.router.route(server.ctx, &req, allocator) catch {
        var err_resp = router.Response.text(allocator, 500, "Internal Server Error") catch return;
        defer err_resp.deinit(allocator);
        writeResponse(server.io, conn, &err_resp) catch {};
        return;
    };
    defer resp.deinit(allocator);

    writeResponse(server.io, conn, &resp) catch {
        server.ctx.log.err("write error");
    };
}

fn splitOnce(buf: []const u8, delimiter: u8) ?struct { []const u8, []const u8 } {
    const idx = std.mem.indexOfScalar(u8, buf, delimiter) orelse return null;
    return .{ buf[0..idx], buf[idx + 1 ..] };
}

fn parseRequest(allocator: std.mem.Allocator, data: []const u8) !router.Request {
    var pos: usize = 0;
    while (pos < data.len and data[pos] != '\n') pos += 1;
    const request_line = std.mem.trimEnd(u8, data[0..pos], "\r");
    pos += 1;

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method_str = parts.next() orelse return error.BadRequest;
    const path = parts.next() orelse return error.BadRequest;

    const method: router.Method = if (std.mem.eql(u8, method_str, "GET"))
        .GET
    else if (std.mem.eql(u8, method_str, "POST"))
        .POST
    else if (std.mem.eql(u8, method_str, "PUT"))
        .PUT
    else if (std.mem.eql(u8, method_str, "DELETE"))
        .DELETE
    else
        return error.BadRequest;

    var headers = std.StringHashMapUnmanaged([]const u8){};
    errdefer headers.deinit(allocator);

    var content_length: usize = 0;
    while (pos < data.len) {
        var line_end = pos;
        while (line_end < data.len and data[line_end] != '\n') line_end += 1;
        const line = std.mem.trimEnd(u8, data[pos..line_end], "\r");
        pos = line_end + 1;
        if (line.len == 0) break;
        if (splitOnce(line, ':')) |kv| {
            const key = std.mem.trim(u8, kv[0], " ");
            const val = std.mem.trim(u8, kv[1], " ");
            try headers.put(allocator, key, val);
            if (std.ascii.eqlIgnoreCase(key, "Content-Length")) {
                content_length = std.fmt.parseInt(usize, val, 10) catch 0;
            }
        }
    }

    var body: []const u8 = "";
    const remaining = data[pos..];
    if (remaining.len >= content_length) {
        body = remaining[0..content_length];
    }

    return router.Request{
        .method = method,
        .path = try allocator.dupe(u8, path),
        .params = .{},
        .headers = headers,
        .body = body,
    };
}

fn writeResponse(io: Io, conn: net.Stream, resp: *const router.Response) !void {
    var write_buf: [4096]u8 = undefined;
    var writer = conn.writer(io, &write_buf);
    const w = &writer.interface;

    try w.print("HTTP/1.1 {d} {s}\r\n", .{ resp.status, statusText(resp.status) });

    var it = resp.headers.iterator();
    while (it.next()) |entry| {
        try w.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    try w.print("Content-Length: {d}\r\n", .{resp.body.len});
    try w.print("\r\n", .{});
    if (resp.body.len > 0) {
        try w.writeAll(resp.body);
    }
    try w.flush();
}

fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        500 => "Internal Server Error",
        else => "Unknown",
    };
}

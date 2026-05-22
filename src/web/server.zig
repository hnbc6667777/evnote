const std = @import("std");
const Io = std.Io;
const net = Io.net;
const router = @import("router.zig");
const Context = @import("../effect/context.zig").Context;

const MAX_BODY: usize = 10 * 1024 * 1024;

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

fn handleConnection(server: *Server, conn: net.Stream) !void {
    defer conn.close(server.io);
    const allocator = server.allocator;

    var buf: [16384]u8 = std.mem.zeroes([16384]u8);
    var slices: [1][]u8 = .{&buf};
    const n = conn.read(server.io, &slices) catch {
        server.ctx.log.err("read error");
        return;
    };
    if (n == 0) return;

    const data = buf[0..n];
    const body_start = findBodyStart(data);
    const content_length = parseContentLength(data, body_start) orelse 0;

    if (body_start + content_length <= n) {
        var req = parseRequestFrom(allocator, data, body_start, content_length) catch {
            return sendErr(server.io, allocator, conn, 400, "Bad Request");
        };
        defer { allocator.free(req.path); req.params.deinit(allocator); req.headers.deinit(allocator); }
        return handleReq(server, conn, &req, allocator);
    } else if (content_length > MAX_BODY) {
        return sendErr(server.io, allocator, conn, 413, "Payload Too Large");
    } else if (content_length > 0) {
        const total = body_start + content_length;
        const full = try allocator.alloc(u8, total);
        defer allocator.free(full);
        @memcpy(full[0..n], data);
        var pos = n;
        while (pos < total) {
            var read_slices: [1][]u8 = .{full[pos..]};
            const rn = conn.read(server.io, &read_slices) catch break;
            if (rn == 0) break;
            pos += rn;
        }
        var req = parseRequestFrom(allocator, full[0..pos], body_start, content_length) catch {
            return sendErr(server.io, allocator, conn, 400, "Bad Request");
        };
        defer { allocator.free(req.path); req.params.deinit(allocator); req.headers.deinit(allocator); }
        return handleReq(server, conn, &req, allocator);
    }

    var req = parseRequestFrom(allocator, data, body_start, content_length) catch {
        return sendErr(server.io, allocator, conn, 400, "Bad Request");
    };
    defer { allocator.free(req.path); req.params.deinit(allocator); req.headers.deinit(allocator); }
    return handleReq(server, conn, &req, allocator);
}

fn handleReq(server: *Server, conn: net.Stream, req: *router.Request, allocator: std.mem.Allocator) !void {
    var resp = server.router.route(server.ctx, req, allocator) catch {
        return sendErr(server.io, allocator, conn, 500, "Internal Server Error");
    };
    defer resp.deinit(allocator);
    writeResponse(server.io, conn, &resp) catch server.ctx.log.err("write error");
}

fn sendErr(io: Io, allocator: std.mem.Allocator, conn: net.Stream, status: u16, msg: []const u8) void {
    var resp = router.Response.text(allocator, status, msg) catch return;
    defer resp.deinit(allocator);
    writeResponse(io, conn, &resp) catch {};
}

fn findBodyStart(data: []const u8) usize {
    if (std.mem.indexOf(u8, data, "\r\n\r\n")) |i| return i + 4;
    if (std.mem.indexOf(u8, data, "\n\n")) |i| return i + 2;
    return data.len;
}

fn parseContentLength(data: []const u8, end: usize) ?usize {
    var pos: usize = 0;
    while (pos < end) {
        var line_end = pos;
        while (line_end < end and data[line_end] != '\n') line_end += 1;
        const line = std.mem.trim(u8, data[pos..line_end], "\r ");
        pos = line_end + 1;
        if (std.ascii.indexOfIgnoreCase(line, "Content-Length:")) |idx| {
            const val = std.mem.trim(u8, line[idx + 16 ..], " ");
            return std.fmt.parseInt(usize, val, 10) catch null;
        }
    }
    return null;
}

fn parseRequestFrom(allocator: std.mem.Allocator, data: []const u8, body_start: usize, content_length: usize) !router.Request {
    var pos: usize = 0;
    while (pos < data.len and data[pos] != '\n') pos += 1;
    const request_line = std.mem.trim(u8, data[0..pos], "\r");
    pos += 1;

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method_str = parts.next() orelse return error.BadRequest;
    const path = parts.next() orelse return error.BadRequest;

    const method: router.Method = if (std.mem.eql(u8, method_str, "GET")) .GET
    else if (std.mem.eql(u8, method_str, "POST")) .POST
    else if (std.mem.eql(u8, method_str, "PUT")) .PUT
    else if (std.mem.eql(u8, method_str, "DELETE")) .DELETE
    else return error.BadRequest;

    var headers = std.StringHashMapUnmanaged([]const u8){};
    errdefer headers.deinit(allocator);

    while (pos < body_start) {
        var line_end = pos;
        while (line_end < body_start and data[line_end] != '\n') line_end += 1;
        const line = std.mem.trim(u8, data[pos..line_end], "\r ");
        pos = line_end + 1;
        if (line.len == 0) break;
        if (splitOnce(line, ':')) |kv| {
            try headers.put(allocator, std.mem.trim(u8, kv[0], " "), std.mem.trim(u8, kv[1], " "));
        }
    }

    const body = data[body_start..][0..@min(content_length, data.len - body_start)];
    return router.Request{ .method = method, .path = try allocator.dupe(u8, path), .params = .{}, .headers = headers, .body = body };
}

fn splitOnce(buf: []const u8, delimiter: u8) ?struct { []const u8, []const u8 } {
    const idx = std.mem.indexOfScalar(u8, buf, delimiter) orelse return null;
    return .{ buf[0..idx], buf[idx + 1 ..] };
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
    if (resp.body.len > 0) try w.writeAll(resp.body);
    try w.flush();
}

fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK", 201 => "Created", 400 => "Bad Request",
        401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
        409 => "Conflict", 413 => "Payload Too Large", 500 => "Internal Server Error",
        else => "Unknown",
    };
}

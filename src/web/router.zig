const std = @import("std");
const json_mod = @import("json.zig");
const Context = @import("../effect/context.zig").Context;
const Io = std.Io;

pub const Method = enum { GET, POST, PUT, DELETE, PATCH };

pub const Request = struct {
    method: Method,
    path: []const u8,
    params: std.StringHashMapUnmanaged([]const u8),
    headers: std.StringHashMapUnmanaged([]const u8),
    body: []const u8,
};

pub const Response = struct {
    status: u16,
    headers: std.StringHashMapUnmanaged([]const u8),
    body: []const u8,

    pub fn json(allocator: std.mem.Allocator, status: u16, val: json_mod.Value) !Response {
        const body = try json_mod.serialize(allocator, val);
        var headers = std.StringHashMapUnmanaged([]const u8){};
        try headers.put(allocator, "Content-Type", "application/json");
        return .{ .status = status, .headers = headers, .body = body };
    }

    pub fn jsonError(allocator: std.mem.Allocator, status: u16, msg: []const u8) !Response {
        var obj = std.StringHashMap(json_mod.Value).init(allocator);
        defer obj.deinit();
        try obj.put("error", .{ .string = msg });
        return Response.json(allocator, status, .{ .object = obj });
    }

    pub fn text(allocator: std.mem.Allocator, status: u16, body: []const u8) !Response {
        _ = allocator;
        return .{ .status = status, .headers = .{}, .body = body };
    }

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
        self.headers.deinit(allocator);
    }
};

pub const Handler = *const fn (ctx: *const Context, req: *const Request, allocator: std.mem.Allocator) anyerror!Response;

pub const Route = struct {
    method: Method,
    path: []const u8,
    handler: Handler,
};

fn matchPath(allocator: std.mem.Allocator, pattern: []const u8, path: []const u8) !?std.StringHashMapUnmanaged([]const u8) {
    var pat_it = std.mem.splitScalar(u8, pattern, '/');
    var path_it = std.mem.splitScalar(u8, path, '/');
    var params = std.StringHashMapUnmanaged([]const u8){};
    errdefer params.deinit(allocator);

    while (true) {
        const p_opt = pat_it.next();
        const q_opt = path_it.next();
        if (p_opt == null and q_opt == null) return params;
        if (p_opt == null or q_opt == null) return null;
        const p = p_opt.?;
        const q = q_opt.?;
        if (p.len > 0 and p[0] == ':') {
            try params.put(allocator, p[1..], q);
        } else if (!std.mem.eql(u8, p, q)) {
            return null;
        }
    }
}

pub const Router = struct {
    routes: std.ArrayListUnmanaged(Route),

    pub fn init() Router {
        return .{ .routes = .{ .items = &.{}, .capacity = 0 } };
    }

    pub fn deinit(self: *Router, allocator: std.mem.Allocator) void {
        self.routes.deinit(allocator);
    }

    pub fn addRoute(self: *Router, allocator: std.mem.Allocator, method: Method, path: []const u8, handler: Handler) !void {
        try self.routes.append(allocator, .{ .method = method, .path = path, .handler = handler });
    }

    pub fn get(self: *Router, allocator: std.mem.Allocator, path: []const u8, handler: Handler) !void {
        try self.addRoute(allocator, .GET, path, handler);
    }

    pub fn post(self: *Router, allocator: std.mem.Allocator, path: []const u8, handler: Handler) !void {
        try self.addRoute(allocator, .POST, path, handler);
    }

    pub fn put(self: *Router, allocator: std.mem.Allocator, path: []const u8, handler: Handler) !void {
        try self.addRoute(allocator, .PUT, path, handler);
    }

    pub fn delete(self: *Router, allocator: std.mem.Allocator, path: []const u8, handler: Handler) !void {
        try self.addRoute(allocator, .DELETE, path, handler);
    }

    pub fn route(self: *const Router, ctx: *const Context, req: *Request, allocator: std.mem.Allocator) !Response {
        for (self.routes.items) |r| {
            if (req.method != r.method) continue;
            if (try matchPath(allocator, r.path, req.path)) |params| {
                req.params = params;
                return r.handler(ctx, req, allocator);
            }
        }
        return Response.jsonError(allocator, 404, "Not Found");
    }
};

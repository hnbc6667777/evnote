const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;

fn requireAdmin(ctx: *const Context, req: *const router.Request) !u64 {
    const uid_str = req.headers.get("x-user-id") orelse return error.NotAuthorized;
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch return error.NotAuthorized;
    const u = ctx.storage.getUser(ctx.allocator, uid) catch return error.NotAuthorized;
    if (u) |user_val| {
        defer { ctx.allocator.free(user_val.username); ctx.allocator.free(user_val.password_hash); }
        if (user_val.role != .admin) return error.NotAuthorized;
        return uid;
    }
    return error.NotAuthorized;
}

pub fn listUsers(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    _ = requireAdmin(ctx, req) catch return router.Response.jsonError(allocator, 403, "Admin only");
    return router.Response.jsonError(allocator, 501, "Not implemented");
}

pub fn listAllFiles(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    _ = requireAdmin(ctx, req) catch return router.Response.jsonError(allocator, 403, "Admin only");
    const files = ctx.file_store.list(allocator, 0) catch return router.Response.jsonError(allocator, 500, "List failed");
    defer {
        for (files) |f| { allocator.free(f.filename); allocator.free(f.content_type); }
        allocator.free(files);
    }

    var arr: std.ArrayList(json.Value) = .empty;
    errdefer { for (arr.items) |*v| v.deinit(allocator); arr.deinit(allocator); }

    for (files) |f| {
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(f.id) });
        try obj.put("filename", .{ .string = try allocator.dupe(u8, f.filename) });
        try obj.put("content_type", .{ .string = try allocator.dupe(u8, f.content_type) });
        try obj.put("size", .{ .int = @intCast(f.size) });
        try obj.put("user_id", .{ .int = @intCast(f.user_id) });
        try obj.put("created_at", .{ .int = f.created_at });
        try arr.append(allocator, .{ .object = obj });
    }

    return router.Response.json(allocator, 200, .{ .array = arr });
}

pub fn deleteAnyFile(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    _ = requireAdmin(ctx, req) catch return router.Response.jsonError(allocator, 403, "Admin only");
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");
    const file = ctx.file_store.get(allocator, id) catch return router.Response.jsonError(allocator, 500, "Get failed");
    if (file) |f| {
        defer { allocator.free(f.filename); allocator.free(f.content_type); }
        ctx.file_store.delete(allocator, f.user_id, id) catch {};
    }
    const empty_obj = std.StringHashMap(json.Value).init(allocator);
    return router.Response.json(allocator, 200, .{ .object = empty_obj });
}

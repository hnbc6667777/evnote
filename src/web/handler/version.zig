const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const version_service = @import("../../service/version_service.zig");

pub fn list(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const note_id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");

    const versions = version_service.getVersionHistory(ctx, note_id) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    defer ctx.allocator.free(versions);

    var arr: std.ArrayList(json.Value) = .empty;
    errdefer {
        for (arr.items) |*v| v.deinit(allocator);
        arr.deinit(allocator);
    }

    for (versions) |v| {
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("seq", .{ .int = @intCast(v.seq) });
        try obj.put("timestamp", .{ .int = v.timestamp });
        try obj.put("user_id", .{ .int = @intCast(v.user_id) });
        try arr.append(allocator, .{ .object = obj });
    }

    return router.Response.json(allocator, 200, .{ .array = arr });
}

pub fn getAt(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const seq_str = req.params.get("seq") orelse return router.Response.jsonError(allocator, 400, "Missing seq");
    const note_id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");
    const seq = std.fmt.parseInt(u64, seq_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid seq");

    const state = version_service.getNoteAtVersion(ctx, note_id, seq) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };

    if (state) |s| {
        defer s.deinit(allocator);
        var obj = std.StringHashMap(json.Value).init(allocator);
        defer obj.deinit();
        try obj.put("id", .{ .int = @intCast(s.meta.id) });
        try obj.put("title", .{ .string = s.meta.title });
        try obj.put("content", .{ .string = s.content });
        try obj.put("version", .{ .int = @intCast(s.meta.version) });
        return router.Response.json(allocator, 200, .{ .object = obj });
    }
    return router.Response.jsonError(allocator, 404, "Version not found");
}

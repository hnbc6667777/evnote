const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const engine = @import("../../iTask/engine.zig");

pub fn inbox(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    const role_str = req.headers.get("x-user-role") orelse "0";
    const role: ?@import("../../domain/user.zig").Role = if (role_str.len > 0 and role_str[0] != '0') @enumFromInt(std.fmt.parseInt(u8, role_str, 10) catch 0) else null;
    const tasks = engine.getUserInbox(ctx.workflow_store, allocator, uid, role) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    defer allocator.free(tasks);
    var arr: std.ArrayList(json.Value) = .empty;
    errdefer { for (arr.items) |*v| v.deinit(allocator); arr.deinit(allocator); }
    for (tasks) |t| {
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(t.id) });
        try obj.put("name", .{ .string = t.name });
        try obj.put("instance_id", .{ .int = @intCast(t.instance_id) });
        if (t.due_date) |dd| try obj.put("due_date", .{ .int = dd });
        try arr.append(allocator, .{ .object = obj });
    }
    return router.Response.json(allocator, 200, .{ .array = arr });
}

pub fn complete(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    engine.completeTask(ctx.workflow_store, id, uid, req.body) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    const empty_obj = std.StringHashMap(json.Value).init(allocator);
    return router.Response.json(allocator, 200, .{ .object = empty_obj });
}

pub fn createQuick(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    var body = json.parse(allocator, req.body) catch {
        return router.Response.jsonError(allocator, 400, "Invalid JSON");
    };
    defer body.deinit(allocator);
    const name = json.objectGetString(body, "name") orelse return router.Response.jsonError(allocator, 400, "Missing name");
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;

    const root = @import("../../iTask/core.zig").TaskBuilder.notify(name, "");
    const def_id = engine.createDef(ctx.workflow_store, allocator, name, "", root, uid) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    const inst_id = engine.startInstance(ctx.workflow_store, allocator, def_id, uid, null) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    var obj = std.StringHashMap(json.Value).init(allocator);
    try obj.put("instance_id", .{ .int = @intCast(inst_id) });
    return router.Response.json(allocator, 201, .{ .object = obj });
}

pub fn getDetail(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");
    _ = id;
    _ = ctx;
    return router.Response.jsonError(allocator, 501, "Not implemented");
}

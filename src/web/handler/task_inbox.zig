const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const engine = @import("../../iTask/engine.zig");
const wf = @import("../../domain/workflow.zig");

fn assignRoleFromInt(n: u8) wf.Assignment {
    return if (n == 0) .creator else .{ .role = @enumFromInt(n) };
}

pub fn inbox(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    const role_str = req.headers.get("x-user-role") orelse "0";
    const role: ?wf.UserRole = if (role_str.len > 0 and role_str[0] != '0') @enumFromInt(std.fmt.parseInt(u8, role_str, 10) catch 1) else null;

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
        const atype: i64 = switch (t.assignment) { .creator => 0, .user => 1, .role => 2, .anyone => 3 };
        try obj.put("assign_type", .{ .int = atype });
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

    const assign_val = json.objectGetInt(body, "assign_to");
    const assign_role_val = json.objectGetInt(body, "assign_role");
    const assignment: wf.Assignment = if (assign_role_val) |r| blk: {
        break :blk if (r > 0) .{ .role = @enumFromInt(@as(u8, @intCast(r))) } else .creator;
    } else if (assign_val) |u| blk: {
        break :blk if (u > 0) .{ .user = @as(u64, @intCast(u)) } else .creator;
    } else .creator;

    var root = @import("../../iTask/core.zig").TaskBuilder.notify(name, "");
    root.assignment = assignment;

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

const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const engine = @import("../../iTask/engine.zig");

pub fn createDef(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    var body = json.parse(allocator, req.body) catch { return router.Response.jsonError(allocator, 400, "Invalid JSON"); };
    defer body.deinit(allocator);
    const name = json.objectGetString(body, "name") orelse return router.Response.jsonError(allocator, 400, "Missing name");
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    _ = uid;
    _ = ctx;
    _ = name;
    return router.Response.jsonError(allocator, 501, "Not implemented");
}

pub fn listDefs(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    _ = ctx; _ = req;
    return router.Response.json(allocator, 200, .{ .array = .empty });
}

pub fn startInstance(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const def_id_str = req.params.get("def_id") orelse return router.Response.jsonError(allocator, 400, "Missing def_id");
    const def_id = std.fmt.parseInt(u64, def_id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid def_id");
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    const inst_id = engine.startInstance(ctx.workflow_store, allocator, def_id, uid, null) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    var obj = std.StringHashMap(json.Value).init(allocator);
    try obj.put("instance_id", .{ .int = @intCast(inst_id) });
    return router.Response.json(allocator, 201, .{ .object = obj });
}

pub fn listInstances(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const uid = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    const instances = engine.listMyInstances(ctx.workflow_store, allocator, uid) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    defer allocator.free(instances);
    var arr: std.ArrayList(json.Value) = .empty;
    errdefer { for (arr.items) |*v| v.deinit(allocator); arr.deinit(allocator); }
    for (instances) |inst| {
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(inst.id) });
        try obj.put("status", .{ .string = @tagName(inst.status) });
        try arr.append(allocator, .{ .object = obj });
    }
    return router.Response.json(allocator, 200, .{ .array = arr });
}

pub fn getInstance(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");
    const inst = engine.getInstanceDetail(ctx.workflow_store, allocator, id) catch return router.Response.jsonError(allocator, 500, "Get failed");
    if (inst) |i| {
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(i.id) });
        try obj.put("status", .{ .string = @tagName(i.status) });
        _ = engine.getInstanceTasks(ctx.workflow_store, allocator, i.id) catch {};
        return router.Response.json(allocator, 200, .{ .object = obj });
    }
    return router.Response.jsonError(allocator, 404, "Instance not found");
}

const wf = @import("../../domain/workflow.zig");

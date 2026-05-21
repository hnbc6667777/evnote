const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const note_service = @import("../../service/note_service.zig");

pub fn list(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const user_id_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, user_id_str, 10) catch 0;
    const ids = try ctx.storage.getUserNoteIds(allocator, user_id);
    defer allocator.free(ids);

    var arr: std.ArrayList(json.Value) = .empty;
    errdefer {
        for (arr.items) |*v| v.deinit(allocator);
        arr.deinit(allocator);
    }

    for (ids) |id| {
        const st = note_service.getNoteState(ctx, id) catch continue;
        if (st) |s| {
            if (!s.meta.deleted) {
                const title = try allocator.dupe(u8, s.meta.title);
                var obj = std.StringHashMap(json.Value).init(allocator);
                try obj.put("id", .{ .int = @intCast(s.meta.id) });
                try obj.put("title", .{ .string = title });
                try obj.put("updated_at", .{ .int = s.meta.updated_at });
                try arr.append(allocator, .{ .object = obj });
            }
            s.deinit(allocator);
        }
    }

    return router.Response.json(allocator, 200, .{ .array = arr });
}

pub fn create(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    var body = json.parse(allocator, req.body) catch {
        return router.Response.jsonError(allocator, 400, "Invalid JSON");
    };
    defer body.deinit(allocator);

    const title = json.objectGetString(body, "title") orelse return router.Response.jsonError(allocator, 400, "Missing title");
    const content = json.objectGetString(body, "content") orelse return router.Response.jsonError(allocator, 400, "Missing content");

    const user_id_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, user_id_str, 10) catch 0;

    const result = note_service.createNote(ctx, user_id, title, content) catch |err| {
        return router.Response.jsonError(allocator, errorToStatus(err), "Create failed");
    };

    var obj = std.StringHashMap(json.Value).init(allocator);
    try obj.put("note_id", .{ .int = @intCast(result.note_id) });
    try obj.put("seq", .{ .int = @intCast(result.seq) });
    return router.Response.json(allocator, 201, .{ .object = obj });
}

pub fn get(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const note_id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");

    const state = note_service.getNoteState(ctx, note_id) catch return router.Response.jsonError(allocator, 500, "Get failed");
    if (state) |s| {
        defer s.deinit(allocator);
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(s.meta.id) });
        try obj.put("title", .{ .string = try allocator.dupe(u8, s.meta.title) });
        try obj.put("content", .{ .string = try allocator.dupe(u8, s.content) });
        try obj.put("version", .{ .int = @intCast(s.meta.version) });
        return router.Response.json(allocator, 200, .{ .object = obj });
    }
    return router.Response.jsonError(allocator, 404, "Note not found");
}

pub fn update(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const note_id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");

    var body2 = json.parse(allocator, req.body) catch {
        return router.Response.jsonError(allocator, 400, "Invalid JSON");
    };
    defer body2.deinit(allocator);

    const content = json.objectGetString(body2, "content") orelse return router.Response.jsonError(allocator, 400, "Missing content");
    const parent_seq = @as(u64, @intCast(json.objectGetInt(body2, "parent_seq") orelse 0));

    const user_id_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, user_id_str, 10) catch 0;

    const seq = note_service.editNote(ctx, user_id, note_id, content, parent_seq) catch |err| {
        return router.Response.jsonError(allocator, errorToStatus(err), @errorName(err));
    };

    var obj = std.StringHashMap(json.Value).init(allocator);
    try obj.put("seq", .{ .int = @intCast(seq) });
    return router.Response.json(allocator, 200, .{ .object = obj });
}

pub fn delete(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const note_id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");

    const user_id_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, user_id_str, 10) catch 0;

    _ = note_service.deleteNote(ctx, user_id, note_id) catch |err| {
        return router.Response.jsonError(allocator, errorToStatus(err), @errorName(err));
    };

    const empty_obj = std.StringHashMap(json.Value).init(allocator);
    return router.Response.json(allocator, 200, .{ .object = empty_obj });
}

fn errorToStatus(err: anyerror) u16 {
    return switch (err) {
        error.ValidationError => 400,
        error.NotFound => 404,
        error.Conflict => 409,
        error.NotAuthorized => 403,
        error.AlreadyExists => 409,
        else => 500,
    };
}

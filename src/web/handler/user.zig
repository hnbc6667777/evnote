const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const user_service = @import("../../service/user_service.zig");

pub fn register(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    var body = json.parse(allocator, req.body) catch {
        return router.Response.jsonError(allocator, 400, "Invalid JSON");
    };
    defer body.deinit(allocator);

    const username = json.objectGetString(body, "username") orelse return router.Response.jsonError(allocator, 400, "Missing username");
    const password = json.objectGetString(body, "password") orelse return router.Response.jsonError(allocator, 400, "Missing password");

    const result = user_service.registerUser(ctx, username, password) catch |err| {
        const status: u16 = switch (err) {
            error.AlreadyExists => 409,
            error.ValidationError => 400,
            else => 500,
        };
        return router.Response.jsonError(allocator, status, @errorName(err));
    };

    var obj = std.StringHashMap(json.Value).init(allocator);
    try obj.put("user_id", .{ .int = @intCast(result.user_id) });
    try obj.put("username", .{ .string = result.username });
    return router.Response.json(allocator, 201, .{ .object = obj });
}

pub fn get(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const user_id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");

    const u = user_service.getUser(ctx, user_id) catch return router.Response.jsonError(allocator, 500, "Get failed");
    if (u) |user_val| {
        defer user_val.deinit(allocator);
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(user_val.id) });
        try obj.put("username", .{ .string = try allocator.dupe(u8, user_val.username) });
        return router.Response.json(allocator, 200, .{ .object = obj });
    }
    return router.Response.jsonError(allocator, 404, "User not found");
}

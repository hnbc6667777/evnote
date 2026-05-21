const std = @import("std");
const router = @import("../router.zig");
const json = @import("../json.zig");
const Context = @import("../../effect/context.zig").Context;
const auth_service = @import("../../service/auth_service.zig");

pub fn login(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    var body = json.parse(allocator, req.body) catch {
        return router.Response.jsonError(allocator, 400, "Invalid JSON");
    };
    defer body.deinit(allocator);

    const username = json.objectGetString(body, "username") orelse return router.Response.jsonError(allocator, 400, "Missing username");
    const password = json.objectGetString(body, "password") orelse return router.Response.jsonError(allocator, 400, "Missing password");

    const result = auth_service.login(ctx, username, password) catch |err| {
        const status: u16 = switch (err) {
            error.InvalidCredentials => 401,
            else => 500,
        };
        return router.Response.jsonError(allocator, status, @errorName(err));
    };

    var obj = std.StringHashMap(json.Value).init(allocator);
    defer obj.deinit();
    try obj.put("token", .{ .string = result.token });
    try obj.put("user_id", .{ .int = @intCast(result.user_id) });
    try obj.put("username", .{ .string = result.username });
    return router.Response.json(allocator, 200, .{ .object = obj });
}

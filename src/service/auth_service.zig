const std = @import("std");
const auth = @import("../ops/auth.zig");
const time = @import("../domain/time.zig");
const Context = @import("../effect/context.zig").Context;

pub const LoginResult = struct {
    token: []const u8,
    user_id: u64,
    username: []const u8,
};

pub fn login(ctx: *const Context, username: []const u8, password: []const u8) !LoginResult {
    ctx.log.info("user login");

    const u = (try ctx.storage.getUserByUsername(ctx.allocator, username)) orelse return error.InvalidCredentials;
    const u_username = try ctx.allocator.dupe(u8, u.username);
    const u_hash = u.password_hash;
    defer {
        ctx.allocator.free(u.username);
        ctx.allocator.free(u_hash);
    }

    const valid = try ctx.auth.verifyPassword(password, u_hash);
    if (!valid) {
        ctx.allocator.free(u_username);
        return error.InvalidCredentials;
    }

    const claims = auth.TokenClaims{
        .user_id = u.id,
        .username = u_username,
        .role = u.role,
        .exp = time.now() + 86400,
    };

    const token = try ctx.auth.signToken(ctx.allocator, claims);
    ctx.log.info("login successful");

    return .{ .token = token, .user_id = u.id, .username = u_username };
}

pub fn authenticate(ctx: *const Context, token: []const u8) !auth.TokenClaims {
    const claims = (try ctx.auth.verifyToken(ctx.allocator, token)) orelse return error.TokenInvalid;
    if (claims.exp < time.now()) return error.TokenExpired;
    return claims;
}

test "login and authenticate" {
    var storage = @import("../handler/test_doubles.zig").MemStorage.init(std.testing.allocator);
    defer storage.deinit();
    var mem_auth = @import("../handler/test_doubles.zig").MemAuth.init(std.testing.allocator);
    defer mem_auth.deinit();
    const ctx = Context{
        .allocator = std.testing.allocator,
        .storage = storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("../handler/test_doubles.zig").MemRender.handler(),
        .log = @import("../handler/stdio_log.zig").handler(),
    };

    const reg = try @import("user_service.zig").registerUser(&ctx, "alice", "password123");
    const login_result = try login(&ctx, "alice", "password123");
    try std.testing.expect(login_result.token.len > 0);
    try std.testing.expectEqual(reg.user_id, login_result.user_id);

    const claims = try authenticate(&ctx, login_result.token);
    try std.testing.expectEqual(reg.user_id, claims.user_id);
}

test "login with wrong password" {
    var storage = @import("../handler/test_doubles.zig").MemStorage.init(std.testing.allocator);
    defer storage.deinit();
    var mem_auth = @import("../handler/test_doubles.zig").MemAuth.init(std.testing.allocator);
    defer mem_auth.deinit();
    const ctx = Context{
        .allocator = std.testing.allocator,
        .storage = storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("../handler/test_doubles.zig").MemRender.handler(),
        .log = @import("../handler/stdio_log.zig").handler(),
    };

    _ = try @import("user_service.zig").registerUser(&ctx, "bob", "password123");
    try std.testing.expectError(error.InvalidCredentials, login(&ctx, "bob", "wrongpass"));
}

test "login with nonexistent user" {
    var storage = @import("../handler/test_doubles.zig").MemStorage.init(std.testing.allocator);
    defer storage.deinit();
    var mem_auth = @import("../handler/test_doubles.zig").MemAuth.init(std.testing.allocator);
    defer mem_auth.deinit();
    const ctx = Context{
        .allocator = std.testing.allocator,
        .storage = storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("../handler/test_doubles.zig").MemRender.handler(),
        .log = @import("../handler/stdio_log.zig").handler(),
    };

    try std.testing.expectError(error.InvalidCredentials, login(&ctx, "nonexistent", "pass"));
}

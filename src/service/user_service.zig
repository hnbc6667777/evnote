const std = @import("std");
const user = @import("../domain/user.zig");
const time = @import("../domain/time.zig");
const Context = @import("../effect/context.zig").Context;

pub const RegisterResult = struct {
    user_id: u64,
    username: []const u8,
};

pub fn registerUser(ctx: *const Context, username: []const u8, password: []const u8) !RegisterResult {
    ctx.log.info("registering user");

    if (username.len < 3) return error.ValidationError;
    if (password.len < 6) return error.ValidationError;

    const existing = try ctx.storage.getUserByUsername(ctx.allocator, username);
    if (existing != null) {
        if (existing) |e| {
            ctx.allocator.free(e.username);
            ctx.allocator.free(e.password_hash);
        }
        return error.AlreadyExists;
    }

    const hash = try ctx.auth.hashPassword(ctx.allocator, password);
    const latest_seq = try ctx.storage.getLatestSeq();
    const user_id = latest_seq + 1;

    const u = user.User{
        .id = user_id,
        .username = try ctx.allocator.dupe(u8, username),
        .password_hash = hash,
        .created_at = time.now(),
        .role = .user,
    };

    try ctx.storage.putUser(ctx.allocator, u);

    ctx.log.info("user registered");
    return .{ .user_id = user_id, .username = u.username };
}

pub fn getUser(ctx: *const Context, user_id: u64) !?user.User {
    return try ctx.storage.getUser(ctx.allocator, user_id);
}

pub fn getUserByUsername(ctx: *const Context, username: []const u8) !?user.User {
    return try ctx.storage.getUserByUsername(ctx.allocator, username);
}

test "register and get user" {
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

    const result = try registerUser(&ctx, "alice", "password123");
    try std.testing.expect(result.user_id > 0);
    try std.testing.expectEqualStrings("alice", result.username);

    const u = (try getUser(&ctx, result.user_id)).?;
    defer {
        ctx.allocator.free(u.username);
        ctx.allocator.free(u.password_hash);
    }
    try std.testing.expectEqualStrings("alice", u.username);
}

test "register duplicate username" {
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

    _ = try registerUser(&ctx, "bob", "password123");
    try std.testing.expectError(error.AlreadyExists, registerUser(&ctx, "bob", "password456"));
}

test "validation - short username" {
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

    try std.testing.expectError(error.ValidationError, registerUser(&ctx, "ab", "password123"));
}

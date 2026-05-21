const std = @import("std");

pub const Role = enum(u8) {
    user = 0,
    admin = 1,

    pub fn fromU8(v: u8) Role {
        return switch (v) {
            0 => .user,
            1 => .admin,
            else => .user,
        };
    }
};

pub const User = struct {
    id: u64,
    username: []const u8,
    password_hash: []const u8,
    created_at: i64,
    role: Role,

    pub fn deinit(self: *const User, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        allocator.free(self.password_hash);
    }
};

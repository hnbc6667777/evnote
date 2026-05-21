const std = @import("std");
const user = @import("../domain/user.zig");

pub const TokenClaims = struct {
    user_id: u64,
    username: []const u8,
    role: user.Role,
    exp: i64,
};

pub const Auth = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        hashPassword: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror![]u8,
        verifyPassword: *const fn (*anyopaque, []const u8, []const u8) anyerror!bool,
        signToken: *const fn (*anyopaque, std.mem.Allocator, TokenClaims) anyerror![]const u8,
        verifyToken: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror!?TokenClaims,
    };

    pub fn hashPassword(self: Auth, allocator: std.mem.Allocator, password: []const u8) ![]u8 {
        return self.vtable.hashPassword(self.ptr, allocator, password);
    }

    pub fn verifyPassword(self: Auth, password: []const u8, hash: []const u8) !bool {
        return self.vtable.verifyPassword(self.ptr, password, hash);
    }

    pub fn signToken(self: Auth, allocator: std.mem.Allocator, claims: TokenClaims) ![]const u8 {
        return self.vtable.signToken(self.ptr, allocator, claims);
    }

    pub fn verifyToken(self: Auth, allocator: std.mem.Allocator, token: []const u8) !?TokenClaims {
        return self.vtable.verifyToken(self.ptr, allocator, token);
    }
};

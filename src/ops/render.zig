const std = @import("std");

pub const Render = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        markdownToHtml: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror![]const u8,
    };

    pub fn markdownToHtml(self: Render, allocator: std.mem.Allocator, markdown: []const u8) ![]const u8 {
        return self.vtable.markdownToHtml(self.ptr, allocator, markdown);
    }
};

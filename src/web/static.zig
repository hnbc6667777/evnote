const std = @import("std");
const router = @import("router.zig");

const HTML = @embedFile("index.html");

pub fn serveHtml(allocator: std.mem.Allocator) !router.Response {
    var headers = std.StringHashMapUnmanaged([]const u8){};
    try headers.put(allocator, "Content-Type", "text/html; charset=utf-8");
    return .{
        .status = 200,
        .headers = headers,
        .body = try allocator.dupe(u8, HTML),
    };
}

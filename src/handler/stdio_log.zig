const std = @import("std");
const log_mod = @import("../ops/log.zig");

pub fn handler() log_mod.Log {
    return .{
        .ptr = undefined,
        .vtable = &.{
            .log = struct {
                fn f(_: *anyopaque, level: log_mod.Level, msg: []const u8) void {
                    const label = switch (level) {
                        .debug => "DEBUG",
                        .info => "INFO",
                        .warn => "WARN",
                        .err => "ERROR",
                    };
                    std.debug.print("[{s}] {s}\n", .{ label, msg });
                }
            }.f,
        },
    };
}

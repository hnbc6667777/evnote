const std = @import("std");

pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

pub const Log = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        log: *const fn (*anyopaque, Level, []const u8) void,
    };

    pub fn log(self: Log, level: Level, msg: []const u8) void {
        self.vtable.log(self.ptr, level, msg);
    }

    pub fn info(self: Log, msg: []const u8) void {
        self.log(.info, msg);
    }

    pub fn warn(self: Log, msg: []const u8) void {
        self.log(.warn, msg);
    }

    pub fn err(self: Log, msg: []const u8) void {
        self.log(.err, msg);
    }

    pub fn debug(self: Log, msg: []const u8) void {
        self.log(.debug, msg);
    }
};

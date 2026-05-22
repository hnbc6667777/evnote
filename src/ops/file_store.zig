const std = @import("std");

pub const FileRecord = struct {
    id: u64,
    user_id: u64,
    filename: []const u8,
    content_type: []const u8,
    size: u64,
    created_at: i64,
};

pub const FileStore = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        save: *const fn (*anyopaque, std.mem.Allocator, u64, []const u8, []const u8, []const u8) anyerror!FileRecord,
        get: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror!?FileRecord,
        getData: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror![]u8,
        list: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror![]FileRecord,
        delete: *const fn (*anyopaque, std.mem.Allocator, u64, u64) anyerror!void,
    };

    pub fn save(self: FileStore, allocator: std.mem.Allocator, user_id: u64, filename: []const u8, content_type: []const u8, data: []const u8) !FileRecord {
        return self.vtable.save(self.ptr, allocator, user_id, filename, content_type, data);
    }
    pub fn get(self: FileStore, allocator: std.mem.Allocator, id: u64) !?FileRecord {
        return self.vtable.get(self.ptr, allocator, id);
    }
    pub fn getData(self: FileStore, allocator: std.mem.Allocator, id: u64) ![]u8 {
        return self.vtable.getData(self.ptr, allocator, id);
    }
    pub fn list(self: FileStore, allocator: std.mem.Allocator, user_id: u64) ![]FileRecord {
        return self.vtable.list(self.ptr, allocator, user_id);
    }
    pub fn delete(self: FileStore, allocator: std.mem.Allocator, user_id: u64, id: u64) !void {
        return self.vtable.delete(self.ptr, allocator, user_id, id);
    }

    pub fn @"null"() FileStore {
        return .{
            .ptr = undefined,
            .vtable = &.{
                .save = struct {
                    fn f(_: *anyopaque, a: std.mem.Allocator, _uid: u64, _fn: []const u8, _ct: []const u8, _data: []const u8) anyerror!FileRecord {
                        _ = a; _ = _uid; _ = _fn; _ = _ct; _ = _data;
                        return error.NotAuthorized;
                    }
                }.f,
                .get = struct {
                    fn f(_: *anyopaque, a: std.mem.Allocator, _id: u64) anyerror!?FileRecord { _ = a; _ = _id; return null; }
                }.f,
                .getData = struct {
                    fn f(_: *anyopaque, a: std.mem.Allocator, _id: u64) anyerror![]u8 { _ = a; _ = _id; return error.NotFound; }
                }.f,
                .list = struct {
                    fn f(_: *anyopaque, a: std.mem.Allocator, _uid: u64) anyerror![]FileRecord { _ = a; _ = _uid; return &[_]FileRecord{}; }
                }.f,
                .delete = struct {
                    fn f(_: *anyopaque, a: std.mem.Allocator, _uid: u64, _id: u64) anyerror!void { _ = a; _ = _uid; _ = _id; }
                }.f,
            },
        };
    }
};

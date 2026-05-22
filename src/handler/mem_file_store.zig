const std = @import("std");
const fs = @import("../ops/file_store.zig");
const time = @import("../domain/time.zig");

pub const MemFileStore = struct {
    arena: std.heap.ArenaAllocator,
    files: std.AutoArrayHashMapUnmanaged(u64, StoredFile) = .{},
    next_id: u64 = 1,

    pub const StoredFile = struct {
        user_id: u64,
        filename: []const u8,
        content_type: []const u8,
        data: []const u8,
        created_at: i64,
    };

    pub fn init(allocator: std.mem.Allocator) MemFileStore {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *MemFileStore) void { self.arena.deinit(); }

    pub fn handler(self: *MemFileStore) fs.FileStore {
        return .{
            .ptr = self,
            .vtable = &.{
                .save = struct {
                    fn saveFn(ctx: *anyopaque, a: std.mem.Allocator, uid: u64, fname: []const u8, ctype: []const u8, data: []const u8) anyerror!fs.FileRecord {
                        const s = @as(*MemFileStore, @ptrCast(@alignCast(ctx)));
                        const aa = s.arena.allocator();
                        const id = s.next_id;
                        s.next_id += 1;
                        try s.files.put(aa, id, .{
                            .user_id = uid,
                            .filename = try aa.dupe(u8, fname),
                            .content_type = try aa.dupe(u8, ctype),
                            .data = try aa.dupe(u8, data),
                            .created_at = time.now(),
                        });
                        return fs.FileRecord{
                            .id = id, .user_id = uid,
                            .filename = try a.dupe(u8, fname),
                            .content_type = try a.dupe(u8, ctype),
                            .size = @intCast(data.len),
                            .created_at = time.now(),
                        };
                    }
                }.saveFn,
                .get = struct {
                    fn getFn(ctx: *anyopaque, a: std.mem.Allocator, id: u64) anyerror!?fs.FileRecord {
                        const s = @as(*MemFileStore, @ptrCast(@alignCast(ctx)));
                        const entry = s.files.get(id) orelse return null;
                        return fs.FileRecord{
                            .id = id, .user_id = entry.user_id,
                            .filename = try a.dupe(u8, entry.filename),
                            .content_type = try a.dupe(u8, entry.content_type),
                            .size = @intCast(entry.data.len),
                            .created_at = entry.created_at,
                        };
                    }
                }.getFn,
                .getData = struct {
                    fn getDataFn(ctx: *anyopaque, a: std.mem.Allocator, id: u64) anyerror![]u8 {
                        const s = @as(*MemFileStore, @ptrCast(@alignCast(ctx)));
                        const entry = s.files.get(id) orelse return error.NotFound;
                        return a.dupe(u8, entry.data);
                    }
                }.getDataFn,
                .list = struct {
                    fn listFn(ctx: *anyopaque, a: std.mem.Allocator, uid: u64) anyerror![]fs.FileRecord {
                        const s = @as(*MemFileStore, @ptrCast(@alignCast(ctx)));
                        var r: std.ArrayList(fs.FileRecord) = .empty;
                        errdefer r.deinit(a);
                        var it = s.files.iterator();
                        while (it.next()) |kv| {
                            if (kv.value_ptr.user_id == uid) {
                                try r.append(a, .{
                                    .id = kv.key_ptr.*, .user_id = uid,
                                    .filename = try a.dupe(u8, kv.value_ptr.filename),
                                    .content_type = try a.dupe(u8, kv.value_ptr.content_type),
                                    .size = @intCast(kv.value_ptr.data.len),
                                    .created_at = kv.value_ptr.created_at,
                                });
                            }
                        }
                        return r.toOwnedSlice(a);
                    }
                }.listFn,
                .delete = struct {
                    fn delFn(ctx: *anyopaque, a: std.mem.Allocator, uid: u64, id: u64) anyerror!void {
                        const s = @as(*MemFileStore, @ptrCast(@alignCast(ctx)));
                        _ = a;
                        const entry = s.files.get(id) orelse return;
                        if (entry.user_id != uid) return;
                        _ = s.files.swapRemove(id);
                    }
                }.delFn,
            },
        };
    }
};

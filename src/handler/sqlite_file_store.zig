const std = @import("std");
const hlp = @import("sqlite_helpers.zig");
const file_store = @import("../ops/file_store.zig");
const time = @import("../domain/time.zig");

pub const SqliteFileStore = struct {
    db: *hlp.sqlite3,

    pub fn init(db: *hlp.sqlite3) SqliteFileStore {
        return .{ .db = db };
    }

    pub fn handler(self: *SqliteFileStore) file_store.FileStore {
        return .{
            .ptr = self,
            .vtable = &.{
                .save = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64, fname: []const u8, ctype: []const u8, data: []const u8) anyerror!file_store.FileRecord {
                        const s = @as(*SqliteFileStore, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.db, "INSERT INTO files(user_id,filename,content_type,data,size,created_at) VALUES(?1,?2,?3,?4,?5,?6)");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(uid));
                        try hlp.bindText(stmt, 2, fname);
                        try hlp.bindText(stmt, 3, ctype);
                        try hlp.bindBlob(stmt, 4, data);
                        try hlp.bindInt(stmt, 5, @intCast(data.len));
                        try hlp.bindInt(stmt, 6, time.now());
                        try hlp.step(stmt);
                        const id = @as(u64, @intCast(hlp.sqlite3_last_insert_rowid(s.db)));
                        return file_store.FileRecord{
                            .id = id,
                            .user_id = uid,
                            .filename = try a.dupe(u8, fname),
                            .content_type = try a.dupe(u8, ctype),
                            .size = @intCast(data.len),
                            .created_at = time.now(),
                        };
                    }
                }.f,
                .get = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, id: u64) anyerror!?file_store.FileRecord {
                        const s = @as(*SqliteFileStore, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.db, "SELECT id,user_id,filename,content_type,size,created_at FROM files WHERE id=?1");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(id));
                        if (hlp.stepRow(stmt)) |r| { if (!r) return null; } else return error.StepFailed;
                        return file_store.FileRecord{
                            .id = @as(u64, @intCast(hlp.colInt64(stmt, 0))),
                            .user_id = @as(u64, @intCast(hlp.colInt64(stmt, 1))),
                            .filename = try hlp.colText(stmt, 2, a),
                            .content_type = try hlp.colText(stmt, 3, a),
                            .size = @as(u64, @intCast(hlp.colInt64(stmt, 4))),
                            .created_at = hlp.colInt64(stmt, 5),
                        };
                    }
                }.f,
                .getData = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, id: u64) anyerror![]u8 {
                        const s = @as(*SqliteFileStore, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.db, "SELECT data FROM files WHERE id=?1");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(id));
                        if (hlp.stepRow(stmt)) |r| { if (!r) return error.NotFound; } else return error.StepFailed;
                        return hlp.colBlob(stmt, 0, a);
                    }
                }.f,
                .list = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64) anyerror![]file_store.FileRecord {
                        const s = @as(*SqliteFileStore, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.db, "SELECT id,user_id,filename,content_type,size,created_at FROM files WHERE user_id=?1 ORDER BY created_at DESC");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(uid));
                        var r: std.ArrayList(file_store.FileRecord) = .empty;
                        errdefer r.deinit(a);
                        while (true) switch (hlp.sqlite3_step(stmt)) {
                            hlp.SQLITE_ROW => {
                                try r.append(a, file_store.FileRecord{
                                    .id = @as(u64, @intCast(hlp.colInt64(stmt,0))),
                                    .user_id = @as(u64, @intCast(hlp.colInt64(stmt,1))),
                                    .filename = try hlp.colText(stmt,2,a),
                                    .content_type = try hlp.colText(stmt,3,a),
                                    .size = @as(u64, @intCast(hlp.colInt64(stmt,4))),
                                    .created_at = hlp.colInt64(stmt,5),
                                });
                            },
                            hlp.SQLITE_DONE => break,
                            else => return error.StepFailed,
                        };
                        return r.toOwnedSlice(a);
                    }
                }.f,
                .delete = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64, id: u64) anyerror!void {
                        const s = @as(*SqliteFileStore, @ptrCast(@alignCast(ctx)));
                        _ = a;
                        const stmt = try hlp.prepare(s.db, "DELETE FROM files WHERE id=?1 AND user_id=?2");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(id));
                        try hlp.bindInt(stmt, 2, @intCast(uid));
                        try hlp.step(stmt);
                    }
                }.f,
            },
        };
    }
};

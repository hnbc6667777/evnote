const std = @import("std");

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

pub const SQLITE_OK = 0;
pub const SQLITE_ROW = 100;
pub const SQLITE_DONE = 101;
pub const SQLITE_TRANSIENT: c_int = -1;

pub const SqliteError = error{ InitFailed, ExecFailed, PrepareFailed, BindFailed, StepFailed, CorruptData };

extern fn sqlite3_open(filename: [*:0]const u8, ppDb: **sqlite3) c_int;
extern fn sqlite3_close(db: *sqlite3) c_int;
extern fn sqlite3_exec(db: *sqlite3, sql: [*:0]const u8, cb: ?*const anyopaque, arg: ?*anyopaque, errmsg: ?*?*u8) c_int;
extern fn sqlite3_prepare_v2(db: *sqlite3, sql: [*:0]const u8, n: c_int, stmt: **sqlite3_stmt, tail: ?*?[*:0]const u8) c_int;
extern fn sqlite3_step(stmt: *sqlite3_stmt) c_int;
extern fn sqlite3_finalize(stmt: *sqlite3_stmt) c_int;
extern fn sqlite3_bind_int64(stmt: *sqlite3_stmt, idx: c_int, val: i64) c_int;
extern fn sqlite3_bind_text(stmt: *sqlite3_stmt, idx: c_int, val: [*]const u8, len: c_int, destructor: c_int) c_int;
extern fn sqlite3_bind_blob(stmt: *sqlite3_stmt, idx: c_int, val: ?*const anyopaque, len: c_int, destructor: c_int) c_int;
extern fn sqlite3_bind_null(stmt: *sqlite3_stmt, idx: c_int) c_int;
extern fn sqlite3_column_int64(stmt: *sqlite3_stmt, col: c_int) i64;
extern fn sqlite3_column_text(stmt: *sqlite3_stmt, col: c_int) ?[*]const u8;
extern fn sqlite3_column_bytes(stmt: *sqlite3_stmt, col: c_int) c_int;
extern fn sqlite3_column_blob(stmt: *sqlite3_stmt, col: c_int) ?*const anyopaque;
extern fn sqlite3_errmsg(db: *sqlite3) [*:0]const u8;
extern fn sqlite3_last_insert_rowid(db: *sqlite3) i64;
extern fn sqlite3_changes(db: *sqlite3) c_int;

pub fn exec(db: *sqlite3, sql: []const u8) !void {
    if (sqlite3_exec(db, @ptrCast(sql.ptr), null, null, null) != SQLITE_OK)
        return error.ExecFailed;
}

pub fn prepare(db: *sqlite3, sql: []const u8) !*sqlite3_stmt {
    var stmt: *sqlite3_stmt = undefined;
    if (sqlite3_prepare_v2(db, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null) != SQLITE_OK)
        return error.PrepareFailed;
    return stmt;
}

pub fn bindInt(stmt: *sqlite3_stmt, idx: c_int, val: i64) !void {
    if (sqlite3_bind_int64(stmt, idx, val) != SQLITE_OK) return error.BindFailed;
}

pub fn bindText(stmt: *sqlite3_stmt, idx: c_int, val: []const u8) !void {
    if (sqlite3_bind_text(stmt, idx, @ptrCast(val.ptr), @intCast(val.len), SQLITE_TRANSIENT) != SQLITE_OK)
        return error.BindFailed;
}

pub fn bindBlob(stmt: *sqlite3_stmt, idx: c_int, val: []const u8) !void {
    if (sqlite3_bind_blob(stmt, idx, val.ptr, @intCast(val.len), SQLITE_TRANSIENT) != SQLITE_OK)
        return error.BindFailed;
}

pub fn stepRow(stmt: *sqlite3_stmt) ?bool {
    switch (sqlite3_step(stmt)) {
        SQLITE_ROW => return true,
        SQLITE_DONE => return false,
        else => return null,
    }
}

pub fn step(stmt: *sqlite3_stmt) !void {
    const rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE and rc != SQLITE_ROW) return error.StepFailed;
}

pub fn colInt64(stmt: *sqlite3_stmt, col: c_int) i64 {
    return sqlite3_column_int64(stmt, col);
}

pub fn colText(stmt: *sqlite3_stmt, col: c_int, allocator: std.mem.Allocator) ![]const u8 {
    const ptr = sqlite3_column_text(stmt, col) orelse return "";
    const len = @as(usize, @intCast(sqlite3_column_bytes(stmt, col)));
    return allocator.dupe(u8, ptr[0..len]);
}

pub fn colBlob(stmt: *sqlite3_stmt, col: c_int, allocator: std.mem.Allocator) ![]const u8 {
    const ptr = sqlite3_column_blob(stmt, col) orelse return "";
    const len = @as(usize, @intCast(sqlite3_column_bytes(stmt, col)));
    return allocator.dupe(u8, @as([*]const u8, @ptrCast(ptr))[0..len]);
}

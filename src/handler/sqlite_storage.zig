const std = @import("std");
const event_serde = @import("event_serde.zig");
const event = @import("../domain/event.zig");
const note = @import("../domain/note.zig");
const user = @import("../domain/user.zig");
const storage = @import("../ops/storage.zig");
const time = @import("../domain/time.zig");

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

const SQLITE_OK = 0;
const SQLITE_ROW = 100;
const SQLITE_DONE = 101;
const SQLITE_TRANSIENT = @as(c_int, -1);

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

pub const SqliteError = error{
    InitFailed,
    ExecFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
    CorruptData,
};

pub const SqliteStorage = struct {
    db: *sqlite3,

    pub fn init(path: [:0]const u8) !SqliteStorage {
        var db: *sqlite3 = undefined;
        const rc = sqlite3_open(path.ptr, &db);
        if (rc != SQLITE_OK) {
            _ = sqlite3_close(db);
            return error.InitFailed;
        }
        var s = SqliteStorage{ .db = db };
        try s.exec(
            \\CREATE TABLE IF NOT EXISTS events (
            \\  seq INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  note_id INTEGER NOT NULL,
            \\  user_id INTEGER NOT NULL,
            \\  timestamp INTEGER NOT NULL,
            \\  event_type INTEGER NOT NULL,
            \\  event_data BLOB NOT NULL
            \);
            \\CREATE INDEX IF NOT EXISTS idx_events_note ON events(note_id, seq);
            \\CREATE TABLE IF NOT EXISTS snapshots (
            \\  note_id INTEGER PRIMARY KEY,
            \\  user_id INTEGER NOT NULL,
            \\  title TEXT NOT NULL,
            \\  content TEXT NOT NULL,
            \\  created_at INTEGER NOT NULL,
            \\  updated_at INTEGER NOT NULL,
            \\  version INTEGER NOT NULL,
            \\  deleted INTEGER NOT NULL DEFAULT 0
            \);
            \\CREATE TABLE IF NOT EXISTS users (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  username TEXT UNIQUE NOT NULL,
            \\  password_hash BLOB NOT NULL,
            \\  created_at INTEGER NOT NULL,
            \\  role INTEGER NOT NULL DEFAULT 0
            \);
            \\CREATE TABLE IF NOT EXISTS note_owners (
            \\  note_id INTEGER PRIMARY KEY,
            \\  user_id INTEGER NOT NULL
            \);
        );
        return s;
    }

    pub fn deinit(self: *SqliteStorage) void {
        _ = sqlite3_close(self.db);
    }

    fn exec(self: *SqliteStorage, sql: []const u8) !void {
        const rc = sqlite3_exec(self.db, @ptrCast(sql.ptr), null, null, null);
        if (rc != SQLITE_OK) {
            return error.ExecFailed;
        }
    }

    fn prepare(self: *SqliteStorage, sql: []const u8) !*sqlite3_stmt {
        var stmt: *sqlite3_stmt = undefined;
        const rc = sqlite3_prepare_v2(self.db, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
        if (rc != SQLITE_OK) {
            return error.PrepareFailed;
        }
        return stmt;
    }

    fn bindInt(stmt: *sqlite3_stmt, idx: c_int, val: i64) !void {
        if (sqlite3_bind_int64(stmt, idx, val) != SQLITE_OK) return error.BindFailed;
    }

    fn bindText(stmt: *sqlite3_stmt, idx: c_int, val: []const u8) !void {
        if (sqlite3_bind_text(stmt, idx, @ptrCast(val.ptr), @intCast(val.len), SQLITE_TRANSIENT) != SQLITE_OK) return error.BindFailed;
    }

    fn bindBlob(stmt: *sqlite3_stmt, idx: c_int, val: []const u8) !void {
        if (sqlite3_bind_blob(stmt, idx, val.ptr, @intCast(val.len), SQLITE_TRANSIENT) != SQLITE_OK) return error.BindFailed;
    }

    fn step(stmt: *sqlite3_stmt) !void {
        const rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE and rc != SQLITE_ROW) return error.StepFailed;
    }

    fn stepRow(stmt: *sqlite3_stmt) ?bool {
        switch (sqlite3_step(stmt)) {
            SQLITE_ROW => return true,
            SQLITE_DONE => return false,
            else => return null,
        }
    }

    fn colInt64(stmt: *sqlite3_stmt, col: c_int) i64 {
        return sqlite3_column_int64(stmt, col);
    }

    fn colText(stmt: *sqlite3_stmt, col: c_int, allocator: std.mem.Allocator) ![]const u8 {
        const ptr = sqlite3_column_text(stmt, col) orelse return "";
        const len = @as(usize, @intCast(sqlite3_column_bytes(stmt, col)));
        return allocator.dupe(u8, ptr[0..len]);
    }

    fn colBlob(stmt: *sqlite3_stmt, col: c_int, allocator: std.mem.Allocator) ![]const u8 {
        const ptr = sqlite3_column_blob(stmt, col) orelse return "";
        const len = @as(usize, @intCast(sqlite3_column_bytes(stmt, col)));
        return allocator.dupe(u8, @as([*]const u8, @ptrCast(ptr))[0..len]);
    }

    pub fn handler(self: *SqliteStorage) storage.Storage {
        return .{
            .ptr = self,
            .vtable = &.{
                .getNoteEvents = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, note_id: u64, since_seq: u64) anyerror![]event.Event {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try self2.prepare(
                            "SELECT seq, event_data FROM events WHERE note_id = ?1 AND seq > ?2 ORDER BY seq"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(note_id));
                        try bindInt(stmt, 2, @intCast(since_seq));
                        var result: std.ArrayList(event.Event) = .empty;
                        errdefer result.deinit(allocator);
                        while (true) {
                            switch (sqlite3_step(stmt)) {
                                SQLITE_ROW => {
                                    const seq = @as(u64, @intCast(colInt64(stmt, 0)));
                                    const data = try colBlob(stmt, 1, allocator);
                                    defer allocator.free(data);
                                    const evt = event_serde.deserialize(allocator, seq, data) catch continue;
                                    try result.append(allocator, evt);
                                },
                                SQLITE_DONE => break,
                                else => return error.StepFailed,
                            }
                        }
                        return result.toOwnedSlice(allocator);
                    }
                }.f,
                .appendEvent = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, evt: event.Event) anyerror!u64 {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const data = try event_serde.serialize(allocator, evt);
                        defer allocator.free(data);
                        const stmt = try self2.prepare(
                            "INSERT INTO events (note_id, user_id, timestamp, event_type, event_data) VALUES (?1,?2,?3,?4,?5)"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(evt.note_id));
                        try bindInt(stmt, 2, @intCast(evt.user_id));
                        try bindInt(stmt, 3, evt.timestamp);
                        try bindInt(stmt, 4, @as(i64, @intFromEnum(evt.typ)));
                        try bindBlob(stmt, 5, data);
                        try step(stmt);
                        const seq = @as(u64, @intCast(sqlite3_last_insert_rowid(self2.db)));
                        _ = sqlite3_changes(self2.db);
                        const owner_stmt = try self2.prepare(
                            "INSERT OR IGNORE INTO note_owners (note_id, user_id) VALUES (?1, ?2)"
                        );
                        defer _ = sqlite3_finalize(owner_stmt);
                        try bindInt(owner_stmt, 1, @intCast(evt.note_id));
                        try bindInt(owner_stmt, 2, @intCast(evt.user_id));
                        try step(owner_stmt);
                        return seq;
                    }
                }.f,
                .getNoteSnapshot = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, note_id: u64) anyerror!?note.NoteState {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try self2.prepare(
                            "SELECT user_id,title,content,created_at,updated_at,version,deleted FROM snapshots WHERE note_id=?1"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(note_id));
                        if (stepRow(stmt)) |has_row| {
                            if (!has_row) return null;
                        } else return error.StepFailed;
                        return note.NoteState{
                            .meta = .{
                                .id = note_id,
                                .user_id = @as(u64, @intCast(colInt64(stmt, 0))),
                                .title = try colText(stmt, 1, allocator),
                                .created_at = colInt64(stmt, 3),
                                .updated_at = colInt64(stmt, 4),
                                .version = @as(u64, @intCast(colInt64(stmt, 5))),
                                .deleted = colInt64(stmt, 6) != 0,
                            },
                            .content = try colText(stmt, 2, allocator),
                        };
                    }
                }.f,
                .putNoteSnapshot = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, state: note.NoteState) anyerror!void {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        _ = allocator;
                        const stmt = try self2.prepare(
                            "INSERT OR REPLACE INTO snapshots (note_id,user_id,title,content,created_at,updated_at,version,deleted) VALUES (?1,?2,?3,?4,?5,?6,?7,?8)"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(state.meta.id));
                        try bindInt(stmt, 2, @intCast(state.meta.user_id));
                        try bindText(stmt, 3, state.meta.title);
                        try bindText(stmt, 4, state.content);
                        try bindInt(stmt, 5, state.meta.created_at);
                        try bindInt(stmt, 6, state.meta.updated_at);
                        try bindInt(stmt, 7, @as(i64, @intCast(state.meta.version)));
                        try bindInt(stmt, 8, if (state.meta.deleted) @as(i64, 1) else 0);
                        try step(stmt);
                    }
                }.f,
                .getUser = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, user_id: u64) anyerror!?user.User {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try self2.prepare(
                            "SELECT id,username,password_hash,created_at,role FROM users WHERE id=?1"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(user_id));
                        if (stepRow(stmt)) |has_row| {
                            if (!has_row) return null;
                        } else return error.StepFailed;
                        return user.User{
                            .id = @as(u64, @intCast(colInt64(stmt, 0))),
                            .username = try colText(stmt, 1, allocator),
                            .password_hash = try colBlob(stmt, 2, allocator),
                            .created_at = colInt64(stmt, 3),
                            .role = user.Role.fromU8(@intCast(colInt64(stmt, 4))),
                        };
                    }
                }.f,
                .getUserByUsername = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, username: []const u8) anyerror!?user.User {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try self2.prepare(
                            "SELECT id,username,password_hash,created_at,role FROM users WHERE username=?1"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindText(stmt, 1, username);
                        if (stepRow(stmt)) |has_row| {
                            if (!has_row) return null;
                        } else return error.StepFailed;
                        return user.User{
                            .id = @as(u64, @intCast(colInt64(stmt, 0))),
                            .username = try colText(stmt, 1, allocator),
                            .password_hash = try colBlob(stmt, 2, allocator),
                            .created_at = colInt64(stmt, 3),
                            .role = user.Role.fromU8(@intCast(colInt64(stmt, 4))),
                        };
                    }
                }.f,
                .putUser = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, u: user.User) anyerror!void {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        _ = allocator;
                        const stmt = try self2.prepare(
                            "INSERT OR REPLACE INTO users (id,username,password_hash,created_at,role) VALUES (?1,?2,?3,?4,?5)"
                        );
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(u.id));
                        try bindText(stmt, 2, u.username);
                        try bindBlob(stmt, 3, u.password_hash);
                        try bindInt(stmt, 4, u.created_at);
                        try bindInt(stmt, 5, @intCast(@intFromEnum(u.role)));
                        try step(stmt);
                    }
                }.f,
                .getLatestSeq = struct {
                    fn f(ctx: *anyopaque) anyerror!u64 {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try self2.prepare("SELECT COALESCE(MAX(seq),0) FROM events");
                        defer _ = sqlite3_finalize(stmt);
                        if (stepRow(stmt)) |has_row| {
                            if (!has_row) return 0;
                        } else return error.StepFailed;
                        return @as(u64, @intCast(colInt64(stmt, 0)));
                    }
                }.f,
                .getUserNoteIds = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, user_id: u64) anyerror![]u64 {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try self2.prepare("SELECT note_id FROM note_owners WHERE user_id=?1");
                        defer _ = sqlite3_finalize(stmt);
                        try bindInt(stmt, 1, @intCast(user_id));
                        var result: std.ArrayList(u64) = .empty;
                        errdefer result.deinit(allocator);
                        while (true) {
                            switch (sqlite3_step(stmt)) {
                                SQLITE_ROW => {
                                    try result.append(allocator, @as(u64, @intCast(colInt64(stmt, 0))));
                                },
                                SQLITE_DONE => break,
                                else => return error.StepFailed,
                            }
                        }
                        return result.toOwnedSlice(allocator);
                    }
                }.f,
                .fulltextSearch = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, query: []const u8) anyerror![]storage.SearchResult {
                        const self2 = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        _ = self2;
                        _ = allocator;
                        _ = query;
                        return &[_]storage.SearchResult{};
                    }
                }.f,
            },
        };
    }

    pub fn testAll() !void {
        const allocator = std.testing.allocator;
        const ts = time.now();
        const path = try std.fmt.allocPrint(allocator, "/tmp/test_sqlite_{d}.db", .{ts});
        defer allocator.free(path);

        var st = try init(@ptrCast(path.ptr));
        defer st.deinit();
        const h = st.handler();

        const evt = event.Event{
            .seq = 0, .note_id = 7, .user_id = 1,
            .timestamp = ts, .typ = .note_created,
            .data = .{ .note_created = .{ .title = "你好", .content = "世界" } },
        };
        try std.testing.expectEqual(@as(u64, 1), try h.appendEvent(allocator, evt));
        try std.testing.expectEqual(@as(u64, 1), try h.getLatestSeq());

        const ids = try h.getUserNoteIds(allocator, 1);
        defer allocator.free(ids);
        try std.testing.expectEqual(@as(usize, 1), ids.len);

        const events = try h.getNoteEvents(allocator, 7, 0);
        defer allocator.free(events);
        try std.testing.expectEqual(@as(usize, 1), events.len);
    }
};

test "sqlite storage full" {
    try SqliteStorage.testAll();
}

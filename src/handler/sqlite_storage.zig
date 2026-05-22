const std = @import("std");
const hlp = @import("sqlite_helpers.zig");
const event_serde = @import("event_serde.zig");
const event = @import("../domain/event.zig");
const note = @import("../domain/note.zig");
const user = @import("../domain/user.zig");
const storage = @import("../ops/storage.zig");
const file_store = @import("../ops/file_store.zig");
const time = @import("../domain/time.zig");

pub const db = hlp.sqlite3;
pub const SqliteStorage = struct {
    d: *db,

    pub fn init(path: [:0]const u8) !SqliteStorage {
        var d: *db = undefined;
        if (hlp.sqlite3_open(path.ptr, &d) != hlp.SQLITE_OK) {
            _ = hlp.sqlite3_close(d);
            return error.InitFailed;
        }
        var s = SqliteStorage{ .d = d };
        try hlp.exec(d,
            \\CREATE TABLE IF NOT EXISTS events (
            \\  seq INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  note_id INTEGER NOT NULL, user_id INTEGER NOT NULL,
            \\  timestamp INTEGER NOT NULL, event_type INTEGER NOT NULL,
            \\  event_data BLOB NOT NULL);
            \\CREATE INDEX IF NOT EXISTS idx_events_note ON events(note_id, seq);
            \\CREATE TABLE IF NOT EXISTS snapshots (
            \\  note_id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL,
            \\  title TEXT NOT NULL, content TEXT NOT NULL,
            \\  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
            \\  version INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
            \\CREATE TABLE IF NOT EXISTS users (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  username TEXT UNIQUE NOT NULL, password_hash BLOB NOT NULL,
            \\  created_at INTEGER NOT NULL, role INTEGER NOT NULL DEFAULT 0);
            \\CREATE TABLE IF NOT EXISTS note_owners (
            \\  note_id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL);
            \\CREATE TABLE IF NOT EXISTS files (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  user_id INTEGER NOT NULL, filename TEXT NOT NULL,
            \\  content_type TEXT NOT NULL, data BLOB NOT NULL,
            \\  size INTEGER NOT NULL, created_at INTEGER NOT NULL);
        );
        return s;
    }

    pub fn deinit(self: *SqliteStorage) void { _ = hlp.sqlite3_close(self.d); }
    pub fn database(self: *SqliteStorage) *db { return self.d; }

    pub fn handler(self: *SqliteStorage) storage.Storage {
        const V = struct {
            fn getNoteEvents(ctx: *anyopaque, a: std.mem.Allocator, nid: u64, since: u64) anyerror![]event.Event {
                const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                const stmt = try hlp.prepare(s.d, "SELECT seq, event_data FROM events WHERE note_id=?1 AND seq>?2 ORDER BY seq");
                defer _ = hlp.sqlite3_finalize(stmt);
                try hlp.bindInt(stmt, 1, @intCast(nid));
                try hlp.bindInt(stmt, 2, @intCast(since));
                var r: std.ArrayList(event.Event) = .empty;
                errdefer r.deinit(a);
                while (true) switch (hlp.sqlite3_step(stmt)) {
                    hlp.SQLITE_ROW => {
                        const seq = @as(u64, @intCast(hlp.colInt64(stmt, 0)));
                        const data = try hlp.colBlob(stmt, 1, a);
                        defer a.free(data);
                        try r.append(a, try event_serde.deserialize(a, seq, data));
                    },
                    hlp.SQLITE_DONE => break,
                    else => return error.StepFailed,
                };
                return r.toOwnedSlice(a);
            }
            fn appendEvent(ctx: *anyopaque, a: std.mem.Allocator, evt: event.Event) anyerror!u64 {
                const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                const data = try event_serde.serialize(a, evt);
                defer a.free(data);
                const stmt = try hlp.prepare(s.d, "INSERT INTO events(note_id,user_id,timestamp,event_type,event_data) VALUES(?1,?2,?3,?4,?5)");
                defer _ = hlp.sqlite3_finalize(stmt);
                try hlp.bindInt(stmt, 1, @intCast(evt.note_id));
                try hlp.bindInt(stmt, 2, @intCast(evt.user_id));
                try hlp.bindInt(stmt, 3, evt.timestamp);
                try hlp.bindInt(stmt, 4, @as(i64, @intFromEnum(evt.typ)));
                try hlp.bindBlob(stmt, 5, data);
                try hlp.step(stmt);
                const seq = @as(u64, @intCast(hlp.sqlite3_last_insert_rowid(s.d)));
                const os = try hlp.prepare(s.d, "INSERT OR IGNORE INTO note_owners(note_id,user_id) VALUES(?1,?2)");
                defer _ = hlp.sqlite3_finalize(os);
                try hlp.bindInt(os, 1, @intCast(evt.note_id));
                try hlp.bindInt(os, 2, @intCast(evt.user_id));
                try hlp.step(os);
                return seq;
            }
            fn getSnap(ctx: *anyopaque, a: std.mem.Allocator, nid: u64) anyerror!?note.NoteState {
                const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                const stmt = try hlp.prepare(s.d, "SELECT user_id,title,content,created_at,updated_at,version,deleted FROM snapshots WHERE note_id=?1");
                defer _ = hlp.sqlite3_finalize(stmt);
                try hlp.bindInt(stmt, 1, @intCast(nid));
                if (hlp.stepRow(stmt)) |r| { if (!r) return null; } else return error.StepFailed;
                return note.NoteState{
                    .meta = .{ .id = nid, .user_id = @as(u64, @intCast(hlp.colInt64(stmt,0))), .title = try hlp.colText(stmt,1,a), .created_at = hlp.colInt64(stmt,3), .updated_at = hlp.colInt64(stmt,4), .version = @as(u64,@intCast(hlp.colInt64(stmt,5))), .deleted = hlp.colInt64(stmt,6) != 0 },
                    .content = try hlp.colText(stmt, 2, a),
                };
            }
            fn putSnap(ctx: *anyopaque, a: std.mem.Allocator, st: note.NoteState) anyerror!void {
                const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                _ = a;
                const stmt = try hlp.prepare(s.d, "INSERT OR REPLACE INTO snapshots(note_id,user_id,title,content,created_at,updated_at,version,deleted) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)");
                defer _ = hlp.sqlite3_finalize(stmt);
                try hlp.bindInt(stmt, 1, @intCast(st.meta.id));
                try hlp.bindInt(stmt, 2, @intCast(st.meta.user_id));
                try hlp.bindText(stmt, 3, st.meta.title);
                try hlp.bindText(stmt, 4, st.content);
                try hlp.bindInt(stmt, 5, st.meta.created_at);
                try hlp.bindInt(stmt, 6, st.meta.updated_at);
                try hlp.bindInt(stmt, 7, @as(i64, @intCast(st.meta.version)));
                try hlp.bindInt(stmt, 8, if (st.meta.deleted) @as(i64, 1) else 0);
                try hlp.step(stmt);
            }
        };
        return .{
            .ptr = self,
            .vtable = &.{
                .getNoteEvents = V.getNoteEvents,
                .appendEvent = V.appendEvent,
                .getNoteSnapshot = V.getSnap,
                .putNoteSnapshot = V.putSnap,
                .getUser = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64) anyerror!?user.User {
                        const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.d, "SELECT id,username,password_hash,created_at,role FROM users WHERE id=?1");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(uid));
                        if (hlp.stepRow(stmt)) |r| { if (!r) return null; } else return error.StepFailed;
                        return user.User{ .id = @as(u64,@intCast(hlp.colInt64(stmt,0))), .username = try hlp.colText(stmt,1,a), .password_hash = try hlp.colBlob(stmt,2,a), .created_at = hlp.colInt64(stmt,3), .role = user.Role.fromU8(@intCast(hlp.colInt64(stmt,4))) };
                    }
                }.f,
                .getUserByUsername = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, uname: []const u8) anyerror!?user.User {
                        const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.d, "SELECT id,username,password_hash,created_at,role FROM users WHERE username=?1");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindText(stmt, 1, uname);
                        if (hlp.stepRow(stmt)) |r| { if (!r) return null; } else return error.StepFailed;
                        return user.User{ .id = @as(u64,@intCast(hlp.colInt64(stmt,0))), .username = try hlp.colText(stmt,1,a), .password_hash = try hlp.colBlob(stmt,2,a), .created_at = hlp.colInt64(stmt,3), .role = user.Role.fromU8(@intCast(hlp.colInt64(stmt,4))) };
                    }
                }.f,
                .putUser = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, u: user.User) anyerror!void {
                        const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        _ = a;
                        const stmt = try hlp.prepare(s.d, "INSERT OR REPLACE INTO users(id,username,password_hash,created_at,role) VALUES(?1,?2,?3,?4,?5)");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(u.id));
                        try hlp.bindText(stmt, 2, u.username);
                        try hlp.bindBlob(stmt, 3, u.password_hash);
                        try hlp.bindInt(stmt, 4, u.created_at);
                        try hlp.bindInt(stmt, 5, @intCast(@intFromEnum(u.role)));
                        try hlp.step(stmt);
                    }
                }.f,
                .getLatestSeq = struct {
                    fn f(ctx: *anyopaque) anyerror!u64 {
                        const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.d, "SELECT COALESCE(MAX(seq),0) FROM events");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        if (hlp.stepRow(stmt)) |r| { if (!r) return 0; } else return error.StepFailed;
                        return @as(u64, @intCast(hlp.colInt64(stmt, 0)));
                    }
                }.f,
                .getUserNoteIds = struct {
                    fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64) anyerror![]u64 {
                        const s = @as(*SqliteStorage, @ptrCast(@alignCast(ctx)));
                        const stmt = try hlp.prepare(s.d, "SELECT note_id FROM note_owners WHERE user_id=?1");
                        defer _ = hlp.sqlite3_finalize(stmt);
                        try hlp.bindInt(stmt, 1, @intCast(uid));
                        var r: std.ArrayList(u64) = .empty;
                        errdefer r.deinit(a);
                        while (true) switch (hlp.sqlite3_step(stmt)) {
                            hlp.SQLITE_ROW => try r.append(a, @as(u64, @intCast(hlp.colInt64(stmt,0)))),
                            hlp.SQLITE_DONE => break,
                            else => return error.StepFailed,
                        };
                        return r.toOwnedSlice(a);
                    }
                }.f,
                .fulltextSearch = struct {
                    fn f(_: *anyopaque, a: std.mem.Allocator, _q: []const u8) anyerror![]storage.SearchResult {
                        _ = a; _ = _q; return &[_]storage.SearchResult{};
                    }
                }.f,
            },
        };
    }
};

const std = @import("std");
const event_impl = @import("../domain/event.zig");
const note = @import("../domain/note.zig");
const user = @import("../domain/user.zig");
const storage = @import("../ops/storage.zig");
const auth = @import("../ops/auth.zig");
const render = @import("../ops/render.zig");
const time = @import("../domain/time.zig");

fn deepCopyEvent(allocator: std.mem.Allocator, src: event_impl.Event) !event_impl.Event {
    var dst = src;
    switch (src.data) {
        .note_created => |d| {
            dst.data.note_created.title = try allocator.dupe(u8, d.title);
            dst.data.note_created.content = try allocator.dupe(u8, d.content);
        },
        .note_edited => |d| {
            const diffs = try allocator.alloc(event_impl.DiffOp, d.diffs.len);
            for (d.diffs, 0..) |op, i| {
                diffs[i] = switch (op) {
                    .keep => |n| event_impl.DiffOp{ .keep = n },
                    .delete => |n| event_impl.DiffOp{ .delete = n },
                    .insert => |s| event_impl.DiffOp{ .insert = try allocator.dupe(u8, s) },
                };
            }
            dst.data.note_edited.diffs = diffs;
        },
        .user_registered => |d| {
            dst.data.user_registered.username = try allocator.dupe(u8, d.username);
            dst.data.user_registered.password_hash = try allocator.dupe(u8, d.password_hash);
        },
        else => {},
    }
    return dst;
}

pub const MemStorage = struct {
    events: std.ArrayListUnmanaged(event_impl.Event),
    events_by_note: std.AutoArrayHashMapUnmanaged(u64, std.ArrayListUnmanaged(u64)),
    snapshots: std.AutoArrayHashMapUnmanaged(u64, note.NoteState),
    users: std.AutoArrayHashMapUnmanaged(u64, user.User),
    users_by_name: std.StringArrayHashMapUnmanaged(u64),
    note_owners: std.AutoArrayHashMapUnmanaged(u64, u64),
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator) MemStorage {
        return .{
            .events = .{ .items = &.{}, .capacity = 0 },
            .events_by_note = .{},
            .snapshots = .{},
            .users = .{},
            .users_by_name = .{},
            .note_owners = .{},
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *MemStorage) void {
        self.arena.deinit();
    }

    pub fn handler(self: *MemStorage) storage.Storage {
        return .{
            .ptr = self,
            .vtable = &.{
                .getNoteEvents = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, note_id: u64, _since_seq: u64) anyerror![]event_impl.Event {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        _ = _since_seq;
                        const entry = self2.events_by_note.get(note_id) orelse return &[_]event_impl.Event{};
                        var result: std.ArrayList(event_impl.Event) = .empty;
                        errdefer result.deinit(allocator);
                        for (entry.items) |seq| {
                            try result.append(allocator, try deepCopyEvent(allocator, self2.events.items[seq - 1]));
                        }
                        return result.toOwnedSlice(allocator);
                    }
                }.f,
                .appendEvent = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, evt: event_impl.Event) anyerror!u64 {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        _ = allocator;
                        const a = self2.arena.allocator();
                        const seq: u64 = @intCast(self2.events.items.len + 1);
                        var new_evt = try deepCopyEvent(a, evt);
                        new_evt.seq = seq;
                        try self2.events.append(a, new_evt);
                        const entry = try self2.events_by_note.getOrPut(a, evt.note_id);
                        if (!entry.found_existing) {
                            entry.value_ptr.* = .{ .items = &.{}, .capacity = 0 };
                            if (!self2.note_owners.contains(evt.note_id)) {
                                try self2.note_owners.put(a, evt.note_id, evt.user_id);
                            }
                        }
                        try entry.value_ptr.append(a, seq);
                        return seq;
                    }
                }.f,
                .getNoteSnapshot = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, note_id: u64) anyerror!?note.NoteState {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        const entry = self2.snapshots.get(note_id) orelse return null;
                        return note.NoteState{
                            .meta = .{
                                .id = entry.meta.id,
                                .user_id = entry.meta.user_id,
                                .title = try allocator.dupe(u8, entry.meta.title),
                                .created_at = entry.meta.created_at,
                                .updated_at = entry.meta.updated_at,
                                .version = entry.meta.version,
                                .deleted = entry.meta.deleted,
                            },
                            .content = try allocator.dupe(u8, entry.content),
                        };
                    }
                }.f,
                .putNoteSnapshot = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, state: note.NoteState) anyerror!void {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        _ = allocator;
                        const a = self2.arena.allocator();
                        var stored = state;
                        stored.meta.title = try a.dupe(u8, state.meta.title);
                        stored.content = try a.dupe(u8, state.content);
                        try self2.snapshots.put(a, state.meta.id, stored);
                    }
                }.f,
                .getUser = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, user_id: u64) anyerror!?user.User {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        const entry = self2.users.get(user_id) orelse return null;
                        return .{
                            .id = entry.id,
                            .username = try allocator.dupe(u8, entry.username),
                            .password_hash = try allocator.dupe(u8, entry.password_hash),
                            .created_at = entry.created_at,
                            .role = entry.role,
                        };
                    }
                }.f,
                .getUserByUsername = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, username: []const u8) anyerror!?user.User {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        const uid = self2.users_by_name.get(username) orelse return null;
                        const entry = self2.users.get(uid) orelse return null;
                        return .{
                            .id = entry.id,
                            .username = try allocator.dupe(u8, entry.username),
                            .password_hash = try allocator.dupe(u8, entry.password_hash),
                            .created_at = entry.created_at,
                            .role = entry.role,
                        };
                    }
                }.f,
                .putUser = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, u: user.User) anyerror!void {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        _ = allocator;
                        const a = self2.arena.allocator();
                        var stored = u;
                        stored.username = try a.dupe(u8, u.username);
                        stored.password_hash = try a.dupe(u8, u.password_hash);
                        try self2.users.put(a, u.id, stored);
                        try self2.users_by_name.put(a, stored.username, u.id);
                    }
                }.f,
                .getLatestSeq = struct {
                    fn f(ctx: *anyopaque) anyerror!u64 {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        return @intCast(self2.events.items.len);
                    }
                }.f,
                .getUserNoteIds = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, user_id: u64) anyerror![]u64 {
                        const self2 = @as(*MemStorage, @ptrCast(@alignCast(ctx)));
                        var result: std.ArrayList(u64) = .empty;
                        errdefer result.deinit(allocator);
                        var it = self2.note_owners.iterator();
                        while (it.next()) |entry| {
                            if (entry.value_ptr.* == user_id) {
                                try result.append(allocator, entry.key_ptr.*);
                            }
                        }
                        return result.toOwnedSlice(allocator);
                    }
                }.f,
                .fulltextSearch = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, query: []const u8) anyerror![]storage.SearchResult {
                        _ = ctx;
                        _ = allocator;
                        _ = query;
                        return &[_]storage.SearchResult{};
                    }
                }.f,
            },
        };
    }
};

pub const MemAuth = struct {
    arena: std.heap.ArenaAllocator,
    secret: []const u8,

    pub fn init(allocator: std.mem.Allocator) MemAuth {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .secret = "test-secret",
        };
    }

    pub fn deinit(self: *MemAuth) void {
        self.arena.deinit();
    }

    pub fn handler(self: *MemAuth) auth.Auth {
        return .{
            .ptr = self,
            .vtable = &.{
                .hashPassword = struct {
                    fn f(_: *anyopaque, allocator: std.mem.Allocator, password: []const u8) anyerror![]u8 {
                        return allocator.dupe(u8, password);
                    }
                }.f,
                .verifyPassword = struct {
                    fn f(_: *anyopaque, password: []const u8, hash: []const u8) anyerror!bool {
                        return std.mem.eql(u8, password, hash);
                    }
                }.f,
                .signToken = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, claims: auth.TokenClaims) anyerror![]const u8 {
                        const self2 = @as(*MemAuth, @ptrCast(@alignCast(ctx)));
                        return std.fmt.allocPrint(allocator, "{s}:{d}:{s}", .{ self2.secret, claims.user_id, claims.username });
                    }
                }.f,
                .verifyToken = struct {
                    fn f(ctx: *anyopaque, allocator: std.mem.Allocator, token: []const u8) anyerror!?auth.TokenClaims {
                        const self2 = @as(*MemAuth, @ptrCast(@alignCast(ctx)));
                        var it = std.mem.splitScalar(u8, token, ':');
                        const secret = it.next() orelse return null;
                        if (!std.mem.eql(u8, secret, self2.secret)) return null;
                        const uid = std.fmt.parseInt(u64, it.next() orelse return null, 10) catch return null;
                        const uname = it.next() orelse return null;
                        return auth.TokenClaims{
                            .user_id = uid,
                            .username = try allocator.dupe(u8, uname),
                            .role = .user,
                            .exp = time.now() + 86400,
                        };
                    }
                }.f,
            },
        };
    }
};

pub const MemRender = struct {
    pub fn handler() render.Render {
        return .{
            .ptr = undefined,
            .vtable = &.{
                .markdownToHtml = struct {
                    fn f(_: *anyopaque, allocator: std.mem.Allocator, md: []const u8) anyerror![]const u8 {
                        return std.fmt.allocPrint(allocator, "<p>{s}</p>", .{md});
                    }
                }.f,
            },
        };
    }
};

const std = @import("std");
const event = @import("../domain/event.zig");
const note = @import("../domain/note.zig");
const user = @import("../domain/user.zig");

pub const SearchResult = struct {
    note_id: u64,
    title: []const u8,
    snippet: []const u8,
    score: f64,
};

pub const Storage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getNoteEvents: *const fn (*anyopaque, std.mem.Allocator, u64, u64) anyerror![]event.Event,
        appendEvent: *const fn (*anyopaque, std.mem.Allocator, event.Event) anyerror!u64,
        getNoteSnapshot: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror!?note.NoteState,
        putNoteSnapshot: *const fn (*anyopaque, std.mem.Allocator, note.NoteState) anyerror!void,
        getUser: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror!?user.User,
        getUserByUsername: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror!?user.User,
        putUser: *const fn (*anyopaque, std.mem.Allocator, user.User) anyerror!void,
        getLatestSeq: *const fn (*anyopaque) anyerror!u64,
        getUserNoteIds: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror![]u64,
        fulltextSearch: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror![]SearchResult,
    };

    pub fn getNoteEvents(self: Storage, allocator: std.mem.Allocator, note_id: u64, since_seq: u64) ![]event.Event {
        return self.vtable.getNoteEvents(self.ptr, allocator, note_id, since_seq);
    }

    pub fn appendEvent(self: Storage, allocator: std.mem.Allocator, evt: event.Event) !u64 {
        return self.vtable.appendEvent(self.ptr, allocator, evt);
    }

    pub fn getNoteSnapshot(self: Storage, allocator: std.mem.Allocator, note_id: u64) !?note.NoteState {
        return self.vtable.getNoteSnapshot(self.ptr, allocator, note_id);
    }

    pub fn putNoteSnapshot(self: Storage, allocator: std.mem.Allocator, state: note.NoteState) !void {
        return self.vtable.putNoteSnapshot(self.ptr, allocator, state);
    }

    pub fn getUser(self: Storage, allocator: std.mem.Allocator, user_id: u64) !?user.User {
        return self.vtable.getUser(self.ptr, allocator, user_id);
    }

    pub fn getUserByUsername(self: Storage, allocator: std.mem.Allocator, username: []const u8) !?user.User {
        return self.vtable.getUserByUsername(self.ptr, allocator, username);
    }

    pub fn putUser(self: Storage, allocator: std.mem.Allocator, u: user.User) !void {
        return self.vtable.putUser(self.ptr, allocator, u);
    }

    pub fn getLatestSeq(self: Storage) !u64 {
        return self.vtable.getLatestSeq(self.ptr);
    }

    pub fn getUserNoteIds(self: Storage, allocator: std.mem.Allocator, user_id: u64) ![]u64 {
        return self.vtable.getUserNoteIds(self.ptr, allocator, user_id);
    }

    pub fn fulltextSearch(self: Storage, allocator: std.mem.Allocator, query: []const u8) ![]SearchResult {
        return self.vtable.fulltextSearch(self.ptr, allocator, query);
    }
};

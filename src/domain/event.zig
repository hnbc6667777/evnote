const std = @import("std");
const diff = @import("diff.zig");
pub const DiffOp = diff.DiffOp;

pub const EventType = enum(u8) {
    note_created = 1,
    note_edited = 2,
    note_deleted = 3,
    user_registered = 4,
};

pub const Event = struct {
    seq: u64,
    note_id: u64,
    user_id: u64,
    timestamp: i64,
    typ: EventType,
    data: EventData,
};

pub const EventData = union(enum) {
    note_created: NoteCreated,
    note_edited: NoteEdited,
    note_deleted: NoteDeleted,
    user_registered: UserRegistered,
};

pub const NoteCreated = struct {
    title: []const u8,
    content: []const u8,
};

pub const NoteEdited = struct {
    diffs: []DiffOp,
    parent_seq: u64,
};

pub const NoteDeleted = struct {};

pub const UserRegistered = struct {
    username: []const u8,
    password_hash: []const u8,
    role: u8,
};

const std = @import("std");
const event = @import("event.zig");
const Event = event.Event;
const diff = @import("diff.zig");

pub const NoteMeta = struct {
    id: u64,
    user_id: u64,
    title: []const u8,
    created_at: i64,
    updated_at: i64,
    version: u64,
    deleted: bool,
};

pub const NoteState = struct {
    meta: NoteMeta,
    content: []const u8,

    pub fn deinit(self: *const NoteState, allocator: std.mem.Allocator) void {
        allocator.free(self.meta.title);
        allocator.free(self.content);
    }
};

pub fn replayEvents(allocator: std.mem.Allocator, events: []const Event, initial: ?NoteState) !?NoteState {
    var state = initial;

    for (events) |*evt| {
        const new_state = try applyEvent(allocator, state, evt.*);
        if (state) |*s| {
            allocator.free(s.meta.title);
            allocator.free(s.content);
        }
        state = new_state;
    }

    return state;
}

pub fn applyEvent(allocator: std.mem.Allocator, current: ?NoteState, evt: Event) !?NoteState {
    switch (evt.data) {
        .note_created => |data| {
            if (current != null) return error.AlreadyExists;
            return NoteState{
                .meta = .{
                    .id = evt.note_id,
                    .user_id = evt.user_id,
                    .title = try allocator.dupe(u8, data.title),
                    .created_at = evt.timestamp,
                    .updated_at = evt.timestamp,
                    .version = evt.seq,
                    .deleted = false,
                },
                .content = try allocator.dupe(u8, data.content),
            };
        },
        .note_edited => |data| {
            const cur = current orelse return error.NotFound;
            const new_content = try diff.apply(allocator, cur.content, data.diffs);
            const new_title = try allocator.dupe(u8, cur.meta.title);
            return NoteState{
                .meta = .{
                    .id = cur.meta.id,
                    .user_id = cur.meta.user_id,
                    .title = new_title,
                    .created_at = cur.meta.created_at,
                    .updated_at = evt.timestamp,
                    .version = evt.seq,
                    .deleted = false,
                },
                .content = new_content,
            };
        },
        .note_deleted => {
            const cur = current orelse return error.NotFound;
            const new_title = try allocator.dupe(u8, cur.meta.title);
            const new_content = try allocator.dupe(u8, cur.content);
            return NoteState{
                .meta = .{
                    .id = cur.meta.id,
                    .user_id = cur.meta.user_id,
                    .title = new_title,
                    .created_at = cur.meta.created_at,
                    .updated_at = evt.timestamp,
                    .version = evt.seq,
                    .deleted = true,
                },
                .content = new_content,
            };
        },
        else => return current,
    }
}

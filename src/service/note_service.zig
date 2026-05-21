const std = @import("std");
const event = @import("../domain/event.zig");
const note = @import("../domain/note.zig");
const diff = @import("../domain/diff.zig");
const time = @import("../domain/time.zig");
const Context = @import("../effect/context.zig").Context;

pub const CreateNoteResult = struct {
    note_id: u64,
    seq: u64,
};

pub fn createNote(ctx: *const Context, user_id: u64, title: []const u8, content: []const u8) !CreateNoteResult {
    ctx.log.info("creating note");
    const latest_seq = try ctx.storage.getLatestSeq();
    const note_id = latest_seq + 1;

    const evt = event.Event{
        .seq = 0,
        .note_id = note_id,
        .user_id = user_id,
        .timestamp = time.now(),
        .typ = .note_created,
        .data = .{ .note_created = .{
            .title = title,
            .content = content,
        } },
    };

    const seq = try ctx.storage.appendEvent(ctx.allocator, evt);
    ctx.log.info("note created");
    return .{ .note_id = note_id, .seq = seq };
}

pub fn editNote(ctx: *const Context, user_id: u64, note_id: u64, new_content: []const u8, parent_seq: u64) !u64 {
    ctx.log.info("editing note");
    const state = try getNoteState(ctx, note_id) orelse return error.NotFound;
    if (state.meta.deleted) return error.NotFound;
    if (state.meta.user_id != user_id) return error.NotAuthorized;
    if (state.meta.version != parent_seq) return error.Conflict;

    var diffs = try diff.compute(ctx.allocator, state.content, new_content);
    defer diffs.deinit();

    const evt = event.Event{
        .seq = 0,
        .note_id = note_id,
        .user_id = user_id,
        .timestamp = time.now(),
        .typ = .note_edited,
        .data = .{ .note_edited = .{
            .diffs = try ctx.allocator.dupe(diff.DiffOp, diffs.items),
            .parent_seq = parent_seq,
        } },
    };

    const seq = try ctx.storage.appendEvent(ctx.allocator, evt);
    ctx.log.info("note edited");
    return seq;
}

pub fn deleteNote(ctx: *const Context, user_id: u64, note_id: u64) !u64 {
    ctx.log.info("deleting note");
    const state = try getNoteState(ctx, note_id) orelse return error.NotFound;
    if (state.meta.deleted) return error.NotFound;
    if (state.meta.user_id != user_id) return error.NotAuthorized;

    const evt = event.Event{
        .seq = 0,
        .note_id = note_id,
        .user_id = user_id,
        .timestamp = time.now(),
        .typ = .note_deleted,
        .data = .{ .note_deleted = .{} },
    };

    const seq = try ctx.storage.appendEvent(ctx.allocator, evt);
    ctx.log.info("note deleted");
    return seq;
}

pub fn getNoteState(ctx: *const Context, note_id: u64) !?note.NoteState {
    const snapshot = try ctx.storage.getNoteSnapshot(ctx.allocator, note_id);
    const since_seq = if (snapshot) |s| s.meta.version else 0;
    const events = try ctx.storage.getNoteEvents(ctx.allocator, note_id, since_seq);
    defer ctx.allocator.free(events);

    return note.replayEvents(ctx.allocator, events, snapshot);
}

test "create and get note" {
    var storage = @import("../handler/test_doubles.zig").MemStorage.init(std.testing.allocator);
    defer storage.deinit();
    var mem_auth = @import("../handler/test_doubles.zig").MemAuth.init(std.testing.allocator);
    defer mem_auth.deinit();
    const ctx = Context{
        .allocator = std.testing.allocator,
        .storage = storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("../handler/test_doubles.zig").MemRender.handler(),
        .log = @import("../handler/stdio_log.zig").handler(),
    };

    const result = try createNote(&ctx, 1, "Test", "Hello World");
    try std.testing.expect(result.note_id > 0);

    const state = (try getNoteState(&ctx, result.note_id)).?;
    defer state.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Test", state.meta.title);
    try std.testing.expectEqualStrings("Hello World", state.content);
}

test "edit note with optimistic lock" {
    var storage = @import("../handler/test_doubles.zig").MemStorage.init(std.testing.allocator);
    defer storage.deinit();
    var mem_auth = @import("../handler/test_doubles.zig").MemAuth.init(std.testing.allocator);
    defer mem_auth.deinit();
    const ctx = Context{
        .allocator = std.testing.allocator,
        .storage = storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("../handler/test_doubles.zig").MemRender.handler(),
        .log = @import("../handler/stdio_log.zig").handler(),
    };

    const created = try createNote(&ctx, 1, "Test", "Hello");
    const seq = try editNote(&ctx, 1, created.note_id, "Hello World", created.seq);
    try std.testing.expect(seq > created.seq);

    const state = (try getNoteState(&ctx, created.note_id)).?;
    defer state.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Hello World", state.content);
}

test "edit note conflict" {
    var storage = @import("../handler/test_doubles.zig").MemStorage.init(std.testing.allocator);
    defer storage.deinit();
    var mem_auth = @import("../handler/test_doubles.zig").MemAuth.init(std.testing.allocator);
    defer mem_auth.deinit();
    const ctx = Context{
        .allocator = std.testing.allocator,
        .storage = storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("../handler/test_doubles.zig").MemRender.handler(),
        .log = @import("../handler/stdio_log.zig").handler(),
    };

    const created = try createNote(&ctx, 1, "Test", "Hello");
    _ = try editNote(&ctx, 1, created.note_id, "Hello World", created.seq);
    try std.testing.expectError(error.Conflict, editNote(&ctx, 1, created.note_id, "Hello Again", created.seq));
}

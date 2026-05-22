const std = @import("std");
const event = @import("../domain/event.zig");
const note = @import("../domain/note.zig");
const Context = @import("../effect/context.zig").Context;
const file_store = @import("../ops/file_store.zig");

pub const VersionInfo = struct {
    seq: u64,
    timestamp: i64,
    user_id: u64,
    event_type: event.EventType,
};

pub fn getVersionHistory(ctx: *const Context, note_id: u64) ![]VersionInfo {
    const events = try ctx.storage.getNoteEvents(ctx.allocator, note_id, 0);
    defer ctx.allocator.free(events);

    var versions: std.ArrayList(VersionInfo) = .empty;
    errdefer versions.deinit(ctx.allocator);

    for (events) |e| {
        try versions.append(ctx.allocator, .{
            .seq = e.seq,
            .timestamp = e.timestamp,
            .user_id = e.user_id,
            .event_type = e.typ,
        });
    }

    return versions.toOwnedSlice(ctx.allocator);
}

pub fn getNoteAtVersion(ctx: *const Context, note_id: u64, seq: u64) !?note.NoteState {
    const events = try ctx.storage.getNoteEvents(ctx.allocator, note_id, 0);
    defer ctx.allocator.free(events);

    var filtered: std.ArrayList(event.Event) = .empty;
    defer filtered.deinit(ctx.allocator);

    for (events) |e| {
        if (e.seq > seq) break;
        try filtered.append(ctx.allocator, e);
    }

    return note.replayEvents(ctx.allocator, filtered.items, null);
}

test "get version history" {
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
        .file_store = file_store.FileStore.@"null"(),
    };

    const created = try @import("note_service.zig").createNote(&ctx, 1, "Test", "v1");
    _ = try @import("note_service.zig").editNote(&ctx, 1, created.note_id, "v2", created.seq);

    const history = try getVersionHistory(&ctx, created.note_id);
    defer ctx.allocator.free(history);

    try std.testing.expectEqual(@as(usize, 2), history.len);
    try std.testing.expectEqual(@as(u64, 1), history[0].seq);
    try std.testing.expectEqual(@as(u64, 2), history[1].seq);
}

test "get note at specific version" {
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
        .file_store = file_store.FileStore.@"null"(),
    };

    const created = try @import("note_service.zig").createNote(&ctx, 1, "Test", "v1");
    _ = try @import("note_service.zig").editNote(&ctx, 1, created.note_id, "v2", created.seq);

    const v1 = (try getNoteAtVersion(&ctx, created.note_id, created.seq)).?;
    defer v1.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("v1", v1.content);
}

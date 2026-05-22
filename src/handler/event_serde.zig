const std = @import("std");
const event = @import("../domain/event.zig");
const diff = @import("../domain/diff.zig");

pub fn serialize(allocator: std.mem.Allocator, evt: event.Event) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    const writer = buf.writer();
    try writer.writeByte(@intFromEnum(evt.typ));
    try writer.writeInt(u64, evt.note_id, .little);
    try writer.writeInt(u64, evt.user_id, .little);
    try writer.writeInt(i64, evt.timestamp, .little);

    switch (evt.data) {
        .note_created => |d| {
            try writer.writeInt(u64, @intCast(d.title.len), .little);
            try writer.writeAll(d.title);
            try writer.writeInt(u64, @intCast(d.content.len), .little);
            try writer.writeAll(d.content);
        },
        .note_edited => |d| {
            try writer.writeInt(u64, d.parent_seq, .little);
            try writer.writeInt(u64, @intCast(d.diffs.len), .little);
            for (d.diffs) |op| {
                switch (op) {
                    .keep => |n| {
                        try writer.writeByte(0);
                        try writer.writeInt(u32, n, .little);
                    },
                    .insert => |s| {
                        try writer.writeByte(1);
                        try writer.writeInt(u64, @intCast(s.len), .little);
                        try writer.writeAll(s);
                    },
                    .delete => |n| {
                        try writer.writeByte(2);
                        try writer.writeInt(u32, n, .little);
                    },
                }
            }
        },
        .note_deleted => {},
        .user_registered => |d| {
            try writer.writeInt(u64, @intCast(d.username.len), .little);
            try writer.writeAll(d.username);
            try writer.writeInt(u64, @intCast(d.password_hash.len), .little);
            try writer.writeAll(d.password_hash);
            try writer.writeByte(d.role);
        },
    }

    return buf.toOwnedSlice();
}

pub fn deserialize(allocator: std.mem.Allocator, seq: u64, data: []const u8) !event.Event {
    var buf = data;
    if (buf.len < 1 + 8 + 8 + 8) return error.CorruptData;
    const typ: event.EventType = @enumFromInt(buf[0]);
    buf = buf[1..];
    const note_id = std.mem.readInt(u64, buf[0..8], .little);
    buf = buf[8..];
    const user_id = std.mem.readInt(u64, buf[0..8], .little);
    buf = buf[8..];
    const timestamp = std.mem.readInt(i64, buf[0..8], .little);
    buf = buf[8..];

    const evt = event.Event{
        .seq = seq,
        .note_id = note_id,
        .user_id = user_id,
        .timestamp = timestamp,
        .typ = typ,
        .data = try deserializeData(allocator, typ, &buf),
    };

    return evt;
}

fn deserializeData(allocator: std.mem.Allocator, typ: event.EventType, buf: *[]const u8) !event.EventData {
    return switch (typ) {
        .note_created => {
            const title = try readString(allocator, buf);
            const content = try readString(allocator, buf);
            return .{ .note_created = .{ .title = title, .content = content } };
        },
        .note_edited => {
            const parent_seq = std.mem.readInt(u64, buf.*[0..8], .little);
            buf.* = buf.*[8..];
            const diffs_len = std.mem.readInt(u64, buf.*[0..8], .little);
            buf.* = buf.*[8..];
            const diffs = try allocator.alloc(diff.DiffOp, @intCast(diffs_len));
            for (0..@intCast(diffs_len)) |i| {
                if (buf.*.len < 1) return error.CorruptData;
                const op_type = buf.*[0];
                buf.* = buf.*[1..];
                diffs[i] = switch (op_type) {
                    0 => blk: {
                        const n = std.mem.readInt(u32, buf.*[0..4], .little);
                        buf.* = buf.*[4..];
                        break :blk diff.DiffOp{ .keep = n };
                    },
                    1 => blk: {
                        const s = try readString(allocator, buf);
                        break :blk diff.DiffOp{ .insert = s };
                    },
                    2 => blk: {
                        const n = std.mem.readInt(u32, buf.*[0..4], .little);
                        buf.* = buf.*[4..];
                        break :blk diff.DiffOp{ .delete = n };
                    },
                    else => return error.CorruptData,
                };
            }
            return .{ .note_edited = .{ .diffs = diffs, .parent_seq = parent_seq } };
        },
        .note_deleted => {
            return .{ .note_deleted = .{} };
        },
        .user_registered => {
            const username = try readString(allocator, buf);
            const hash = try readString(allocator, buf);
            const role = buf.*[0];
            buf.* = buf.*[1..];
            return .{ .user_registered = .{ .username = username, .password_hash = hash, .role = role } };
        },
    };
}

fn readString(allocator: std.mem.Allocator, buf: *[]const u8) ![]const u8 {
    if (buf.*.len < 8) return error.CorruptData;
    const len = std.mem.readInt(u64, buf.*[0..8], .little);
    buf.* = buf.*[8..];
    if (buf.*.len < len) return error.CorruptData;
    const result = try allocator.dupe(u8, buf.*[0..@intCast(len)]);
    buf.* = buf.*[@intCast(len)..];
    return result;
}

const std = @import("std");

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: std.ArrayList(Value),
    object: std.StringHashMap(Value),

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |*arr| {
                for (arr.items) |*v| v.deinit(allocator);
                arr.deinit(allocator);
            },
            .object => |*obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                obj.deinit();
            },
            .string => |s| allocator.free(s),
            else => {},
        }
    }
};

fn writeEscaped(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    try result.append(allocator, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, ch),
        }
    }
    try result.append(allocator, '"');
    return result.toOwnedSlice(allocator);
}

fn writeVal(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), val: Value) !void {
    switch (val) {
        .null => try buf.appendSlice(allocator, "null"),
        .bool => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch unreachable;
            try buf.appendSlice(allocator, s);
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch unreachable;
            try buf.appendSlice(allocator, s);
        },
        .string => |s| {
            const escaped = try writeEscaped(allocator, s);
            defer allocator.free(escaped);
            try buf.appendSlice(allocator, escaped);
        },
        .array => |arr| {
            try buf.append(allocator, '[');
            for (arr.items, 0..) |item, i| {
                if (i > 0) try buf.appendSlice(allocator, ", ");
                try writeVal(allocator, buf, item);
            }
            try buf.append(allocator, ']');
        },
        .object => |obj| {
            try buf.append(allocator, '{');
            var first = true;
            var it = obj.iterator();
            while (it.next()) |entry| {
                if (!first) try buf.appendSlice(allocator, ", ");
                first = false;
                const escaped_key = try writeEscaped(allocator, entry.key_ptr.*);
                defer allocator.free(escaped_key);
                try buf.appendSlice(allocator, escaped_key);
                try buf.appendSlice(allocator, ": ");
                try writeVal(allocator, buf, entry.value_ptr.*);
            }
            try buf.append(allocator, '}');
        },
    }
}

pub fn serialize(allocator: std.mem.Allocator, val: Value) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try writeVal(allocator, &buf, val);
    return buf.toOwnedSlice(allocator);
}

const JsonErr = error{InvalidJson} || error{OutOfMemory};

fn skipWhitespace(buf: *[]const u8) void {
    while (buf.*.len > 0 and std.ascii.isWhitespace(buf.*[0])) {
        buf.* = buf.*[1..];
    }
}

fn expectChar(buf: *[]const u8, ch: u8) JsonErr!void {
    if (buf.*.len == 0 or buf.*[0] != ch) return error.InvalidJson;
    buf.* = buf.*[1..];
}

fn readString(allocator: std.mem.Allocator, buf: *[]const u8) JsonErr!Value {
    try expectChar(buf, '"');
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    while (buf.*.len > 0) {
        if (buf.*[0] == '"') {
            buf.* = buf.*[1..];
            return .{ .string = try result.toOwnedSlice(allocator) };
        }
        if (buf.*[0] == '\\') {
            buf.* = buf.*[1..];
            if (buf.*.len == 0) return error.InvalidJson;
            switch (buf.*[0]) {
                '"' => try result.append(allocator, '"'),
                '\\' => try result.append(allocator, '\\'),
                'n' => try result.append(allocator, '\n'),
                'r' => try result.append(allocator, '\r'),
                't' => try result.append(allocator, '\t'),
                else => return error.InvalidJson,
            }
        } else {
            try result.append(allocator, buf.*[0]);
        }
        buf.* = buf.*[1..];
    }
    return error.InvalidJson;
}

fn readValue(allocator: std.mem.Allocator, buf: *[]const u8) JsonErr!Value {
    skipWhitespace(buf);
    if (buf.*.len == 0) return error.InvalidJson;
    switch (buf.*[0]) {
        '"' => return readString(allocator, buf),
        '{' => return readObject(allocator, buf),
        '[' => return readArray(allocator, buf),
        't' => {
            if (buf.*.len >= 4 and std.mem.eql(u8, buf.*[0..4], "true")) {
                buf.* = buf.*[4..];
                return .{ .bool = true };
            }
            return error.InvalidJson;
        },
        'f' => {
            if (buf.*.len >= 5 and std.mem.eql(u8, buf.*[0..5], "false")) {
                buf.* = buf.*[5..];
                return .{ .bool = false };
            }
            return error.InvalidJson;
        },
        'n' => {
            if (buf.*.len >= 4 and std.mem.eql(u8, buf.*[0..4], "null")) {
                buf.* = buf.*[4..];
                return .null;
            }
            return error.InvalidJson;
        },
        '0'...'9', '-' => {
            const start = buf.*;
            if (buf.*[0] == '-') buf.* = buf.*[1..];
            while (buf.*.len > 0 and std.ascii.isDigit(buf.*[0])) buf.* = buf.*[1..];
            const is_float = buf.*.len > 0 and buf.*[0] == '.';
            if (is_float) {
                buf.* = buf.*[1..];
                while (buf.*.len > 0 and std.ascii.isDigit(buf.*[0])) buf.* = buf.*[1..];
                const val = std.fmt.parseFloat(f64, start[0..start.len - buf.*.len]) catch return error.InvalidJson;
                return .{ .float = val };
            }
            const val = std.fmt.parseInt(i64, start[0..start.len - buf.*.len], 10) catch return error.InvalidJson;
            return .{ .int = val };
        },
        else => return error.InvalidJson,
    }
}

fn readArray(allocator: std.mem.Allocator, buf: *[]const u8) JsonErr!Value {
    try expectChar(buf, '[');
    var arr: std.ArrayList(Value) = .empty;
    errdefer {
        for (arr.items) |*v| v.deinit(allocator);
        arr.deinit(allocator);
    }
    skipWhitespace(buf);
    if (buf.*.len > 0 and buf.*[0] == ']') {
        buf.* = buf.*[1..];
        return .{ .array = arr };
    }
    while (true) {
        skipWhitespace(buf);
        try arr.append(allocator, try readValue(allocator, buf));
        skipWhitespace(buf);
        if (buf.*.len > 0 and buf.*[0] == ',') {
            buf.* = buf.*[1..];
        } else if (buf.*.len > 0 and buf.*[0] == ']') {
            buf.* = buf.*[1..];
            return .{ .array = arr };
        } else {
            return error.InvalidJson;
        }
    }
}

fn readObject(allocator: std.mem.Allocator, buf: *[]const u8) JsonErr!Value {
    try expectChar(buf, '{');
    var obj = std.StringHashMap(Value).init(allocator);
    errdefer {
        var it = obj.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        obj.deinit();
    }
    skipWhitespace(buf);
    if (buf.*.len > 0 and buf.*[0] == '}') {
        buf.* = buf.*[1..];
        return .{ .object = obj };
    }
    while (true) {
        skipWhitespace(buf);
        const key = try readString(allocator, buf);
        const key_str = key.string;
        skipWhitespace(buf);
        try expectChar(buf, ':');
        skipWhitespace(buf);
        try obj.put(key_str, try readValue(allocator, buf));
        skipWhitespace(buf);
        if (buf.*.len > 0 and buf.*[0] == ',') {
            buf.* = buf.*[1..];
        } else if (buf.*.len > 0 and buf.*[0] == '}') {
            buf.* = buf.*[1..];
            return .{ .object = obj };
        } else {
            return error.InvalidJson;
        }
    }
}

pub fn parse(allocator: std.mem.Allocator, data: []const u8) JsonErr!Value {
    var buf = data;
    return readValue(allocator, &buf);
}

pub fn objectGet(val: Value, key: []const u8) ?Value {
    if (val != .object) return null;
    return val.object.get(key);
}

pub fn objectGetString(val: Value, key: []const u8) ?[]const u8 {
    const v = objectGet(val, key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

pub fn objectGetInt(val: Value, key: []const u8) ?i64 {
    const v = objectGet(val, key) orelse return null;
    if (v != .int) return null;
    return v.int;
}

pub fn objectGetBool(val: Value, key: []const u8) ?bool {
    const v = objectGet(val, key) orelse return null;
    if (v != .bool) return null;
    return v.bool;
}

test "JSON roundtrip" {
    const allocator = std.testing.allocator;
    var obj = std.StringHashMap(Value).init(allocator);
    try obj.put("name", .{ .string = "alice" });
    try obj.put("age", .{ .int = 30 });
    try obj.put("active", .{ .bool = true });

    var val = Value{ .object = obj };
    defer val.deinit(allocator);

    const json_str = try serialize(allocator, val);
    defer allocator.free(json_str);
    try std.testing.expect(json_str.len > 0);
}

test "JSON parse" {
    const allocator = std.testing.allocator;
    const data = "{\"name\":\"alice\",\"age\":30,\"active\":true}";
    var val = try parse(allocator, data);
    defer val.deinit(allocator);

    try std.testing.expect(val == .object);
    try std.testing.expectEqualStrings("alice", objectGetString(val, "name").?);
    try std.testing.expectEqual(@as(i64, 30), objectGetInt(val, "age").?);
    try std.testing.expectEqual(true, objectGetBool(val, "active").?);
}

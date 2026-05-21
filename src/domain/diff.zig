const std = @import("std");

pub const DiffOp = union(enum) {
    keep: u32,
    insert: []const u8,
    delete: u32,
};

pub const DiffOps = struct {
    items: []DiffOp,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiffOps) void {
        for (self.items) |*op| {
            switch (op.*) {
                .insert => |s| self.allocator.free(s),
                else => {},
            }
        }
        self.allocator.free(self.items);
    }
};

fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

pub fn compute(allocator: std.mem.Allocator, original: []const u8, modified: []const u8) !DiffOps {
    const orig_lines = try splitLines(allocator, original);
    defer allocator.free(orig_lines);
    const mod_lines = try splitLines(allocator, modified);
    defer allocator.free(mod_lines);

    const lcs = try longestCommonSubsequence(allocator, orig_lines, mod_lines);
    defer allocator.free(lcs);

    var result: std.ArrayList(DiffOp) = .empty;
    errdefer result.deinit(allocator);

    var o: usize = 0;
    var m: usize = 0;
    var lcs_i: usize = 0;

    while (o < orig_lines.len or m < mod_lines.len) {
        if (lcs_i < lcs.len and o == lcs[lcs_i].orig_idx and m == lcs[lcs_i].mod_idx) {
            try result.append(allocator, DiffOp{ .keep = @intCast(lcs[lcs_i].orig_len) });
            o += 1;
            m += 1;
            lcs_i += 1;
        } else if (lcs_i < lcs.len and o < lcs[lcs_i].orig_idx and m < lcs[lcs_i].mod_idx) {
            const ins_bytes = try mergeLines(allocator, mod_lines[m..lcs[lcs_i].mod_idx]);
            try result.append(allocator, DiffOp{ .delete = @intCast(@as(u64, lcs[lcs_i].orig_idx) - o) });
            try result.append(allocator, DiffOp{ .insert = ins_bytes });
            o = lcs[lcs_i].orig_idx;
            m = lcs[lcs_i].mod_idx;
        } else if (o >= orig_lines.len and m < mod_lines.len) {
            const ins_bytes = try mergeLines(allocator, mod_lines[m..]);
            try result.append(allocator, DiffOp{ .insert = ins_bytes });
            m = mod_lines.len;
        } else if (o < orig_lines.len) {
            try result.append(allocator, DiffOp{ .delete = @intCast(orig_lines.len - o) });
            o = orig_lines.len;
        } else if (m < mod_lines.len) {
            const ins_bytes = try mergeLines(allocator, mod_lines[m..]);
            try result.append(allocator, DiffOp{ .insert = ins_bytes });
            m = mod_lines.len;
        } else {
            break;
        }
    }

    return .{ .items = try result.toOwnedSlice(allocator), .allocator = allocator };
}

pub fn apply(allocator: std.mem.Allocator, original: []const u8, ops: []const DiffOp) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var pos: usize = 0;

    for (ops) |op| {
        switch (op) {
            .keep => |n| {
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    while (pos < original.len) {
                        if (original[pos] == '\n') {
                            try result.append(allocator, '\n');
                            pos += 1;
                            break;
                        }
                        try result.append(allocator, original[pos]);
                        pos += 1;
                    }
                }
            },
            .insert => |s| {
                try result.appendSlice(allocator, s);
            },
            .delete => |n| {
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    while (pos < original.len) {
                        if (original[pos] == '\n') {
                            pos += 1;
                            break;
                        }
                        pos += 1;
                    }
                }
            },
        }
    }

    return result.toOwnedSlice(allocator);
}

const LcsItem = struct {
    orig_idx: usize,
    mod_idx: usize,
    orig_len: u32,
};

fn longestCommonSubsequence(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8) ![]LcsItem {
    const rows = a.len + 1;
    const cols = b.len + 1;
    const table = try allocator.alloc([]u32, rows);
    defer {
        for (table) |row| allocator.free(row);
        allocator.free(table);
    }
    for (table) |*row| {
        row.* = try allocator.alloc(u32, cols);
        @memset(row.*, 0);
    }

    for (1.., a) |i, aline| {
        for (1.., b) |j, bline| {
            if (std.mem.eql(u8, aline, bline)) {
                table[i][j] = table[i - 1][j - 1] + 1;
            } else {
                table[i][j] = @max(table[i - 1][j], table[i][j - 1]);
            }
        }
    }

    var result: std.ArrayList(LcsItem) = .empty;
    errdefer result.deinit(allocator);

    var i = a.len;
    var j = b.len;
    while (i > 0 and j > 0) {
        if (std.mem.eql(u8, a[i - 1], b[j - 1])) {
            try result.append(allocator, .{ .orig_idx = i - 1, .mod_idx = j - 1, .orig_len = @intCast(a[i - 1].len + 1) });
            i -= 1;
            j -= 1;
        } else if (table[i - 1][j] > table[i][j - 1]) {
            i -= 1;
        } else {
            j -= 1;
        }
    }

    std.mem.reverse(LcsItem, result.items);
    return result.toOwnedSlice(allocator);
}

fn splitLines(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer lines.deinit(allocator);

    var start: usize = 0;
    for (text, 0..) |ch, i| {
        if (ch == '\n') {
            try lines.append(allocator, text[start..i]);
            start = i + 1;
        }
    }
    if (start <= text.len) {
        try lines.append(allocator, text[start..]);
    }

    return lines.toOwnedSlice(allocator);
}

fn mergeLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (lines, 0..) |line, i| {
        try result.appendSlice(allocator, line);
        if (i < lines.len - 1) {
            try result.append(allocator, '\n');
        }
    }

    return result.toOwnedSlice(allocator);
}

test "diff and apply roundtrip" {
    const allocator = std.testing.allocator;
    const original = "hello\nworld\nfoo\n";
    const modified = "hello\nzig\nworld\nbar\n";

    const diffs = try compute(allocator, original, modified);
    defer diffs.deinit();

    const result = try apply(allocator, original, diffs.items);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(modified, result);
}

test "no change" {
    const allocator = std.testing.allocator;
    const text = "hello\nworld\n";
    const diffs = try compute(allocator, text, text);
    defer diffs.deinit();

    try std.testing.expect(diffs.items.len == 1);
    try std.testing.expect(diffs.items[0] == .keep);
}

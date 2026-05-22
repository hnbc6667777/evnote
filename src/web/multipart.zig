const std = @import("std");

pub const MultipartField = struct {
    name: []const u8,
    filename: ?[]const u8,
    content_type: ?[]const u8,
    data: []const u8,
};

pub const ParseResult = struct {
    fields: []MultipartField,
};

pub fn parse(allocator: std.mem.Allocator, body: []const u8, boundary: []const u8) !ParseResult {
    const delim = try std.fmt.allocPrint(allocator, "--{s}", .{boundary});
    defer allocator.free(delim);

    var result: std.ArrayList(MultipartField) = .empty;
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    while (pos < body.len) {
        const part_start = std.mem.indexOfPos(u8, body, pos, delim) orelse break;
        pos = part_start + delim.len;

        if (pos < body.len and body[pos] == '-' and pos + 1 < body.len and body[pos + 1] == '-') {
            break;
        }

        if (pos + 2 > body.len) break;
        pos += 2;

        const header_end = std.mem.indexOfPos(u8, body, pos, "\r\n\r\n") orelse
            std.mem.indexOfPos(u8, body, pos, "\n\n") orelse break;

        const headers_text = body[pos..header_end];
        pos = header_end + (if (std.mem.indexOfPos(u8, body, pos, "\r\n\r\n") != null) @as(usize, 4) else 2);

        const crlf_delim = try std.fmt.allocPrint(allocator, "\r\n--{s}", .{boundary});
        defer allocator.free(crlf_delim);
        const part_end = std.mem.indexOfPos(u8, body, pos, crlf_delim) orelse
            std.mem.indexOfPos(u8, body, pos, "\n--") orelse body.len;

        const part_body = body[pos..part_end];
        pos = part_end;

        var name: []const u8 = "";
        var filename: ?[]const u8 = null;
        var content_type: ?[]const u8 = null;

        var hlines = std.mem.splitScalar(u8, headers_text, '\n');
        while (hlines.next()) |hline| {
            const trimmed = std.mem.trim(u8, hline, "\r ");
            if (std.ascii.startsWithIgnoreCase(trimmed, "Content-Disposition:")) {
                if (extractParam(trimmed, " name=\"")) |n| name = n;
                if (extractParam(trimmed, " filename=\"")) |f| filename = f;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "Content-Type:")) {
                const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
                content_type = std.mem.trim(u8, trimmed[colon + 1 ..], " ");
            }
        }

        var body_trimmed = part_body;
        if (std.mem.endsWith(u8, body_trimmed, "\r\n")) {
            body_trimmed = body_trimmed[0 .. body_trimmed.len - 2];
        } else if (std.mem.endsWith(u8, body_trimmed, "\n")) {
            body_trimmed = body_trimmed[0 .. body_trimmed.len - 1];
        }

        try result.append(allocator, .{
            .name = name,
            .filename = filename,
            .content_type = content_type,
            .data = body_trimmed,
        });
    }

    return .{ .fields = try result.toOwnedSlice(allocator) };
}

fn extractParam(text: []const u8, key: []const u8) ?[]const u8 {
    const start = std.mem.indexOfPos(u8, text, 0, key) orelse return null;
    const val_start = start + key.len;
    const end = std.mem.indexOfScalarPos(u8, text, val_start, '"') orelse return null;
    return text[val_start..end];
}

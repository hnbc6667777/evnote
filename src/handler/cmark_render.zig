const std = @import("std");
const render = @import("../ops/render.zig");

const CMARK_OPT_UNSAFE: c_int = 1 << 17;

extern fn cmark_markdown_to_html(text: [*]const u8, len: usize, options: c_int) ?[*:0]u8;

pub const CmarkRender = struct {
    pub fn handler() render.Render {
        return .{
            .ptr = undefined,
            .vtable = &.{
                .markdownToHtml = struct {
                    fn convert(_: *anyopaque, allocator: std.mem.Allocator, md: []const u8) anyerror![]const u8 {
                        const c_str = cmark_markdown_to_html(md.ptr, md.len, CMARK_OPT_UNSAFE) orelse return error.RenderFailed;
                        defer std.c.free(c_str);
                        const len = std.mem.len(c_str);
                        return allocator.dupe(u8, c_str[0..len]);
                    }
                }.convert,
            },
        };
    }
};

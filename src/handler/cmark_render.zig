const std = @import("std");
const render = @import("../ops/render.zig");

const CMARK_OPT_DEFAULT: c_int = 0;
const CMARK_OPT_UNSAFE: c_int = 1 << 17;

const cmark_node = opaque {};
const cmark_parser = opaque {};
const cmark_syntax_extension = opaque {};
const cmark_llist = opaque {};
const cmark_mem = opaque {};

extern fn cmark_parser_new(options: c_int) ?*cmark_parser;
extern fn cmark_parser_feed(parser: *cmark_parser, buffer: [*]const u8, len: usize) void;
extern fn cmark_parser_finish(parser: *cmark_parser) ?*cmark_node;
extern fn cmark_parser_free(parser: *cmark_parser) void;
extern fn cmark_parser_attach_syntax_extension(parser: *cmark_parser, extension: *cmark_syntax_extension) c_int;
extern fn cmark_parser_get_syntax_extensions(parser: *cmark_parser) ?*cmark_llist;
extern fn cmark_find_syntax_extension(name: [*:0]const u8) ?*cmark_syntax_extension;
extern fn cmark_render_html(root: *cmark_node, options: c_int, extensions: ?*cmark_llist) ?[*:0]u8;
extern fn cmark_node_free(root: *cmark_node) void;
extern fn free(ptr: ?*anyopaque) void;
extern fn cmark_gfm_core_extensions_ensure_registered() void;

pub const CmarkGfmRender = struct {
    pub fn handler() render.Render {
        cmark_gfm_core_extensions_ensure_registered();

        const extension_names = [_][*:0]const u8{
            "table",
            "strikethrough",
            "autolink",
            "tagfilter",
            "tasklist",
        };

        return .{
            .ptr = undefined,
            .vtable = &.{
                .markdownToHtml = struct {
                    fn convert(_: *anyopaque, allocator: std.mem.Allocator, md: []const u8) anyerror![]const u8 {
                        const parser = cmark_parser_new(CMARK_OPT_DEFAULT) orelse return error.RenderFailed;
                        defer cmark_parser_free(parser);

                        for (&extension_names) |name| {
                            if (cmark_find_syntax_extension(name)) |ext| {
                                _ = cmark_parser_attach_syntax_extension(parser, ext);
                            }
                        }

                        cmark_parser_feed(parser, md.ptr, md.len);
                        const doc = cmark_parser_finish(parser) orelse return error.RenderFailed;
                        defer cmark_node_free(doc);

                        const exts = cmark_parser_get_syntax_extensions(parser);
                        const c_str = cmark_render_html(doc, CMARK_OPT_UNSAFE, exts) orelse return error.RenderFailed;
                        defer free(c_str);

                        const len = std.mem.len(c_str);
                        return allocator.dupe(u8, c_str[0..len]);
                    }
                }.convert,
            },
        };
    }
};

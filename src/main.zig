const std = @import("std");
const context = @import("effect/context.zig");
const server = @import("web/server.zig");
const router = @import("web/router.zig");
const static_mod = @import("web/static.zig");
const stdio_log = @import("handler/stdio_log.zig");
const note_handler = @import("web/handler/note.zig");
const user_handler = @import("web/handler/user.zig");
const auth_handler = @import("web/handler/auth.zig");
const version_handler = @import("web/handler/version.zig");
const file_handler = @import("web/handler/file.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const log = stdio_log.handler();
    log.info("starting notes server");

    var mem_storage = @import("handler/test_doubles.zig").MemStorage.init(allocator);
    var mem_auth = @import("handler/test_doubles.zig").MemAuth.init(allocator);
    var mem_files = @import("handler/mem_file_store.zig").MemFileStore.init(allocator);

    const ctx = context.Context{
        .allocator = allocator,
        .storage = mem_storage.handler(),
        .auth = mem_auth.handler(),
        .render = @import("handler/test_doubles.zig").MemRender.handler(),
        .log = log,
        .file_store = mem_files.handler(),
    };
    const ctx_ptr: *const context.Context = &ctx;

    var rtr = router.Router.init();
    rtr.get(allocator, "/", staticHandler) catch {};
    rtr.post(allocator, "/api/auth/login", auth_handler.login) catch {};
    rtr.post(allocator, "/api/auth/register", user_handler.register) catch {};
    rtr.post(allocator, "/api/users", user_handler.register) catch {};
    rtr.get(allocator, "/api/notes", note_handler.list) catch {};
    rtr.post(allocator, "/api/notes", note_handler.create) catch {};
    rtr.get(allocator, "/api/notes/:id", note_handler.get) catch {};
    rtr.put(allocator, "/api/notes/:id", note_handler.update) catch {};
    rtr.delete(allocator, "/api/notes/:id", note_handler.delete) catch {};
    rtr.get(allocator, "/api/users/:id", user_handler.get) catch {};
    rtr.get(allocator, "/api/notes/:id/versions", version_handler.list) catch {};
    rtr.get(allocator, "/api/notes/:id/versions/:seq", version_handler.getAt) catch {};
    rtr.post(allocator, "/api/files", file_handler.upload) catch {};
    rtr.get(allocator, "/api/files", file_handler.list) catch {};
    rtr.get(allocator, "/api/files/:id", file_handler.get) catch {};
    rtr.delete(allocator, "/api/files/:id", file_handler.delete) catch {};

    var srv = server.Server.init(allocator, ctx_ptr, io, rtr);
    try srv.listen(8080);
}

fn staticHandler(_: *const context.Context, _: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    return static_mod.serveHtml(allocator);
}

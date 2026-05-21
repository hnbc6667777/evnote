const std = @import("std");
const storage = @import("../ops/storage.zig");
const auth = @import("../ops/auth.zig");
const render = @import("../ops/render.zig");
const log_mod = @import("../ops/log.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    storage: storage.Storage,
    auth: auth.Auth,
    render: render.Render,
    log: log_mod.Log,

    pub fn init(
        allocator: std.mem.Allocator,
        storage_impl: anytype,
        auth_impl: anytype,
        render_impl: anytype,
        log_impl: anytype,
    ) Context {
        return .{
            .allocator = allocator,
            .storage = storage_impl.handler(),
            .auth = auth_impl.handler(),
            .render = render_impl.handler(),
            .log = log_impl.handler(),
        };
    }
};

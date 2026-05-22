const std = @import("std");
const storage = @import("../ops/storage.zig");
const auth = @import("../ops/auth.zig");
const render = @import("../ops/render.zig");
const log_mod = @import("../ops/log.zig");
const file_store = @import("../ops/file_store.zig");
const workflow_store = @import("../ops/workflow.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    storage: storage.Storage,
    auth: auth.Auth,
    render: render.Render,
    log: log_mod.Log,
    file_store: file_store.FileStore,
    workflow_store: workflow_store.WorkflowStore,
};

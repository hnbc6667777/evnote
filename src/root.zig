pub const domain = struct {
    pub const errors = @import("domain/error.zig");
    pub const event = @import("domain/event.zig");
    pub const note = @import("domain/note.zig");
    pub const user = @import("domain/user.zig");
    pub const diff = @import("domain/diff.zig");
    pub const time = @import("domain/time.zig");
};

pub const ops = struct {
    pub const storage = @import("ops/storage.zig");
    pub const auth = @import("ops/auth.zig");
    pub const render = @import("ops/render.zig");
    pub const log = @import("ops/log.zig");
};

pub const effect = struct {
    pub const context = @import("effect/context.zig");
};

pub const handler = struct {
    pub const test_doubles = @import("handler/test_doubles.zig");
    pub const stdio_log = @import("handler/stdio_log.zig");
};

pub const service = struct {
    pub const note_service = @import("service/note_service.zig");
    pub const user_service = @import("service/user_service.zig");
    pub const auth_service = @import("service/auth_service.zig");
    pub const version_service = @import("service/version_service.zig");
};

pub const web = struct {
    pub const server = @import("web/server.zig");
    pub const router = @import("web/router.zig");
    pub const json = @import("web/json.zig");
    pub const handler = struct {
        pub const note = @import("web/handler/note.zig");
        pub const user = @import("web/handler/user.zig");
        pub const auth = @import("web/handler/auth.zig");
    };
};

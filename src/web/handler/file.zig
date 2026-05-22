const std = @import("std");
const base64 = std.base64;
const router = @import("../router.zig");
const json = @import("../json.zig");
const multipart = @import("../multipart.zig");
const Context = @import("../../effect/context.zig").Context;

const MAX_UPLOAD: usize = 10 * 1024 * 1024;

pub fn upload(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, uid_str, 10) catch 0;
    if (user_id == 0) return router.Response.jsonError(allocator, 401, "Unauthorized");

    const content_type = req.headers.get("Content-Type") orelse "";
    const is_multipart = std.ascii.indexOfIgnoreCase(content_type, "multipart/form-data") != null;

    if (is_multipart) {
        return uploadMultipart(ctx, req, allocator, user_id);
    }

    var parsed = json.parse(allocator, req.body) catch {
        return router.Response.jsonError(allocator, 400, "Invalid JSON");
    };
    defer parsed.deinit(allocator);

    const filename = json.objectGetString(parsed, "filename") orelse return router.Response.jsonError(allocator, 400, "Missing filename");
    const content_type_val = json.objectGetString(parsed, "content_type") orelse "application/octet-stream";
    const b64 = json.objectGetString(parsed, "data") orelse return router.Response.jsonError(allocator, 400, "Missing data");

    const decoded_len = base64.standard.Decoder.calcSizeForSlice(b64) catch return router.Response.jsonError(allocator, 400, "Invalid base64");
    if (decoded_len > MAX_UPLOAD) return router.Response.jsonError(allocator, 413, "File too large");

    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);
    try base64.standard.Decoder.decode(decoded, b64);

    const rec = ctx.file_store.save(allocator, user_id, filename, content_type_val, decoded) catch |err| {
        return router.Response.jsonError(allocator, 500, @errorName(err));
    };
    defer {
        allocator.free(rec.filename);
        allocator.free(rec.content_type);
    }

    var obj = std.StringHashMap(json.Value).init(allocator);
    try obj.put("id", .{ .int = @intCast(rec.id) });
    try obj.put("filename", .{ .string = rec.filename });
    try obj.put("content_type", .{ .string = rec.content_type });
    try obj.put("size", .{ .int = @intCast(rec.size) });
    return router.Response.json(allocator, 201, .{ .object = obj });
}

fn uploadMultipart(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator, user_id: u64) !router.Response {
    const content_type = req.headers.get("Content-Type") orelse "";
    const boundary_start = std.mem.indexOf(u8, content_type, "boundary=") orelse return router.Response.jsonError(allocator, 400, "Missing boundary");
    const boundary = content_type[boundary_start + 9 ..];

    const parsed = multipart.parse(allocator, req.body, boundary) catch |err| {
        return router.Response.jsonError(allocator, 400, @errorName(err));
    };
    defer {
        for (parsed.fields) |f| {
            if (f.filename) |fn_| allocator.free(fn_);
        }
        allocator.free(parsed.fields);
    }

    for (parsed.fields) |field| {
        if (field.filename) |fname| {
            if (field.data.len > MAX_UPLOAD) return router.Response.jsonError(allocator, 413, "File too large");
            const ctype = field.content_type orelse "application/octet-stream";
            const rec = ctx.file_store.save(allocator, user_id, fname, ctype, field.data) catch |err| {
                return router.Response.jsonError(allocator, 500, @errorName(err));
            };
            defer {
                allocator.free(rec.filename);
                allocator.free(rec.content_type);
            }
            var obj = std.StringHashMap(json.Value).init(allocator);
            try obj.put("id", .{ .int = @intCast(rec.id) });
            try obj.put("filename", .{ .string = rec.filename });
            try obj.put("content_type", .{ .string = rec.content_type });
            try obj.put("size", .{ .int = @intCast(rec.size) });
            return router.Response.json(allocator, 201, .{ .object = obj });
        }
    }

    return router.Response.jsonError(allocator, 400, "No file found in upload");
}

pub fn get(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");

    const meta = ctx.file_store.get(allocator, id) catch return router.Response.jsonError(allocator, 500, "Get failed");
    if (meta) |m| {
        defer { allocator.free(m.filename); allocator.free(m.content_type); }
        const data = ctx.file_store.getData(allocator, id) catch return router.Response.jsonError(allocator, 500, "Read failed");
        var headers = std.StringHashMapUnmanaged([]const u8){};
        try headers.put(allocator, "Content-Type", m.content_type);
        try headers.put(allocator, "Content-Disposition", "inline");
        return router.Response{ .status = 200, .headers = headers, .body = data };
    }
    return router.Response.jsonError(allocator, 404, "File not found");
}

pub fn list(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, uid_str, 10) catch 0;

    const files = ctx.file_store.list(allocator, user_id) catch return router.Response.jsonError(allocator, 500, "List failed");
    defer {
        for (files) |f| { allocator.free(f.filename); allocator.free(f.content_type); }
        allocator.free(files);
    }

    var arr: std.ArrayList(json.Value) = .empty;
    errdefer { for (arr.items) |*v| v.deinit(allocator); arr.deinit(allocator); }

    for (files) |f| {
        var obj = std.StringHashMap(json.Value).init(allocator);
        try obj.put("id", .{ .int = @intCast(f.id) });
        try obj.put("filename", .{ .string = try allocator.dupe(u8, f.filename) });
        try obj.put("content_type", .{ .string = try allocator.dupe(u8, f.content_type) });
        try obj.put("size", .{ .int = @intCast(f.size) });
        try obj.put("created_at", .{ .int = f.created_at });
        try arr.append(allocator, .{ .object = obj });
    }

    return router.Response.json(allocator, 200, .{ .array = arr });
}

pub fn delete(ctx: *const Context, req: *const router.Request, allocator: std.mem.Allocator) !router.Response {
    const id_str = req.params.get("id") orelse return router.Response.jsonError(allocator, 400, "Missing id");
    const id = std.fmt.parseInt(u64, id_str, 10) catch return router.Response.jsonError(allocator, 400, "Invalid id");
    const uid_str = req.headers.get("x-user-id") orelse "0";
    const user_id = std.fmt.parseInt(u64, uid_str, 10) catch 0;

    ctx.file_store.delete(allocator, user_id, id) catch return router.Response.jsonError(allocator, 500, "Delete failed");
    const empty_obj = std.StringHashMap(json.Value).init(allocator);
    return router.Response.json(allocator, 200, .{ .object = empty_obj });
}

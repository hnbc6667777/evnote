const std = @import("std");
const wf = @import("../domain/workflow.zig");
const time = @import("../domain/time.zig");

pub const MemWorkflowStore = struct {
    arena: std.heap.ArenaAllocator,
    defs: std.AutoArrayHashMapUnmanaged(u64, wf.WorkflowDef) = .{},
    instances: std.AutoArrayHashMapUnmanaged(u64, wf.WorkflowInstance) = .{},
    tasks: std.ArrayListUnmanaged(wf.WorkflowTask) = .{ .items = &.{}, .capacity = 0 },
    def_next_id: u64 = 1,
    inst_next_id: u64 = 1,
    task_next_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) MemWorkflowStore {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }
    pub fn deinit(self: *MemWorkflowStore) void { self.arena.deinit(); }

    pub fn handler(self: *MemWorkflowStore) @import("../ops/workflow.zig").WorkflowStore {
        return .{ .ptr = self, .vtable = &.{
            .createDef = struct {
                fn f(ctx: *anyopaque, def: wf.WorkflowDef) anyerror!u64 {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    const id = s.def_next_id; s.def_next_id += 1;
                    var d = def; d.id = id;
                    try s.defs.put(s.arena.allocator(), id, d);
                    return id;
                }
            }.f,
            .getDef = struct {
                fn f(ctx: *anyopaque, a: std.mem.Allocator, id: u64) anyerror!?wf.WorkflowDef {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    const d = s.defs.get(id) orelse return null;
                    var r = d; r.name = try a.dupe(u8, d.name); r.description = try a.dupe(u8, d.description);
                    return r;
                }
            }.f,
            .listDefs = struct {
                fn f(ctx: *anyopaque, a: std.mem.Allocator) anyerror![]wf.WorkflowDef {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    var r: std.ArrayList(wf.WorkflowDef) = .empty;
                    errdefer r.deinit(a);
                    var it = s.defs.iterator();
                    while (it.next()) |entry| try r.append(a, entry.value_ptr.*);
                    return r.toOwnedSlice(a);
                }
            }.f,
            .createInstance = struct {
                fn f(ctx: *anyopaque, def_id: u64, user_id: u64) anyerror!u64 {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    const id = s.inst_next_id; s.inst_next_id += 1;
                    const now = time.now();
                    const inst = wf.WorkflowInstance{
                        .id = id, .def_id = def_id, .name = "", .status = .active,
                        .created_by = user_id, .created_at = now, .completed_at = null, .next_task_index = 0,
                    };
                    try s.instances.put(s.arena.allocator(), id, inst);
                    const def = s.defs.get(def_id) orelse return error.NotFound;
                    const t = def.root_task;
                    const task = wf.WorkflowTask{
                        .id = s.task_next_id, .instance_id = id, .task_index = 0,
                        .name = try s.arena.allocator().dupe(u8, t.name),
                        .kind = t.kind, .assignment = t.assignment,
                        .due_date = if (t.due_seconds) |ds| @as(i64, now + ds) else null,
                        .status = .active, .result_json = null,
                        .completed_by = null, .completed_at = null, .created_at = now,
                    };
                    s.task_next_id += 1;
                    try s.tasks.append(s.arena.allocator(), task);
                    return id;
                }
            }.f,
            .getInstance = struct {
                fn f(ctx: *anyopaque, a: std.mem.Allocator, id: u64) anyerror!?wf.WorkflowInstance {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    _ = a; return s.instances.get(id);
                }
            }.f,
            .listUserInstances = struct {
                fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64) anyerror![]wf.WorkflowInstance {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    var r: std.ArrayList(wf.WorkflowInstance) = .empty;
                    errdefer r.deinit(a);
                    var it = s.instances.iterator();
                    while (it.next()) |entry| {
                        if (entry.value_ptr.created_by == uid) try r.append(a, entry.value_ptr.*);
                    }
                    return r.toOwnedSlice(a);
                }
            }.f,
            .saveTask = struct {
                fn f(ctx: *anyopaque, t: wf.WorkflowTask) anyerror!void {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    _ = s; _ = t;
                }
            }.f,
            .getInstanceTasks = struct {
                fn f(ctx: *anyopaque, a: std.mem.Allocator, iid: u64) anyerror![]wf.WorkflowTask {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    var r: std.ArrayList(wf.WorkflowTask) = .empty;
                    errdefer r.deinit(a);
                    for (s.tasks.items) |t| { if (t.instance_id == iid) try r.append(a, t); }
                    return r.toOwnedSlice(a);
                }
            }.f,
            .getUserInbox = struct {
                fn f(ctx: *anyopaque, a: std.mem.Allocator, uid: u64, role: ?wf.UserRole) anyerror![]wf.WorkflowTask {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    var r: std.ArrayList(wf.WorkflowTask) = .empty;
                    errdefer r.deinit(a);
                    for (s.tasks.items) |t| {
                        if (t.status != .active) continue;
                        const match = switch (t.assignment) {
                            .creator => true,
                            .user => |u| u == uid,
                            .role => |rl| if (role) |r2| rl == r2 else false,
                            .anyone => true,
                        };
                        if (match) try r.append(a, t);
                    }
                    return r.toOwnedSlice(a);
                }
            }.f,
            .completeTask = struct {
                fn f(ctx: *anyopaque, task_id: u64, user_id: u64, result: []const u8) anyerror!void {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    const now = time.now();
                    for (s.tasks.items) |*t| {
                        if (t.id == task_id) {
                            t.status = .completed;
                            t.result_json = try s.arena.allocator().dupe(u8, result);
                            t.completed_by = user_id;
                            t.completed_at = now;
                        }
                    }
                }
            }.f,
            .updateInstanceStatus = struct {
                fn f(ctx: *anyopaque, id: u64, status: wf.TaskStatus) anyerror!void {
                    const s = @as(*MemWorkflowStore, @ptrCast(@alignCast(ctx)));
                    if (s.instances.getPtr(id)) |inst| { inst.status = status; if (status == .completed) inst.completed_at = time.now(); }
                }
            }.f,
        },
    };
}
};

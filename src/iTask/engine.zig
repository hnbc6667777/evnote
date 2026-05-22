const std = @import("std");
const wf = @import("../domain/workflow.zig");
const ws = @import("../ops/workflow.zig");
const time = @import("../domain/time.zig");

pub fn createDef(store: ws.WorkflowStore, _: std.mem.Allocator, name: []const u8, desc: []const u8, root: wf.TaskDef, user_id: u64) !u64 {
    const def = wf.WorkflowDef{
        .id = 0, .name = name, .description = desc, .root_task = root,
        .created_by = user_id, .created_at = time.now(),
    };
    return store.createDef(def);
}

pub fn listDefs(store: ws.WorkflowStore, allocator: std.mem.Allocator) ![]wf.WorkflowDef {
    return store.listDefs(allocator);
}

pub fn startInstance(store: ws.WorkflowStore, allocator: std.mem.Allocator, def_id: u64, user_id: u64, _user_role: ?wf.UserRole) !u64 {
    _ = _user_role;
    const def = (try store.getDef(allocator, def_id)) orelse return error.NotFound;
    defer { allocator.free(def.name); allocator.free(def.description); }
    const instance_id = try store.createInstance(def_id, user_id);
    const now = time.now();
    const t = def.root_task;
    const task = wf.WorkflowTask{
        .id = 0, .instance_id = instance_id, .task_index = 0,
        .name = t.name, .kind = t.kind, .assignment = t.assignment,
        .due_date = if (t.due_seconds) |ds| now + ds else null,
        .status = .active, .result_json = null,
        .completed_by = null, .completed_at = null, .created_at = now,
    };
    try store.saveTask(task);
    return instance_id;
}

pub fn listMyInstances(store: ws.WorkflowStore, allocator: std.mem.Allocator, user_id: u64) ![]wf.WorkflowInstance {
    return store.listUserInstances(allocator, user_id);
}

pub fn getInstanceDetail(store: ws.WorkflowStore, allocator: std.mem.Allocator, instance_id: u64) !?wf.WorkflowInstance {
    return store.getInstance(allocator, instance_id);
}

pub fn getInstanceTasks(store: ws.WorkflowStore, allocator: std.mem.Allocator, instance_id: u64) ![]wf.WorkflowTask {
    return store.getInstanceTasks(allocator, instance_id);
}

pub fn getUserInbox(store: ws.WorkflowStore, allocator: std.mem.Allocator, user_id: u64, role: ?wf.UserRole) ![]wf.WorkflowTask {
    return store.getUserInbox(allocator, user_id, role);
}

pub fn completeTask(store: ws.WorkflowStore, task_id: u64, user_id: u64, result: []const u8) !void {
    try store.completeTask(task_id, user_id, result);
}

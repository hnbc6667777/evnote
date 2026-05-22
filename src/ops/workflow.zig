const std = @import("std");
const wf = @import("../domain/workflow.zig");

pub const WorkflowStore = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        createDef: *const fn (*anyopaque, wf.WorkflowDef) anyerror!u64,
        getDef: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror!?wf.WorkflowDef,
        listDefs: *const fn (*anyopaque, std.mem.Allocator) anyerror![]wf.WorkflowDef,
        createInstance: *const fn (*anyopaque, u64, u64) anyerror!u64,
        getInstance: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror!?wf.WorkflowInstance,
        listUserInstances: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror![]wf.WorkflowInstance,
        saveTask: *const fn (*anyopaque, wf.WorkflowTask) anyerror!void,
        getInstanceTasks: *const fn (*anyopaque, std.mem.Allocator, u64) anyerror![]wf.WorkflowTask,
        getUserInbox: *const fn (*anyopaque, std.mem.Allocator, u64, ?wf.UserRole) anyerror![]wf.WorkflowTask,
        completeTask: *const fn (*anyopaque, u64, u64, []const u8) anyerror!void,
        updateInstanceStatus: *const fn (*anyopaque, u64, wf.TaskStatus) anyerror!void,
    };

    pub fn createDef(self: WorkflowStore, def: wf.WorkflowDef) !u64 { return self.vtable.createDef(self.ptr, def); }
    pub fn getDef(self: WorkflowStore, a: std.mem.Allocator, id: u64) !?wf.WorkflowDef { return self.vtable.getDef(self.ptr, a, id); }
    pub fn listDefs(self: WorkflowStore, a: std.mem.Allocator) ![]wf.WorkflowDef { return self.vtable.listDefs(self.ptr, a); }
    pub fn createInstance(self: WorkflowStore, def_id: u64, user_id: u64) !u64 { return self.vtable.createInstance(self.ptr, def_id, user_id); }
    pub fn getInstance(self: WorkflowStore, a: std.mem.Allocator, id: u64) !?wf.WorkflowInstance { return self.vtable.getInstance(self.ptr, a, id); }
    pub fn listUserInstances(self: WorkflowStore, a: std.mem.Allocator, uid: u64) ![]wf.WorkflowInstance { return self.vtable.listUserInstances(self.ptr, a, uid); }
    pub fn saveTask(self: WorkflowStore, t: wf.WorkflowTask) !void { return self.vtable.saveTask(self.ptr, t); }
    pub fn getInstanceTasks(self: WorkflowStore, a: std.mem.Allocator, iid: u64) ![]wf.WorkflowTask { return self.vtable.getInstanceTasks(self.ptr, a, iid); }
    pub fn getUserInbox(self: WorkflowStore, a: std.mem.Allocator, uid: u64, role: ?wf.UserRole) ![]wf.WorkflowTask { return self.vtable.getUserInbox(self.ptr, a, uid, role); }
    pub fn completeTask(self: WorkflowStore, task_id: u64, user_id: u64, result: []const u8) !void { return self.vtable.completeTask(self.ptr, task_id, user_id, result); }
    pub fn updateInstanceStatus(self: WorkflowStore, id: u64, status: wf.TaskStatus) !void { return self.vtable.updateInstanceStatus(self.ptr, id, status); }

    pub fn @"null"() WorkflowStore {
        return .{
            .ptr = undefined,
            .vtable = &.{
                .createDef = struct { fn f(_: *anyopaque, _def: wf.WorkflowDef) anyerror!u64 { _ = _def; return error.NotFound; } }.f,
                .getDef = struct { fn f(_: *anyopaque, a: std.mem.Allocator, _id: u64) anyerror!?wf.WorkflowDef { _ = a; _ = _id; return null; } }.f,
                .listDefs = struct { fn f(_: *anyopaque, a: std.mem.Allocator) anyerror![]wf.WorkflowDef { _ = a; return &.{}; } }.f,
                .createInstance = struct { fn f(_: *anyopaque, _did: u64, _uid: u64) anyerror!u64 { _ = _did; _ = _uid; return error.NotFound; } }.f,
                .getInstance = struct { fn f(_: *anyopaque, a: std.mem.Allocator, _id: u64) anyerror!?wf.WorkflowInstance { _ = a; _ = _id; return null; } }.f,
                .listUserInstances = struct { fn f(_: *anyopaque, a: std.mem.Allocator, _uid: u64) anyerror![]wf.WorkflowInstance { _ = a; _ = _uid; return &.{}; } }.f,
                .saveTask = struct { fn f(_: *anyopaque, _t: wf.WorkflowTask) anyerror!void { _ = _t; } }.f,
                .getInstanceTasks = struct { fn f(_: *anyopaque, a: std.mem.Allocator, _iid: u64) anyerror![]wf.WorkflowTask { _ = a; _ = _iid; return &.{}; } }.f,
                .getUserInbox = struct { fn f(_: *anyopaque, a: std.mem.Allocator, _uid: u64, _role: ?wf.UserRole) anyerror![]wf.WorkflowTask { _ = a; _ = _uid; _ = _role; return &.{}; } }.f,
                .completeTask = struct { fn f(_: *anyopaque, _tid: u64, _uid: u64, _r: []const u8) anyerror!void { _ = _tid; _ = _uid; _ = _r; } }.f,
                .updateInstanceStatus = struct { fn f(_: *anyopaque, _id: u64, _s: wf.TaskStatus) anyerror!void { _ = _id; _ = _s; } }.f,
            },
        };
    }
};

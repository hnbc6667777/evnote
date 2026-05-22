const std = @import("std");
const user = @import("user.zig");

pub const UserRole = user.Role;

pub const TaskStatus = enum(u8) {
    pending = 0,
    active = 1,
    completed = 2,
    cancelled = 3,
};

pub const FieldDef = struct {
    label: []const u8,
    kind: FieldKind,
    required: bool,
};

pub const FieldKind = union(enum) {
    text: struct { default: []const u8 },
    number: struct { default: i64 },
    checkbox: struct { default: bool },
    select: struct { options: []const []const u8 },
    textarea: struct { default: []const u8 },
};

pub const TaskKind = union(enum) {
    form: []FieldDef,
    choice: []const []const u8,
    notify: []const u8,
    subflow: u64,
    parallel: struct { branches: []TaskDef },
    seq: struct { first: *TaskDef, next: *TaskDef },
};

pub const Assignment = union(enum) {
    creator,
    user: u64,
    role: UserRole,
    anyone,
};

pub const TaskDef = struct {
    name: []const u8,
    kind: TaskKind,
    assignment: Assignment = .creator,
    due_seconds: ?i64 = null,
    children: []TaskDef = &.{},

    pub fn assignedTo(self: TaskDef, a: Assignment) TaskDef {
        var r = self;
        r.assignment = a;
        return r;
    }

    pub fn dueIn(self: TaskDef, secs: i64) TaskDef {
        var r = self;
        r.due_seconds = secs;
        return r;
    }
};

pub const WorkflowDef = struct {
    id: u64,
    name: []const u8,
    description: []const u8,
    root_task: TaskDef,
    created_by: u64,
    created_at: i64,
};

pub const WorkflowInstance = struct {
    id: u64,
    def_id: u64,
    name: []const u8,
    status: TaskStatus,
    created_by: u64,
    created_at: i64,
    completed_at: ?i64,
    next_task_index: u64,
};

pub const WorkflowTask = struct {
    id: u64,
    instance_id: u64,
    task_index: u64,
    name: []const u8,
    kind: TaskKind,
    assignment: Assignment,
    due_date: ?i64,
    status: TaskStatus,
    result_json: ?[]const u8,
    completed_by: ?u64,
    completed_at: ?i64,
    created_at: i64,
};

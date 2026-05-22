const std = @import("std");
const wf = @import("../domain/workflow.zig");

pub const TaskBuilder = struct {
    pub fn form(comptime T: type, name: []const u8) wf.TaskDef {
        const fields = comptime generateFields(T);
        return .{ .name = name, .kind = .{ .form = fields } };
    }

    pub fn choice(name: []const u8, options: []const []const u8) wf.TaskDef {
        return .{ .name = name, .kind = .{ .choice = options } };
    }

    pub fn notify(name: []const u8, message: []const u8) wf.TaskDef {
        return .{ .name = name, .kind = .{ .notify = message } };
    }

    pub fn subflow(name: []const u8, def_id: u64) wf.TaskDef {
        return .{ .name = name, .kind = .{ .subflow = def_id } };
    }

    pub fn seq(first: wf.TaskDef, second: wf.TaskDef) wf.TaskDef {
        return .{ .name = first.name, .kind = .{ .seq = .{ .first = @constCast(&first), .next = @constCast(&second) } }, .children = &.{ first, second } };
    }

    pub fn parallel(tasks: []const wf.TaskDef) wf.TaskDef {
        return .{ .name = "parallel", .kind = .{ .parallel = .{ .branches = tasks } }, .children = tasks };
    }
};

fn generateFields(comptime T: type) []wf.FieldDef {
    _ = T;
    return &.{};
}

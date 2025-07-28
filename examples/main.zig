const std = @import("std");

const Shapes = @import("shapes.zig").Shapes;

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // run examples one by one
    Shapes(allocator) catch |err| {
        std.debug.print("Error running Shapes example: {}\n", .{err});
    };
}

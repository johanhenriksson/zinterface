const std = @import("std");

pub const Interface = @import("interface.zig").Interface;
pub const validateDefinition = @import("definition.zig").validateDefinition;
pub const validateImplementation = @import("implementation.zig").validateImplementation;
pub const fnCast = @import("utility.zig").fnCast;

test {
    std.testing.log_level = .debug;
    std.testing.refAllDecls(@This());
}

const TestInterface = struct {
    ptr: *anyopaque,
    vtable: struct {
        add: *const fn (self: *const anyopaque, v: i32) i32,
        sub: ?*const fn (self: *anyopaque, v: i32) i32,
    },

    pub fn add(self: TestInterface, v: i32) i32 {
        return self.vtable.add(self.ptr, v);
    }

    pub fn sub(self: TestInterface, v: i32) i32 {
        if (self.vtable.sub) |subFn| {
            return subFn(self.ptr, v);
        }
        return v;
    }
};

test "method calls" {
    const Constant = struct {
        const Self = @This();
        value: i32,

        pub fn add(self: *const Self, v: i32) i32 {
            return v + self.value;
        }
        pub fn sub(self: *Self, v: i32) i32 {
            return v - self.value;
        }
    };

    var impl = Constant{ .value = 1 };
    var iface = Interface(TestInterface, &impl);

    const addResult = iface.add(1);
    try std.testing.expectEqual(2, addResult);

    const subResult = iface.sub(2);
    try std.testing.expectEqual(1, subResult);
}

test "optional method" {
    const AddOne = struct {
        pub fn add(self: *const @This(), v: i32) i32 {
            _ = self;
            return v + 1;
        }
    };
    var impl = AddOne{};
    const iface = Interface(TestInterface, &impl);

    const addResult = iface.add(1);
    try std.testing.expectEqual(2, addResult);
}

test "mutability cast" {
    const Identity = struct {
        const Self = @This();

        pub fn add(self: *const Self, v: i32) i32 {
            _ = self;
            return v;
        }
        pub fn sub(self: *const Self, v: i32) i32 {
            // declaring self as const should still satisfy the interface,
            // since the interface is defined with a mutable pointer
            _ = self;
            return v;
        }
    };

    var impl = Identity{};
    var iface = Interface(TestInterface, &impl);

    const addResult = iface.add(1);
    try std.testing.expectEqual(1, addResult);
}

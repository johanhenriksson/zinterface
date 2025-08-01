const validateMethodSignature = @import("implementation.zig").validateMethodSignature;

pub fn fnCast(comptime T: type, ptr: anytype) *const T {
    const P = @TypeOf(ptr);
    const actualPtr = @typeInfo(P);

    const expected = T;
    const expectedInfo = @typeInfo(expected);
    comptime if (expectedInfo != .@"fn") {
        @compileError("Expected T to be a function type, got " ++ @typeName(expected));
    };

    comptime if (actualPtr != .pointer) {
        @compileError("Expected ptr to be a pointer, got " ++ @typeName(P));
    };
    const actual = actualPtr.pointer.child;
    const actualInfo = @typeInfo(actual);
    comptime if (actualInfo != .@"fn") {
        @compileError("Expected ptr to be a function pointer, got " ++ @typeName(actual));
    };

    comptime if (validateMethodSignature(expected, actual)) |err| {
        @compileError("Function pointers are incompatible: " ++ err.message());
    };

    return @ptrCast(ptr);
}

test "function pointer casts" {
    const Actual = fn (self: *anyopaque, v: *const i32) i32;

    // ok:
    const ptr1: *const fn (self: *const anyopaque, v: *const i32) i32 = undefined;
    _ = fnCast(Actual, ptr1);

    // not ok:
    // const ptr2: *const fn (self: *const anyopaque, v: *i32) i32 = undefined;
    // _ = fnCast(Actual, ptr2);
}

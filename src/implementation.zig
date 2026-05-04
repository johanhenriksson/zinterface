const std = @import("std");
const Type = std.builtin.Type;
const Interface = @import("interface.zig").Interface;
const InterfaceError = @import("error.zig").InterfaceError;

pub fn validateImplementation(comptime InterfaceType: type, comptime ImplType: type) ?InterfaceError {
    const VtablePtrType = @TypeOf(@as(InterfaceType, undefined).vtable);
    const VtableType = @typeInfo(VtablePtrType).pointer.child;
    const vtableInfo = @typeInfo(VtableType);
    const vtableFields = vtableInfo.@"struct".fields;

    inline for (vtableFields) |field| {
        var fieldType = field.type;
        var interfaceMethodPtrInfo = @typeInfo(field.type);
        var optional = false;
        if (interfaceMethodPtrInfo == .optional) {
            optional = true;
            fieldType = interfaceMethodPtrInfo.optional.child;
            interfaceMethodPtrInfo = @typeInfo(fieldType);
        }

        const methodName = field.name;
        if (!@hasDecl(ImplType, methodName)) {
            if (optional) {
                continue;
            }
            return .{ .missingMethod = .{ .method = methodName } };
        }

        const implementationField = @field(ImplType, methodName);
        const implementationFnType = @TypeOf(implementationField);
        const implementationInfo = @typeInfo(implementationFnType);
        if (implementationInfo != .@"fn") {
            return .{ .invalidMethod = .{ .method = methodName } };
        }

        const interfaceFnType = interfaceMethodPtrInfo.pointer.child;
        if (validateMethodSignature(methodName, interfaceFnType, implementationFnType)) |err| {
            return err;
        }
    }

    // no errors found
    return null;
}

pub fn validateMethodSignature(comptime methodName: []const u8, comptime ExpectedFn: type, comptime ActualFn: type) ?InterfaceError {
    const expectedFn = @typeInfo(ExpectedFn).@"fn";
    const actualFn = @typeInfo(ActualFn).@"fn";

    // Check parameter count
    if (expectedFn.params.len != actualFn.params.len) {
        return .{
            .wrongParameterCount = .{
                .method = methodName,
                .expected = expectedFn.params.len,
                .actual = actualFn.params.len,
            },
        };
    }

    // Check return type
    if (expectedFn.return_type != actualFn.return_type) {
        const expectedRet = if (expectedFn.return_type) |t| @typeName(t) else "void";
        const actualRet = if (actualFn.return_type) |t| @typeName(t) else "void";
        return .{
            .wrongReturnType = .{
                .method = methodName,
                .expected = expectedRet,
                .actual = actualRet,
            },
        };
    }

    // Check parameter types
    parameter: inline for (expectedFn.params, actualFn.params, 0..) |expectedParam, actualParam, index| {
        const expectedType = expectedParam.type.?;
        const actualType = actualParam.type.?;
        const actualInfo = @typeInfo(actualType);

        // allow casts of anyopaque to specific pointer types
        if (expectedType == *const anyopaque) {
            if (actualInfo == .pointer) {
                // reject if the actual pointer is mutable
                if (!actualInfo.pointer.is_const) {
                    return .{
                        .invalidPointerCast = .{
                            .method = methodName,
                            .index = index,
                            .expected = @typeName(expectedType),
                            .actual = @typeName(actualType),
                        },
                    };
                }

                // allow cast of more specific pointers to *const anyopaque
                // skip type check
                continue :parameter;
            }
        }
        if (expectedType == *anyopaque) {
            if (actualInfo == .pointer) {
                // allow cast of specific pointers to *const anyopaque
                // skip type check
                continue :parameter;
            }
        }

        if (expectedType != actualType) {
            return .{
                .wrongParameterType = .{
                    .method = methodName,
                    .index = index,
                    .expected = @typeName(expectedType),
                    .actual = @typeName(actualType),
                },
            };
        }
    }

    return null;
}

const TestInterface = struct {
    ptr: *anyopaque,
    vtable: *const struct {
        method: *const fn (*const anyopaque, i32) i32,
    },
};

test "missing method" {
    const Impl = struct {};
    const error1 = comptime validateImplementation(TestInterface, Impl);
    try std.testing.expectEqualDeep(InterfaceError{
        .missingMethod = .{ .method = "method" },
    }, error1);

    // comptime error1.?.raise(TestInterface, Impl);
}

test "invalid method" {
    const Impl = struct {
        pub const method = struct {};
    };
    const error1 = comptime validateImplementation(TestInterface, Impl);
    try std.testing.expectEqualDeep(InterfaceError{
        .invalidMethod = .{ .method = "method" },
    }, error1);

    // comptime error1.?.raise(TestInterface, Impl);
}

test "return value checks" {
    const result = validateMethodSignature(
        "method",
        fn (*anyopaque) i32,
        fn (*anyopaque) i32,
    );
    try std.testing.expectEqual(null, result);

    const error1 = comptime validateMethodSignature(
        "method",
        fn (*anyopaque) i32,
        fn (*anyopaque) void,
    );
    try std.testing.expectEqualDeep(InterfaceError{ .wrongReturnType = .{
        .method = "method",
        .expected = "i32",
        .actual = "void",
    } }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

test "parameter type check" {
    const result = validateMethodSignature(
        "method",
        fn (*anyopaque, i32) void,
        fn (*anyopaque, i32) void,
    );
    try std.testing.expectEqual(null, result);

    const error1 = comptime validateMethodSignature(
        "method",
        fn (*anyopaque, i32) void,
        fn (*anyopaque, f32) void,
    );
    try std.testing.expectEqualDeep(InterfaceError{ .wrongParameterType = .{
        .method = "method",
        .index = 1,
        .expected = "i32",
        .actual = "f32",
    } }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

test "anyopaque pointer casts" {
    // allow cast of mutable anyopaque to mutable specific pointer
    const result1 = validateMethodSignature(
        "method",
        fn (*anyopaque, *anyopaque) void,
        fn (*anyopaque, *i32) void,
    );
    try std.testing.expectEqual(null, result1);

    // allow cast of mutable anyopaque to specific const pointer
    const result2 = validateMethodSignature(
        "method",
        fn (*anyopaque, *anyopaque) void,
        fn (*anyopaque, *const i32) void,
    );
    try std.testing.expectEqual(null, result2);

    // allow cast of const anyopaque to const specific pointer
    const result3 = validateMethodSignature(
        "method",
        fn (*anyopaque, *const anyopaque) void,
        fn (*anyopaque, *const i32) void,
    );
    try std.testing.expectEqual(null, result3);

    // reject cast of const anyopaque to mutable specific pointer
    const error1 = comptime validateMethodSignature(
        "method",
        fn (*anyopaque, *const anyopaque) void,
        fn (*anyopaque, *i32) void,
    );
    try std.testing.expectEqualDeep(InterfaceError{
        .invalidPointerCast = .{
            .method = "method",
            .index = 1,
            .expected = "*const anyopaque",
            .actual = "*i32",
        },
    }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

test "wrong parameter count" {
    const error1 = comptime validateMethodSignature(
        "method",
        fn (*anyopaque, i32, f32) void,
        fn (*anyopaque, i32) void,
    );
    try std.testing.expectEqualDeep(InterfaceError{ .wrongParameterCount = .{
        .method = "method",
        .expected = 3,
        .actual = 2,
    } }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

const std = @import("std");
const Type = std.builtin.Type;
const Interface = @import("interface.zig").Interface;

const ImplementationError = union(enum) {
    missingMethod: struct { method: []const u8 },
    invalidMethod: struct { method: []const u8 },
    signatureError: struct {
        method: []const u8,
        inner: MethodError,
    },

    pub fn raise(self: ImplementationError, comptime InterfaceType: type, comptime ImplType: type) void {
        const msg = std.fmt.comptimePrint("{s} implementation {s}", .{
            @typeName(InterfaceType),
            @typeName(ImplType),
        });
        switch (self) {
            .missingMethod => @compileError(msg ++ " is missing method '" ++ self.missingMethod.method ++ "'"),
            .invalidMethod => @compileError(msg ++ " expected '" ++ self.invalidMethod.method ++ "' to be a method"),
            .signatureError => |err| {
                err.inner.raise(ImplType, err.method);
            },
        }
    }
};

pub fn validateImplementation(comptime InterfaceType: type, comptime ImplType: type) ?ImplementationError {
    const iface: InterfaceType = undefined;

    // find all vtable fields and match them to methods
    const vtableInfo = @typeInfo(@TypeOf(iface.vtable));
    for (vtableInfo.@"struct".fields) |field| {
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

        // compare signatures
        const implementationField = @field(ImplType, methodName);
        const implementationFnType = @TypeOf(implementationField);
        const implementationInfo = @typeInfo(implementationFnType);
        if (implementationInfo != .@"fn") {
            return .{ .invalidMethod = .{ .method = methodName } };
        }

        const interfaceFnType = interfaceMethodPtrInfo.pointer.child;
        if (validateMethodSignature(interfaceFnType, implementationFnType)) |err| {
            return .{ .signatureError = .{ .method = methodName, .inner = err } };
        }
    }

    // no errors found
    return null;
}

const MethodError = union(enum) {
    wrongParameterCount: struct { expected: usize, actual: usize },
    returnType: struct { expected: []const u8, actual: []const u8 },
    parameterType: struct {
        index: usize,
        expected: []const u8,
        actual: []const u8,
    },
    pointerCast: struct {
        index: usize,
        expected: []const u8,
        actual: []const u8,
    },

    pub fn raise(self: MethodError, comptime T: type, comptime methodName: []const u8) void {
        const name = std.fmt.comptimePrint("{s}.{s}", .{ @typeName(T), methodName });
        switch (self) {
            .wrongParameterCount => |err| @compileError(std.fmt.comptimePrint(
                "Interface method {s} has wrong parameter count: expected {d}, got {d}",
                .{ name, err.expected, err.actual },
            )),
            .returnType => |err| {
                @compileError(std.fmt.comptimePrint(
                    "Interface method {s} has wrong return type: expected {s}, got {s}",
                    .{ name, err.expected, err.actual },
                ));
            },
            .parameterType => |err| {
                @compileError(std.fmt.comptimePrint(
                    "Interface method {s} parameter {d} has wrong type: expected {s}, got {s}",
                    .{ name, err.index, err.expected, err.actual },
                ));
            },
            .pointerCast => |err| {
                @compileError(std.fmt.comptimePrint(
                    "Interface method {s} parameter {d} cant be cast from const {s} to mutable {s}",
                    .{ name, err.index, err.expected, err.actual },
                ));
            },
        }
    }
};

fn validateMethodSignature(comptime ExpectedFn: type, comptime ActualFn: type) ?MethodError {
    const expectedFn = @typeInfo(ExpectedFn).@"fn";
    const actualFn = @typeInfo(ActualFn).@"fn";

    // Check parameter count
    if (expectedFn.params.len != actualFn.params.len) {
        return .{
            .wrongParameterCount = .{
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
            .returnType = .{
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

        // allow casts of specific pointer types to *anyopaque/*const anyopaque
        if (expectedType == *anyopaque) {
            if (actualInfo == .pointer) {
                // reject if the actual pointer is const
                if (actualInfo.pointer.is_const) {
                    return .{
                        .pointerCast = .{
                            .index = index,
                            .expected = @typeName(expectedType),
                            .actual = @typeName(actualType),
                        },
                    };
                }

                // allow cast of more specific pointers to *anyopaque
                // skip type check
                continue :parameter;
            }
        }
        if (expectedType == *const anyopaque) {
            if (actualInfo == .pointer) {
                // allow cast of specific pointers to *const anyopaque
                // skip type check
                continue :parameter;
            }
        }

        if (expectedType != actualType) {
            return .{
                .parameterType = .{
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
    vtable: struct {
        method: *const fn (*const anyopaque, i32) i32,
    },
};

test "missing method" {
    const Impl = struct {};
    const error1 = comptime validateImplementation(TestInterface, Impl);
    try std.testing.expectEqualDeep(ImplementationError{
        .missingMethod = .{ .method = "method" },
    }, error1);

    // comptime error1.?.raise(TestInterface, Impl);
}

test "invalid method" {
    const Impl = struct {
        pub const method = struct {};
    };
    const error1 = comptime validateImplementation(TestInterface, Impl);
    try std.testing.expectEqualDeep(ImplementationError{
        .invalidMethod = .{ .method = "method" },
    }, error1);

    // comptime error1.?.raise(TestInterface, Impl);
}

test "return value checks" {
    const result = validateMethodSignature(
        fn (*anyopaque) i32,
        fn (*anyopaque) i32,
    );
    try std.testing.expectEqual(null, result);

    const error1 = comptime validateMethodSignature(
        fn (*anyopaque) i32,
        fn (*anyopaque) void,
    );
    try std.testing.expectEqualDeep(MethodError{ .returnType = .{
        .expected = "i32",
        .actual = "void",
    } }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

test "parameter type check" {
    const result = validateMethodSignature(
        fn (*anyopaque, i32) void,
        fn (*anyopaque, i32) void,
    );
    try std.testing.expectEqual(null, result);

    const error1 = comptime validateMethodSignature(
        fn (*anyopaque, i32) void,
        fn (*anyopaque, f32) void,
    );
    try std.testing.expectEqualDeep(MethodError{ .parameterType = .{
        .index = 1,
        .expected = "i32",
        .actual = "f32",
    } }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

test "anyopaque pointer casts" {
    // allow cast of mutable specific pointer to mutable anyopaque
    const result1 = validateMethodSignature(
        fn (*anyopaque, *anyopaque) void,
        fn (*anyopaque, *i32) void,
    );
    try std.testing.expectEqual(null, result1);

    // allow cast of specific mutable pointer to const anyopaque
    const result2 = validateMethodSignature(
        fn (*anyopaque, *const anyopaque) void,
        fn (*anyopaque, *i32) void,
    );
    try std.testing.expectEqual(null, result2);

    // allow cast of const specific pointer to const anyopaque
    const result3 = validateMethodSignature(
        fn (*anyopaque, *const anyopaque) void,
        fn (*anyopaque, *const i32) void,
    );
    try std.testing.expectEqual(null, result3);

    // reject cast of const specific pointer to mutable anyopaque
    const error1 = comptime validateMethodSignature(
        fn (*anyopaque, *anyopaque) void,
        fn (*anyopaque, *const i32) void,
    );
    try std.testing.expectEqualDeep(MethodError{
        .pointerCast = .{
            .index = 1,
            .expected = "*anyopaque",
            .actual = "*const i32",
        },
    }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

test "wrong parameter count" {
    const error1 = comptime validateMethodSignature(
        fn (*anyopaque, i32, f32) void,
        fn (*anyopaque, i32) void,
    );
    try std.testing.expectEqualDeep(MethodError{ .wrongParameterCount = .{
        .expected = 3,
        .actual = 2,
    } }, error1);

    // comptime error1.?.raise(TestInterface, "method");
}

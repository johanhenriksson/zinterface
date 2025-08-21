const std = @import("std");
const Interface = @import("interface.zig").Interface;
const InterfaceError = @import("error.zig").InterfaceError;

pub fn validateDefinition(comptime InterfaceType: type) ?InterfaceError {
    return comptime block: {
        const typeInfo = @typeInfo(InterfaceType);
        if (typeInfo != .@"struct") {
            break :block .{ .invalidType = .{ .actual = @tagName(typeInfo) } };
        }

        if (!@hasField(InterfaceType, "ptr")) {
            break :block .{ .missingPtr = {} };
        }

        const ptrType = @TypeOf(@as(InterfaceType, undefined).ptr);
        const constPtr = ptrType == *const anyopaque;
        if (ptrType != *anyopaque and ptrType != *const anyopaque) {
            break :block .{ .invalidPtr = .{ .type = @typeName(ptrType) } };
        }

        if (!@hasField(InterfaceType, "vtable")) {
            break :block .{ .missingVtable = {} };
        }

        const VtableType = @TypeOf(@as(InterfaceType, undefined).vtable);
        const vtableInfo = @typeInfo(VtableType);
        if (vtableInfo != .@"struct") {
            break :block .{ .invalidVtable = .{ .actual = @tagName(vtableInfo) } };
        }

        const vtableFields = vtableInfo.@"struct".fields;
        if (vtableFields.len == 0) {
            break :block .{ .emptyVtable = {} };
        }
        for (vtableFields) |vfield| {
            var methodPtrInfo = @typeInfo(vfield.type);

            // optional methods are allowed - unpack one level
            if (methodPtrInfo == .optional) {
                methodPtrInfo = @typeInfo(methodPtrInfo.optional.child);
            }

            if (methodPtrInfo != .pointer) {
                break :block .{ .invalidMethod = .{ .method = vfield.name } };
            }
            const methodInfo = @typeInfo(methodPtrInfo.pointer.child);
            if (methodInfo != .@"fn") {
                break :block .{ .invalidMethod = .{ .method = vfield.name } };
            }

            // methods must have at least 1 parameter
            const methodFn = methodInfo.@"fn";
            if (methodFn.params.len == 0) {
                break :block .{ .invalidSignature = .{ .method = vfield.name } };
            }
            // the first parameter must be *anyopaque or *const anyopaque
            const firstParam = methodFn.params[0];
            if (firstParam.type != *anyopaque and firstParam.type != *const anyopaque) {
                break :block .{ .invalidSignature = .{ .method = vfield.name } };
            }
            // mutability must match the interface
            if (constPtr and firstParam.type == *anyopaque) {
                break :block .{ .mutableMethod = .{ .method = vfield.name } };
            }
        }

        break :block null;
    };
}

test "interface must be struct" {
    const result = validateDefinition(i32).?;
    try std.testing.expectEqualDeep(InterfaceError{ .invalidType = .{ .actual = "int" } }, result);

    // const impl = struct {}{};
    // _ = Interface(i32, &impl);
}

test "interface must have ptr" {
    const Iface = struct {};
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .missingPtr = {} }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "interface ptr must be anyopaque" {
    const Iface = struct { ptr: i32 };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .invalidPtr = .{ .type = "i32" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "interface must have vtable" {
    const Iface = struct { ptr: *anyopaque };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .missingVtable = {} }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "vtable must be struct" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: i32,
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .invalidVtable = .{ .actual = "int" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "vtable must not be empty" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: struct {},
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .emptyVtable = {} }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "vtable method must be function pointer" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: struct {
            method: *i32,
        },
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .invalidMethod = .{ .method = "method" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "optional vtable method" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: struct {
            method: ?*const fn (*anyopaque) void,
        },
    };
    const result = validateDefinition(Iface);
    try std.testing.expectEqualDeep(null, result);
}

test "interface vtable method must have at least one parameter" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: struct {
            method: *const fn () void,
        },
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .invalidSignature = .{ .method = "method" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "valid self pointer" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: struct {
            method: *const fn (i32) void,
        },
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .invalidSignature = .{ .method = "method" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "reject mutable pointer on const interface" {
    const Iface = struct {
        ptr: *const anyopaque,
        vtable: struct {
            method: *const fn (self: *anyopaque) void,
        },
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(InterfaceError{ .mutableMethod = .{ .method = "method" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

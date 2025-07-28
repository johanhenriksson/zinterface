const std = @import("std");
const Interface = @import("interface.zig").Interface;

pub const DefinitionError = union(enum) {
    invalidType: struct { actual: []const u8 },
    invalidPtr: struct { type: []const u8 },
    invalidVtable: struct { actual: []const u8 },
    missingPtr: void,
    missingVtable: void,
    emptyVtable: void,
    invalidMethod: struct { method: []const u8 },
    invalidSignature: struct { method: []const u8 },
    mutableMethod: struct { method: []const u8 },

    pub fn raise(err: DefinitionError, comptime T: type) void {
        const name = @typeName(T);
        switch (err) {
            .invalidType => |e| @compileError("Interface " ++ name ++ " must be a struct, got " ++ e.actual),
            .invalidPtr => |e| @compileError("Interface " ++ name ++ " must have a 'ptr' field of type *anyopaque, got " ++ e.type),
            .missingPtr => @compileError("Interface " ++ name ++ " must have a 'ptr' field"),
            .missingVtable => @compileError("Interface " ++ name ++ " must have a 'vtable' field"),
            .emptyVtable => @compileError("Interface " ++ name ++ " must have at least one method in the vtable"),
            .invalidVtable => |e| @compileError("Interface " ++ name ++ " vtable must be a struct, got " ++ e.actual),
            .invalidMethod => |e| @compileError("Interface " ++ name ++ " method '" ++ e.method ++ "' must be a function pointer"),
            .invalidSignature => |e| @compileError("Interface " ++ name ++ " method '" ++ e.method ++ "' must accept *anyopaque or *const anyopaque as the first argument"),
            .mutableMethod => |e| @compileError("Const Interface " ++ name ++ " method '" ++ e.method ++ "' cant have mutable self argument"),
        }
    }
};

pub fn validateDefinition(comptime InterfaceType: type) ?DefinitionError {
    return comptime block: {
        const typeInfo = @typeInfo(InterfaceType);
        if (typeInfo != .@"struct") {
            break :block .{ .invalidType = .{ .actual = @tagName(typeInfo) } };
        }

        var hasPtr = false;
        var constPtr = false;
        var hasVtable = false;
        var emptyVtable = true;

        for (typeInfo.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "ptr")) {
                hasPtr = true;
                constPtr = field.type == *const anyopaque;

                const ptrType = field.type;
                if (ptrType != *anyopaque and ptrType != *const anyopaque) {
                    break :block .{ .invalidPtr = .{ .type = @typeName(ptrType) } };
                }
            }
        }
        if (!hasPtr) {
            break :block .{ .missingPtr = {} };
        }

        for (typeInfo.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "vtable")) {
                hasVtable = true;

                const vtableType = field.type;
                const vtableInfo = @typeInfo(vtableType);
                if (vtableInfo != .@"struct") {
                    break :block .{ .invalidVtable = .{ .actual = @tagName(vtableInfo) } };
                }

                emptyVtable = vtableInfo.@"struct".fields.len == 0;

                for (vtableInfo.@"struct".fields) |vfield| {
                    // check that vtable fields are function pointers
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
            }
        }
        if (!hasVtable) {
            break :block .{ .missingVtable = {} };
        }
        if (emptyVtable) {
            break :block .{ .emptyVtable = {} };
        }

        break :block null;
    };
}

test "interface must be struct" {
    const result = validateDefinition(i32).?;
    try std.testing.expectEqualDeep(DefinitionError{ .invalidType = .{ .actual = "int" } }, result);

    // const impl = struct {}{};
    // _ = Interface(i32, &impl);
}

test "interface must have ptr" {
    const Iface = struct {};
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(DefinitionError{ .missingPtr = {} }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "interface ptr must be anyopaque" {
    const Iface = struct { ptr: i32 };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(DefinitionError{ .invalidPtr = .{ .type = "i32" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "interface must have vtable" {
    const Iface = struct { ptr: *anyopaque };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(DefinitionError{ .missingVtable = {} }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "vtable must be struct" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: i32,
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(DefinitionError{ .invalidVtable = .{ .actual = "int" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

test "vtable must not be empty" {
    const Iface = struct {
        ptr: *anyopaque,
        vtable: struct {},
    };
    const result = validateDefinition(Iface).?;
    try std.testing.expectEqualDeep(DefinitionError{ .emptyVtable = {} }, result);

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
    try std.testing.expectEqualDeep(DefinitionError{ .invalidMethod = .{ .method = "method" } }, result);

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
    try std.testing.expectEqualDeep(DefinitionError{ .invalidSignature = .{ .method = "method" } }, result);

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
    try std.testing.expectEqualDeep(DefinitionError{ .invalidSignature = .{ .method = "method" } }, result);

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
    try std.testing.expectEqualDeep(DefinitionError{ .mutableMethod = .{ .method = "method" } }, result);

    // const impl = struct {}{};
    // _ = Interface(Iface, &impl);
}

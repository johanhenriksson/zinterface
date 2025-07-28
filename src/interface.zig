const std = @import("std");

const validateDefinition = @import("definition.zig").validateDefinition;
const validateImplementation = @import("implementation.zig").validateImplementation;

pub fn Interface(comptime InterfaceType: type, ptr: anytype) InterfaceType {
    // implementation must be a pointer
    const ptrInfo = @typeInfo(@TypeOf(ptr));
    comptime if (ptrInfo != .pointer) {
        @compileError("Expected a pointer, got " ++ @typeName(@TypeOf(ptr)));
    };
    const ImplType = ptrInfo.pointer.child;

    // implementation must be a struct
    const implInfo = @typeInfo(ImplType);
    comptime if (implInfo != .@"struct") {
        @compileError("Interface implementation must be a struct, got " ++ @typeName(ImplType));
    };

    // validate the interface definition
    comptime if (validateDefinition(InterfaceType)) |err| {
        err.raise(InterfaceType);
    };

    // ensure that the passed pointer is compatible with the interface
    comptime if (!checkConstCompatibility(InterfaceType, ptrInfo)) {
        @compileError("Interface " ++ @typeName(InterfaceType) ++ " requires a mutable pointer, got " ++ @typeName(@TypeOf(ptr)));
    };

    // validate that the implementation matches the definition
    comptime if (validateImplementation(InterfaceType, ImplType)) |err| {
        err.raise(InterfaceType, ImplType);
    };

    return wrap(InterfaceType, ImplType, ptr);
}

fn wrap(comptime InterfaceType: type, comptime ImplType: type, ptr: anytype) InterfaceType {
    var result: InterfaceType = undefined;
    result.ptr = ptr;

    const vtableInfo = @typeInfo(@TypeOf(result.vtable));
    inline for (vtableInfo.@"struct".fields) |field| {
        const methodInfo = @typeInfo(field.type);
        if (!@hasDecl(ImplType, field.name) and methodInfo == .optional) {
            @field(result.vtable, field.name) = null;
            continue;
        }
        const methodFn = @field(ImplType, field.name);
        @field(result.vtable, field.name) = @ptrCast(&methodFn);
    }

    return result;
}

fn getInterfacePtr(comptime T: type) std.builtin.Type {
    const typeInfo = @typeInfo(T);
    for (typeInfo.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "ptr")) {
            return @typeInfo(field.type);
        }
    }
    unreachable;
}

pub fn checkConstCompatibility(comptime T: type, ptrInfo: std.builtin.Type) bool {
    const declPtrInfo = getInterfacePtr(T);
    if (declPtrInfo.pointer.is_const) {
        // interface takes a constant pointer, anything will do
        return true;
    }

    // if we reach here, the interface requires a mutable pointer
    if (ptrInfo.pointer.is_const) {
        return false;
    }

    // interface is compatible with the pointer type
    return true;
}

test "pointer compatibility" {
    const ConstInterface = struct { ptr: *const anyopaque };
    const MutableInterface = struct { ptr: *anyopaque };

    var mutValue: u32 = 123;
    const mutPtr = &mutValue;
    const mutPtrInfo = @typeInfo(@TypeOf(mutPtr));
    const constValue: u32 = 456;
    const constPtr = &constValue;
    const constPtrInfo = @typeInfo(@TypeOf(constPtr));

    try std.testing.expect(checkConstCompatibility(ConstInterface, mutPtrInfo));
    try std.testing.expect(checkConstCompatibility(ConstInterface, constPtrInfo));

    try std.testing.expect(checkConstCompatibility(MutableInterface, mutPtrInfo));
    try std.testing.expect(checkConstCompatibility(MutableInterface, constPtrInfo) == false);
}

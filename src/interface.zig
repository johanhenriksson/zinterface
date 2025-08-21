const std = @import("std");

const validateDefinition = @import("definition.zig").validateDefinition;
const validateImplementation = @import("implementation.zig").validateImplementation;
const InterfaceError = @import("error.zig").InterfaceError;

/// Wraps the pointer in an interface of the given InterfaceType.
/// ptr must be a pointer to a struct that implements the interface.
pub fn Interface(comptime InterfaceType: type, ptr: anytype) InterfaceType {
    // implementation must be a pointer to struct
    const ptrInfo = @typeInfo(@TypeOf(ptr));
    comptime if (ptrInfo != .pointer) {
        @compileError("Expected pointer to implementation, got " ++ @typeName(@TypeOf(ptr)));
    };
    const ImplType = ptrInfo.pointer.child;

    // ensure that the implementation satisfies the interface
    comptime Implements(InterfaceType, ImplType);

    // ensure that the passed pointer is compatible with the interface
    comptime if (!checkConstCompatibility(InterfaceType, ptrInfo)) {
        @compileError("Interface " ++ @typeName(InterfaceType) ++ " requires a mutable pointer, got " ++ @typeName(@TypeOf(ptr)));
    };

    return wrap(InterfaceType, ImplType, ptr);
}

/// Asserts that ImplType satisfies the InterfaceType definition.
pub fn Implements(comptime InterfaceType: type, comptime ImplType: type) void {
    // implementation must be a struct
    const implInfo = @typeInfo(ImplType);
    if (implInfo != .@"struct") {
        @compileError("Interface implementation must be a struct, got " ++ @typeName(ImplType));
    }

    // validate the interface definition
    if (validateDefinition(InterfaceType)) |err| {
        err.raiseDefinition(InterfaceType);
    }

    // validate that the implementation matches the definition
    if (validateImplementation(InterfaceType, ImplType)) |err| {
        err.raiseImplementation(InterfaceType, ImplType);
    }
}

fn wrap(comptime InterfaceType: type, comptime ImplType: type, ptr: anytype) InterfaceType {
    var result: InterfaceType = undefined;
    result.ptr = ptr;

    const VtableType = @TypeOf(@as(InterfaceType, undefined).vtable);
    const vtableInfo = @typeInfo(VtableType);
    const vtableFields = vtableInfo.@"struct".fields;

    inline for (vtableFields) |field| {
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

pub fn checkConstCompatibility(comptime T: type, ptrInfo: std.builtin.Type) bool {
    const PtrType = @TypeOf(@as(T, undefined).ptr);
    const declPtrInfo = @typeInfo(PtrType);

    if (declPtrInfo.pointer.is_const) {
        // interface takes a constant pointer, anything will do
        return true;
    } else {
        // the interface requires a mutable pointer
        if (ptrInfo.pointer.is_const) {
            return false;
        } else {
            // interface is compatible with the pointer type
            return true;
        }
    }
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

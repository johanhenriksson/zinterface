const std = @import("std");

pub const InterfaceError = union(enum) {
    // Definition errors
    invalidType: struct { actual: []const u8 },
    invalidPtr: struct { type: []const u8 },
    invalidVtable: struct { actual: []const u8 },
    missingPtr: void,
    missingVtable: void,
    emptyVtable: void,
    invalidMethod: struct { method: []const u8 },
    invalidSignature: struct { method: []const u8 },
    mutableMethod: struct { method: []const u8 },
    
    // Implementation errors
    missingMethod: struct { method: []const u8 },
    wrongParameterCount: struct { method: []const u8, expected: usize, actual: usize },
    wrongReturnType: struct { method: []const u8, expected: []const u8, actual: []const u8 },
    wrongParameterType: struct { method: []const u8, index: usize, expected: []const u8, actual: []const u8 },
    invalidPointerCast: struct { method: []const u8, index: usize, expected: []const u8, actual: []const u8 },

    pub fn raiseDefinition(err: InterfaceError, comptime T: type) void {
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
            else => unreachable,
        }
    }

    pub fn raiseImplementation(self: InterfaceError, comptime InterfaceType: type, comptime ImplType: type) void {
        const msg = std.fmt.comptimePrint("{s} implementation {s}", .{
            @typeName(InterfaceType),
            @typeName(ImplType),
        });
        switch (self) {
            .missingMethod => @compileError(msg ++ " is missing method '" ++ self.missingMethod.method ++ "'"),
            .invalidMethod => @compileError(msg ++ " expected '" ++ self.invalidMethod.method ++ "' to be a method"),
            .wrongParameterCount => |err| @compileError(std.fmt.comptimePrint(
                "{s} method {s} has wrong parameter count: expected {d}, got {d}",
                .{ msg, err.method, err.expected, err.actual },
            )),
            .wrongReturnType => |err| @compileError(std.fmt.comptimePrint(
                "{s} method {s} has wrong return type: expected {s}, got {s}",
                .{ msg, err.method, err.expected, err.actual },
            )),
            .wrongParameterType => |err| @compileError(std.fmt.comptimePrint(
                "{s} method {s} parameter {d} has wrong type: expected {s}, got {s}",
                .{ msg, err.method, err.index, err.expected, err.actual },
            )),
            .invalidPointerCast => |err| @compileError(std.fmt.comptimePrint(
                "{s} method {s} parameter {d} cant be cast from {s} to mutable {s}",
                .{ msg, err.method, err.index, err.expected, err.actual },
            )),
            else => unreachable,
        }
    }
};
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("zinterface", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zinterface",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    //
    // unit tests
    //

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    //
    // examples
    //

    const examples_mod = b.createModule(.{
        .root_source_file = b.path("examples/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    examples_mod.addImport("zinterface", lib_mod);
    const exe_examples = b.addExecutable(.{
        .name = "examples",
        .root_module = examples_mod,
    });
    const run_examples = b.addRunArtifact(exe_examples);
    const examples_step = b.step("examples", "Run examples");
    examples_step.dependOn(&run_examples.step);
}

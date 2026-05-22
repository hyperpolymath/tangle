// TANGLE FFI Build Configuration
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "tangle",
        .root_module = root_module,
        .linkage = .dynamic,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    b.installArtifact(lib);

    const lib_static = b.addLibrary(.{
        .name = "tangle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .static,
    });
    b.installArtifact(lib_static);

    const unit_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit_tests = b.addTest(.{ .root_module = unit_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const integration_mod = b.createModule(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    integration_mod.addImport("tangle", root_module);

    const integration_tests = b.addTest(.{ .root_module = integration_mod });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const unit_step = b.step("test", "Run Zig unit tests");
    unit_step.dependOn(&run_unit_tests.step);

    const integration_step = b.step("test-integration", "Run Zig integration tests");
    integration_step.dependOn(&run_integration_tests.step);

    const all_step = b.step("test-all", "Run all Zig tests");
    all_step.dependOn(&run_unit_tests.step);
    all_step.dependOn(&run_integration_tests.step);
}

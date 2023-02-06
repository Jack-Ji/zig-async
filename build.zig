const std = @import("std");

pub fn build(b: *std.Build) void {
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
    });
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

pub fn getPkg(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .source_file = .{
            .path = comptime thisDir() ++ "/src/main.zig",
        },
    });
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

//! Tests the options as a package depending on zig-patch would use them.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run the tests");

    // a patched directory, dir/main.zig exits 1 until patched
    test_step.dependOn(&b.addRunArtifact(b.addExecutable(.{
        .name = "patched-dir",
        .root_module = b.createModule(.{
            .root_source_file = b.dependency("patch", .{
                .source = b.path("dir"),
                .patches = &[_]std.Build.LazyPath{b.path("dir.patch")},
            }).namedLazyPath("patched").path(b, "main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .win32_manifest = b.dependency("patch", .{}).path("src/asinvoker.manifest"),
    })).step);

    // every module sees the patched std and patches stack
    const subsub = b.createModule(.{ .root_source_file = b.path("subsub.zig") });
    const sub = b.createModule(.{
        .root_source_file = b.path("sub.zig"),
        .imports = &.{.{ .name = "subsub", .module = subsub }},
    });
    const stacked: []const std.Build.LazyPath = &.{ b.path("std-decl.patch"), b.path("std-stack.patch") };
    // a second instance with other patches gets its own std
    const single: []const std.Build.LazyPath = &.{b.path("std-decl.patch")};
    for ([_]struct { []const u8, []const std.Build.LazyPath }{
        .{ "std-stacked", stacked },
        .{ "std-single", single },
    }) |case| {
        const options = b.addOptions();
        options.addOption(bool, "stacked", case[1].len == 2);
        test_step.dependOn(&b.addRunArtifact(b.addExecutable(.{
            .name = case[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path("std.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "std", .module = b.dependency("patch", .{ .std_patches = case[1] }).module("std") },
                    .{ .name = "sub", .module = sub },
                    .{ .name = "options", .module = options.createModule() },
                },
            }),
        })).step);
    }

    // misuses fail with a clear error, see misuse/build.zig
    for ([_]struct { []const u8, []const u8 }{
        .{ "std_without_std_patches", "module(\"std\") needs the std_patches option" },
        .{ "patched_without_options", "namedLazyPath(\"patched\") needs the source and patches options" },
        .{ "source_without_patches", "the source option needs the patches option" },
        .{ "patches_without_source", "the patches option needs the source option" },
        .{ "empty_patches", "the patches option is empty" },
        .{ "empty_std_patches", "the std_patches option is empty" },
        // errors name the patch line
        .{ "bad_patch", "bad.patch:6: patching 'x.txt' failed with HunkNotFound" },
    }) |case| {
        const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", b.fmt("-Dcase={s}", .{case[0]}) });
        run.setName(b.fmt("misuse {s}", .{case[0]}));
        run.setCwd(b.path("misuse"));
        // its inputs, zig-patch included, aren't args this step can hash
        run.has_side_effects = true;
        run.expectExitCode(1);
        run.expectStdErrMatch(case[1]);
        test_step.dependOn(&run.step);
    }
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    // a build tool, it runs on the host
    const module = b.createModule(.{
        .root_source_file = b.path("src/patch.zig"),
        .target = b.graph.host,
        .optimize = b.standardOptimizeOption(.{}),
    });
    const exe = b.addExecutable(.{
        .name = "patch",
        .root_module = module,
        .win32_manifest = b.path("src/asinvoker.manifest"),
    });
    b.installArtifact(exe);

    {
        const std_dir = if (b.option(
            []const std.Build.LazyPath,
            "std_patches",
            "Patches applied to std, in order, for module(\"std\")",
        )) |std_patches|
            patchDir(b, exe, zigStdDir(b), "std_patches", std_patches)
        else
            failingDir(b, "patch: module(\"std\") needs the std_patches option");
        _ = b.addModule("std", .{ .root_source_file = std_dir.path(b, "std.zig") });
    }

    {
        const source = b.option(std.Build.LazyPath, "source", "Directory to patch for namedLazyPath(\"patched\"), needs patches");
        const patches = b.option([]const std.Build.LazyPath, "patches", "Patches applied to source, in order");
        b.addNamedLazyPath("patched", if (source != null or patches != null) patchDir(
            b,
            exe,
            source orelse std.process.fatal("patch: the patches option needs the source option", .{}),
            "patches",
            patches orelse std.process.fatal("patch: the source option needs the patches option", .{}),
        ) else failingDir(b, "patch: namedLazyPath(\"patched\") needs the source and patches options"));
    }

    {
        const test_step = b.step("test", "Run the tests");
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module })).step);
    }
}

fn patchDir(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    source: std.Build.LazyPath,
    option: []const u8,
    patches: []const std.Build.LazyPath,
) std.Build.LazyPath {
    if (patches.len == 0) std.process.fatal("patch: the {s} option is empty", .{option});
    const run = b.addRunArtifact(exe);
    run.addDirectoryArg(source);
    const dir = run.addOutputDirectoryArg("patched");
    // the build system only hashes a directory arg's path, this tracks its files
    _ = run.addDepFileOutputArg("deps.d");
    for (patches) |p| run.addFileArg(p);
    return dir;
}

/// A directory that fails the build with `msg` if anything uses it, so an
/// output without its options gives a clear error.
fn failingDir(b: *std.Build, msg: []const u8) std.Build.LazyPath {
    const write = b.addWriteFiles();
    write.step.dependOn(&b.addFail(msg).step);
    return write.getDirectory();
}

/// The zig lib's std directory, `b.graph.path(.zig_lib, "std")` from zig 0.17.
fn zigStdDir(b: *std.Build) std.Build.LazyPath {
    if (zig_16) return .{ .cwd_relative = b.graph.zig_lib_directory.join(b.allocator, &.{"std"}) catch @panic("OOM") };
    return b.graph.path(.zig_lib, "std");
}

const zig_16 = @import("builtin").zig_version.order(.{ .major = 0, .minor = 17, .patch = 0 }) == .lt;

const std = @import("std");

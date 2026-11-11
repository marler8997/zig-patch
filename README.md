# zig-patch

Apply patch files from the zig build system, including to std.

Supports Zig 0.16.0 and 0.17.0.

## Patching a directory

```zig
const patched_dir = b.dependency("patch", .{
    .source = some_dep.path("src"),
    .patches = &[_]std.Build.LazyPath{
        b.path("fix.patch"),
    },
}).namedLazyPath("patched");
```

## Patching std

```zig
const patched_std = b.dependency("patch", .{
    .std_patches = &[_]std.Build.LazyPath{
        b.path("my-std.patch"),
    },
}).module("std");

// in a root module's .imports (or root_module.addImport):
.imports = &.{.{ .name = "std", .module = patched_std }},
```

> Note that replacing std in the root module automatically replaces it for every module in the compilation.

### Stale builds after changing a std patch

In zig 0.16 and 0.17 the compiler leaves the std module out of its cache key, even when it's been replaced. After a std patch changes, the patch is applied again but the compile step that uses it is "cached" and you get the previous build. This is fixed in zig 0.18.

Until then, either delete `.zig-cache` after changing a std patch (or updating a dependency that provides one), or give the root module a second import of the patched std. Nothing needs to import it, it just puts the patched path in the cache key:

```zig
.imports = &.{
    .{ .name = "std", .module = patched_std },
    .{ .name = "std_cache_key", .module = b.createModule(.{
        .root_source_file = patched_std.root_source_file,
    }) },
},
```

## Making a patch

Patches use git's format:

```sh
cp -r path/to/dir my-dir   # for std: std_dir from `zig env`
cd my-dir && git init && git add -A && git commit -m original
# edit, then:
git add -A && git diff --cached -M -C > ../my.patch
```

`git diff --no-index` doesn't work, its paths include the directory names.

Unlike `git apply`, line numbers are ignored: each hunk's old lines must match exactly once. Deletions, mode changes and binary patches aren't supported.

## CLI

```
patch SRC_DIR OUT_DIR DEP_FILE PATCH...
```

Replaces OUT_DIR with SRC_DIR patched. DEP_FILE lists the copied files for zig's cache, which only hashes a directory argument's path; files added to SRC_DIR later aren't tracked.

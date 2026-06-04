// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// TANGLE Integration Tests

const std = @import("std");
const testing = std.testing;
const tangle = @import("tangle");

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(handle);

    try testing.expect(tangle.tangle_is_initialized(handle) == 1);
}

test "handle is initialized" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(handle);

    const initialized = tangle.tangle_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = tangle.tangle_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Operation Tests
//==============================================================================

test "process with valid handle" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(handle);

    const result = tangle.tangle_process(handle, 42);
    try testing.expectEqual(tangle.Result.ok, result);
}

test "process with null handle returns error" {
    const result = tangle.tangle_process(null, 42);
    try testing.expectEqual(tangle.Result.null_pointer, result);
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(handle);

    const str = tangle.tangle_get_string(handle);
    defer if (str) |s| tangle.tangle_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = tangle.tangle_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = tangle.tangle_process(null, 0);

    const err = tangle.tangle_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(handle);

    _ = tangle.tangle_process(handle, 0);

    try testing.expect(tangle.tangle_last_error() == null);
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = tangle.tangle_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = tangle.tangle_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(h1);

    const h2 = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = tangle.tangle_process(h1, 1);
    _ = tangle.tangle_process(h2, 2);
}

test "double free is safe" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;

    tangle.tangle_free(handle);
    tangle.tangle_free(handle); // Should not crash
}

test "free null is safe" {
    tangle.tangle_free(null); // Should not crash
}

//==============================================================================
// Thread Safety Tests
//==============================================================================

test "concurrent operations" {
    const handle = tangle.tangle_init() orelse return error.InitFailed;
    defer tangle.tangle_free(handle);

    const ThreadContext = struct {
        h: *tangle.Handle,
        id: u32,
    };

    const thread_fn = struct {
        fn run(ctx: ThreadContext) void {
            _ = tangle.tangle_process(ctx.h, ctx.id);
        }
    }.run;

    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, thread_fn, .{
            ThreadContext{ .h = handle, .id = @intCast(i) },
        });
    }

    for (threads) |thread| {
        thread.join();
    }
}

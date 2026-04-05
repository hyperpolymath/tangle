// TANGLE FFI Implementation
// SPDX-License-Identifier: PMPL-1.0-or-later

const std = @import("std");
const builtin = @import("builtin");

const VERSION: [:0]const u8 = "0.1.0";
const BUILD_INFO: [:0]const u8 = "TANGLE built with Zig " ++ builtin.zig_version_string;

threadlocal var last_error: ?[:0]const u8 = null;

fn setError(msg: [:0]const u8) void {
    last_error = msg;
}

fn clearError() void {
    last_error = null;
}

pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
};

pub const Callback = *const fn (u64, u32) callconv(.c) u32;

const HandleData = struct {
    initialized: bool,
    callback: ?Callback,
};

pub const Handle = opaque {};

var handles_mutex: std.Thread.Mutex = .{};
var active_handles: std.AutoHashMapUnmanaged(usize, void) = .{};

fn toHandle(data: *HandleData) *Handle {
    return @as(*Handle, @ptrCast(data));
}

fn toData(handle: *Handle) *HandleData {
    return @as(*HandleData, @ptrCast(@alignCast(handle)));
}

fn addHandle(data: *HandleData) !void {
    handles_mutex.lock();
    defer handles_mutex.unlock();
    try active_handles.put(std.heap.page_allocator, @intFromPtr(data), {});
}

fn removeHandle(handle: *Handle) bool {
    handles_mutex.lock();
    defer handles_mutex.unlock();
    return active_handles.remove(@intFromPtr(handle));
}

fn isLiveHandle(handle: *Handle) bool {
    handles_mutex.lock();
    defer handles_mutex.unlock();
    return active_handles.contains(@intFromPtr(handle));
}

pub export fn tangle_init() ?*Handle {
    const allocator = std.heap.page_allocator;

    const data = allocator.create(HandleData) catch {
        setError("Failed to allocate handle");
        return null;
    };

    data.* = .{
        .initialized = true,
        .callback = null,
    };

    addHandle(data) catch {
        allocator.destroy(data);
        setError("Failed to register handle");
        return null;
    };

    clearError();
    return toHandle(data);
}

pub export fn tangle_free(handle: ?*Handle) void {
    const h = handle orelse return;

    if (!removeHandle(h)) {
        // Unknown/stale handle: treat as no-op for FFI robustness.
        return;
    }

    const data = toData(h);
    data.initialized = false;
    data.callback = null;

    std.heap.page_allocator.destroy(data);
    clearError();
}

pub export fn tangle_process(handle: ?*Handle, input: u32) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!isLiveHandle(h)) {
        setError("Handle not initialized");
        return .@"error";
    }

    const data = toData(h);
    if (!data.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    _ = input;

    clearError();
    return .ok;
}

pub export fn tangle_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!isLiveHandle(h)) {
        setError("Handle not initialized");
        return null;
    }

    const data = toData(h);
    if (!data.initialized) {
        setError("Handle not initialized");
        return null;
    }

    clearError();
    return "Example result";
}

pub export fn tangle_free_string(str: ?[*:0]const u8) void {
    _ = str;
    // Returned strings are static right now.
}

pub export fn tangle_process_array(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!isLiveHandle(h)) {
        setError("Handle not initialized");
        return .@"error";
    }

    const buf = buffer orelse {
        setError("Null buffer");
        return .null_pointer;
    };

    _ = buf[0..len];

    clearError();
    return .ok;
}

pub export fn tangle_last_error() ?[*:0]const u8 {
    return if (last_error) |err| err else null;
}

pub export fn tangle_version() [*:0]const u8 {
    return VERSION;
}

pub export fn tangle_build_info() [*:0]const u8 {
    return BUILD_INFO;
}

pub export fn tangle_register_callback(handle: ?*Handle, callback: ?Callback) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const cb = callback orelse {
        setError("Null callback");
        return .null_pointer;
    };

    if (!isLiveHandle(h)) {
        setError("Handle not initialized");
        return .@"error";
    }

    const data = toData(h);
    if (!data.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    data.callback = cb;
    clearError();
    return .ok;
}

pub export fn tangle_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    if (!isLiveHandle(h)) return 0;

    const data = toData(h);
    return if (data.initialized) 1 else 0;
}

test "lifecycle" {
    const handle = tangle_init() orelse return error.InitFailed;
    defer tangle_free(handle);

    try std.testing.expect(tangle_is_initialized(handle) == 1);
}

test "error handling" {
    const result = tangle_process(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = tangle_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = tangle_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

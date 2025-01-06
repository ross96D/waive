const std = @import("std");
const secrets = @import("secrets");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");

var allocator_instance = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = allocator_instance.allocator();

const NULL = @as(*allowzero void, @ptrFromInt(0));

pub const schema: secrets.Schema = blk: {
    var ret = std.mem.zeroes(secrets.Schema);
    ret.f_name = "waive.ross96D.schema";
    ret.f_attributes[0] = .{
        .f_name = "name",
        .f_type = secrets.SchemaAttributeType.string,
    };
    break :blk ret;
};

pub const timespec = extern struct {
    sec: isize = 0,
    nsec: isize = 0,
};

fn time_cancel(time: timespec) *gio.Cancellable {
    const ret: *gio.Cancellable = gio.Cancellable.new();
    ret.ref();

    const fd = std.posix.timerfd_create(std.posix.CLOCK.MONOTONIC, .{ .NONBLOCK = true }) catch unreachable;
    std.posix.timerfd_settime(fd, .{}, @ptrCast(&time), null) catch unreachable;

    const callback = struct {
        fn func(p_fd: c_int, _: glib.IOCondition, user_data: ?*anyopaque) callconv(.C) c_int {
            std.posix.close(@intCast(p_fd));

            const cancellable: *gio.Cancellable = @ptrCast(@alignCast(user_data));
            gio.Cancellable.cancel(cancellable);
            cancellable.unref();

            return 0;
        }
    }.func;

    _ = glib.unixFdAdd(@intCast(fd), .{ .in = true }, &callback, ret);

    return ret;
}

const name: [*:0]const u8 = "waive.ross96D.schema";
const label: [*:0]const u8 = "waive.ross96D.schema";

fn Callback(P_T: type) type {
    return struct {
        const Self = @This();

        pub const Fn = *const fn (p_res: P_T, p_error: ?*glib.Error, p_data: ?*anyopaque) void;
        pub const Data = struct {
            callback: ?Self.Fn,
            data: ?*anyopaque,
        };
    };
}

const T_get_passphrase = Callback(?[*:0]u8);

fn cb_get_passphrase(_: ?*gobject.Object, p_res: *gio.AsyncResult, p_data: ?*anyopaque) callconv(.C) void {
    const callback_data: *T_get_passphrase.Data = @ptrCast(@alignCast(p_data));
    defer allocator.destroy(callback_data);

    var p_error: ?*glib.Error = null;
    defer if (p_error) |err| glib.Error.free(err);

    const response = secrets.passwordLookupFinish(p_res, &p_error);
    if (callback_data.callback) |cb| {
        cb(response, p_error, callback_data.data);
    }
}

pub fn get_passphrase(callback: ?T_get_passphrase.Fn, data: ?*anyopaque) void {
    const callback_data = allocator.create(T_get_passphrase.Data) catch unreachable;
    callback_data.* = .{ .callback = callback, .data = data };
    secrets.passwordLookup(&schema, time_cancel(.{ .sec = 1 }), &cb_get_passphrase, callback_data, "name", name, NULL);
}

const T_put_passphrase = Callback(bool);

fn cb_put_passphrase(_: ?*gobject.Object, p_res: *gio.AsyncResult, p_data: ?*anyopaque) callconv(.C) void {
    const callback_data: *T_put_passphrase.Data = @ptrCast(@alignCast(p_data));
    defer allocator.destroy(callback_data);

    var p_error: ?*glib.Error = null;
    defer if (p_error) |err| glib.Error.free(err);

    const response = secrets.passwordStoreFinish(p_res, &p_error) != 0;
    if (callback_data.callback) |cb| {
        cb(response, p_error, callback_data.data);
    }
}

pub fn put_passphrase(phrase: [*:0]const u8, callback: ?T_put_passphrase.Fn, data: ?*anyopaque) void {
    const callback_data = allocator.create(T_put_passphrase.Data) catch unreachable;
    callback_data.* = .{ .callback = callback, .data = data };
    secrets.passwordStore(
        &schema,
        secrets.COLLECTION_SESSION,
        label,
        phrase,
        time_cancel(.{ .sec = 1 }),
        &cb_put_passphrase,
        callback_data,
        @as([*:0]const u8, "name"),
        name,
        NULL,
    );
}

const T_delete_passphrase = Callback(bool);

fn cb_delete_passphrase(_: ?*gobject.Object, p_res: *gio.AsyncResult, p_data: ?*anyopaque) callconv(.C) void {
    const callback_data: *T_delete_passphrase.Data = @ptrCast(@alignCast(p_data));
    defer allocator.destroy(callback_data);

    var p_error: ?*glib.Error = null;
    defer if (p_error) |err| glib.Error.free(err);

    const response = secrets.passwordClearFinish(p_res, &p_error) != 0;
    if (callback_data.callback) |cb| {
        cb(response, p_error, callback_data.data);
    }
}

pub fn delete_passphrase(callback: ?T_delete_passphrase.Fn, user_data: ?*anyopaque) void {
    const callback_data = allocator.create(T_delete_passphrase.Data) catch unreachable;
    callback_data.* = .{ .callback = callback, .data = user_data };
    secrets.passwordClear(&schema, time_cancel(.{ .sec = 1 }), &cb_delete_passphrase, callback_data, "name", name, NULL);
}

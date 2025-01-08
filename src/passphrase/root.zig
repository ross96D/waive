const std = @import("std");
const glib = @import("glib");
const gtk = @import("gtk");
pub const dbus = @import("./dbus_secret_service.zig");
pub const dialog = @import("dialog.zig");
const Rc = @import("../utils.zig").Rc;

pub const schema = dbus.schema;

pub const GetPassphraseData = struct {
    window: *gtk.Window,
    cb: ?*const fn (p_res: ?[*:0]u8, p_error: ?*glib.Error, p_data: ?*anyopaque) void,
    data: ?*anyopaque,
};

fn get_passphrase_dialog_cb(data: ?*anyopaque) void {
    const p_cb_data: *Rc(GetPassphraseData) = @ptrCast(@alignCast(data));
    get_passphrase(p_cb_data);
}

fn retry_get_passphrase(p_res: ?[*:0]u8, p_error: ?*glib.Error, p_data: ?*anyopaque) void {
    const rc: *Rc(GetPassphraseData) = @ptrCast(@alignCast(p_data));
    const p_cb_data: GetPassphraseData = rc.value;
    if (p_res != null or p_error != null) {
        if (p_cb_data.cb) |cb_| {
            cb_(p_res, p_error, p_cb_data.data);
            rc.unref();
        }
    } else {
        dialog.Dialog.pop(p_cb_data.window, get_passphrase_dialog_cb, rc);
    }
}

pub fn get_passphrase(params: *Rc(GetPassphraseData)) void {
    dbus.get_passphrase(retry_get_passphrase, params);
}

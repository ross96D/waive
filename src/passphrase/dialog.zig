const std = @import("std");
const gtk = @import("gtk");
const glib = @import("glib");
const dbus_secret = @import("./dbus_secret_service.zig");
const utils = @import("../utils.zig");

fn set_layer(window: *gtk.Window) void {
    const l = @cImport(@cInclude("gtk4-layer-shell.h"));
    // Before the window is first realized, set it up to be a layer surface
    const w: [*c]l.GtkWindow = @ptrCast(window);

    l.gtk_layer_init_for_window(w);

    // Order below normal windows
    l.gtk_layer_set_layer(w, l.GTK_LAYER_SHELL_LAYER_OVERLAY);

    l.gtk_layer_set_keyboard_mode(w, l.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
}

var self: ?Dialog = null;

pub const Callback = extern struct {
    pub const Fn = ?*const fn (?*anyopaque) void;
    pub const Data = ?*anyopaque;
    cb: Fn,
    data: Data,
};

pub const Dialog = extern struct {
    dialog: *gtk.Dialog,
    callback: Callback,

    // TODO: try using a wayland pop up instead of a layer shell
    pub fn pop(parent: *gtk.Window, callback: Callback.Fn, data: ?*anyopaque) void {
        std.debug.assert(self == null);

        const flags = gtk.DialogFlags{ .destroy_with_parent = true, .modal = true };
        const dialog = gtk.MessageDialog.new(parent, flags, .info, .none, "insert passphrase");

        self = Dialog{
            .dialog = dialog.as(gtk.Dialog),
            .callback = Callback{
                .cb = callback,
                .data = data,
            },
        };

        _ = gtk.Dialog.signals.response.connect(dialog.as(gtk.Dialog), ?*anyopaque, cb_response, null, .{});

        const content_box = gtk.Box.new(.horizontal, 5);
        { // ---- FRAME ----
            const frame = gtk.Frame.new("Insert the passphrase");
            frame.setLabelAlign(0.5);
            gtk.Window.setChild(dialog.as(gtk.Window), frame.as(gtk.Widget));
            utils.set_widget_margin_all(content_box.as(gtk.Widget), 5);
            frame.setChild(content_box.as(gtk.Widget));
        }

        // ---- ENTRY ----
        const entry = gtk.Entry.new();
        gtk.Entry.setIconFromIconName(entry, .secondary, "dialog-information");
        gtk.Entry.setIconActivatable(entry, .secondary, 1); // TODO how to use the activable function?
        gtk.Entry.setIconTooltipText(entry, .secondary, "set an easy to remember text to encrypt the passwords with");
        _ = gtk.Entry.signals.activate.connect(entry, ?*anyopaque, &cb_entry_activate, null, .{});
        content_box.append(entry.as(gtk.Widget));
        // ----- END -----

        set_layer(dialog.as(gtk.Window));

        gtk.Window.present(dialog.as(gtk.Window));
    }

    fn cb_entry_activate(entry: *gtk.Entry, _: ?*anyopaque) callconv(.C) void {
        const buffer = entry.getBuffer();
        const text = buffer.getText();
        if (buffer.getLength() == 0) {
            std.log.info("TODO add visual notification that the field needs to be filled", .{});
            return;
        }
        dbus_secret.put_passphrase(text, &cb_put_passphrase, null);
    }

    fn cb_put_passphrase(_: bool, p_error: ?*glib.Error, _: ?*anyopaque) void {
        std.debug.assert(self != null);
        if (p_error) |err| {
            std.log.err("put_passphrase {}", .{err});
            std.log.info("TODO add visual notification of the error", .{});
            return;
        }
        gtk.Window.close(self.?.dialog.as(gtk.Window));
    }

    fn cb_response(_: *gtk.Dialog, p_response_id: c_int, _: ?*anyopaque) callconv(.C) void {
        switch (p_response_id) {
            @intFromEnum(gtk.ResponseType.delete_event) => {
                std.log.debug("delete_event response", .{});
                const cb = self.?.callback;
                self = null;
                if (cb.cb) |call| {
                    call(cb.data);
                }
            },
            else => std.log.err("unknown response_id {d}", .{p_response_id}),
        }
    }
};

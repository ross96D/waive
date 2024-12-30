const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const glib = @import("glib");
const gdk = @import("gdk");

fn set_layer(window: *gtk.Window) void {
    const l = @cImport(@cInclude("gtk4-layer-shell.h"));
    // Before the window is first realized, set it up to be a layer surface
    const w: [*c]l.GtkWindow = @ptrCast(window);
    l.gtk_layer_init_for_window(w);

    // Order below normal windows
    l.gtk_layer_set_layer(w, l.GTK_LAYER_SHELL_LAYER_OVERLAY);

    l.gtk_layer_set_keyboard_mode(w, l.GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
}

pub fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const window = gtk.ApplicationWindow.new(app);
    const w = window.as(gtk.Window);
    w.setTitle("hello world");
    w.setDefaultSize(500, 300);

    const action = gio.SimpleAction.new("quit", null);
    defer action.unref();
    _ = gio.SimpleAction.signals.activate.connect(action, *gtk.Application, &gtk_quit, app, .{});
    gio.ActionMap.addAction(app.as(gio.ActionMap), action.as(gio.Action));

    const accel = gdk.keyvalName(gdk.KEY_Escape);
    const accels = [1:0][*c]const u8{accel};
    gtk.Application.setAccelsForAction(app, "app.quit", @ptrCast(&accels));

    set_layer(w);

    const box = gtk.Box.new(gtk.Orientation.vertical, 1);
    gtk.Widget.setHalign(box.as(gtk.Widget), gtk.Align.center);
    gtk.Widget.setValign(box.as(gtk.Widget), gtk.Align.start);
    gtk.Widget.setSizeRequest(box.as(gtk.Widget), 500, 0);

    const entry = gtk.Entry.new();
    gtk.Entry.setPlaceholderText(entry, "search for link or password");
    gtk.Widget.setHexpand(entry.as(gtk.Widget), 1);
    gtk.Box.append(box, entry.as(gtk.Widget));

    const list = gtk.ListBox.new();
    for (0..5) |_| {
        const label = gtk.Label.new("example text");
        label.setXalign(0);
        list.append(label.as(gtk.Widget));
    }
    gtk.Box.append(box, list.as(gtk.Widget));

    const button = gtk.Button.newWithLabel("Hellow");
    gtk.Box.append(box, button.as(gtk.Widget));

    gtk.Window.setChild(w, box.as(gtk.Widget));
    gtk.Window.present(w);
}

pub fn main() !void {
    const app = gtk.Application.new("org.gtk.example", gio.ApplicationFlags{
        // .is_launcher = true,
        // .handles_open = false,
    });

    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn gtk_quit(_: *gio.SimpleAction, _: ?*glib.Variant, app: *gtk.Application) callconv(.C) void {
    const list = app.getWindows();
    glib.List.foreach(list, &close_window, null);
}

fn close_window(window: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
    const w: *gtk.Window = @ptrCast(@alignCast(window));
    w.destroy();
}

const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const glib = @import("glib");
const gdk = @import("gdk");
const gobject = @import("gobject");

const data = &[_][*:0]const u8{
    "comida",  "sentido", "comida",  "sentido", "comida",  "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
};

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

    const main_box = gtk.Box.new(gtk.Orientation.vertical, 5);
    gtk.Widget.setName(main_box.as(gtk.Widget), "outer-box");
    gtk.Box.setSpacing(main_box, 3);
    gtk.Window.setChild(w, main_box.as(gtk.Widget));

    gtk.Widget.setSizeRequest(main_box.as(gtk.Widget), 500, 0);

    const entry = gtk.Entry.new();
    gtk.Entry.setPlaceholderText(entry, "search for link or password");
    gtk.Widget.setHexpand(entry.as(gtk.Widget), 1);
    gtk.Box.append(main_box, entry.as(gtk.Widget));

    const model_gio = gtk.StringList.new(@ptrCast(data));
    const model = gtk.SingleSelection.new(model_gio.as(gio.ListModel));
    const list = @import("list.zig").list(model.as(gtk.SelectionModel));

    const scrolled = gtk.ScrolledWindow.new();
    gtk.Widget.setVexpand(scrolled.as(gtk.Widget), 1);
    gtk.ScrolledWindow.setChild(scrolled, list.as(gtk.Widget));

    gtk.Box.append(main_box, scrolled.as(gtk.Widget));

    const button = gtk.Button.newWithLabel("Hellow");
    gtk.Box.append(main_box, button.as(gtk.Widget));

    gtk.Window.present(w);
}

fn setup_list() *gtk.ListView {
    const setup_cb = struct {
        fn f(_: *gtk.SignalListItemFactory, item_: *gobject.Object, _: ?*anyopaque) callconv(.C) void {
            const item: *gtk.ListItem = @ptrCast(item_);
            const label = gtk.Label.new("entry");
            item.setChild(label.as(gtk.Widget));
        }
    }.f;

    const factory = gtk.SignalListItemFactory.new();
    _ = gtk.SignalListItemFactory.signals.setup.connect(factory, ?*anyopaque, setup_cb, null, .{});

    return gtk.ListView.new(null, factory.as(gtk.ListItemFactory));
}

pub fn main() !void {
    const app = gtk.Application.new("org.gtk.example", gio.ApplicationFlags{});

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

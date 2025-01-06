const std = @import("std");
const views = @import("views.zig");
const utils = @import("utils.zig");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gio = @import("gio");

pub fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    views.init_application(app);
    // const window = views.SearchPassword.get();
    const window = views.AddPassword.get();

    std.log.debug("Window.present(SearchPassword)", .{});
    gtk.Window.present(window);
}

pub fn main() !void {
    const app = gtk.Application.new("org.gtk.example", gio.ApplicationFlags{});

    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

const std = @import("std");
const views = @import("views.zig");
const utils = @import("utils.zig");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gio = @import("gio");

pub fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    views.init_application(app);
    const window = switch (arg_.?) {
        .add => views.AddPassword.get(),
        .search => views.SearchPassword.get(),
    };

    std.log.debug("Window.present(SearchPassword)", .{});
    gtk.Window.present(window);
}

var arg_: ?Arg = null;

pub fn main() !void {
    const app = gtk.Application.new("org.gtk.example", gio.ApplicationFlags{});

    arg_ = parse_args();

    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), 0, null);
    std.process.exit(@intCast(status));
}

const Arg = enum { add, search };

fn parse_args() Arg {
    var iter = std.process.args();
    _ = iter.next();
    var result: ?Arg = null;
    while (iter.next()) |arg| {
        if (result != null) {
            std.log.err("accept only 1 argument", .{});
            std.process.exit(1);
        }
        std.debug.print("{s} {}\n", .{ arg, std.mem.eql(u8, arg, "-a") });
        if (std.mem.eql(u8, arg, "-s")) {
            result = .search;
        } else if (std.mem.eql(u8, arg, "-a")) {
            result = .add;
        } else {
            std.log.err("unknown argument {s}", .{arg});
            std.process.exit(1);
        }
    }
    return result orelse .search;
}

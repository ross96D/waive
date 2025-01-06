const std = @import("std");
const gdk = @import("gdk");
const bultin = @import("builtin");

pub const APP_NAME = "waive";

var priv_env: ?std.process.EnvMap = null;
pub fn env() std.process.EnvMap {
    if (bultin.is_test) {
        if (priv_env == null) init(std.testing.allocator);
    }
    return priv_env.?;
}

fn init(allocator: std.mem.Allocator) void {
    priv_env = std.process.EnvMap.init(allocator);
}

pub fn text2clip(text: []const u8) void {
    const display = gdk.Display.getDefault().?;
    const clipboard = gdk.Display.getClipboard(display);
    clipboard.setText(text);
}
